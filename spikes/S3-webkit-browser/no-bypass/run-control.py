#!/usr/bin/env python3
"""S3 no-bypass qualification control (owned loopback fixtures only; no real sites or accounts).

Compiles the product browser sources (from git HEAD or the worktree) with S3NoBypassControl.swift
into an owned carrier app, then runs real WebKit against:
  * sinks.py, an independent sink process (TCP v4/v6, bare connect, TURN, STUN v4/v6, QUIC);
  * serve-fixtures.py --no-bypass-dir, which serves the probe pages on 127.0.0.1;
  * names for owned sinks: random `dns-sd -lo` local-only `.local` records (never announced,
    removed when the run ends; see mdns.json). No LAN hostname is loaded (2026-11-08 safety rule);
    the gateway's post-resolution address check under real WebKit is covered by
    `EgressWebKitGatewayTests`. A `.local` grant must fail configuration (`fc-local-name-grant`).
Owner-free controls (2026-11-14): trusted native `NSEvent` clicks on `target=_blank` (retained
expected-failing like the scripted ones), a persistent `forIdentifier` store seeded outside the
boundary with a service worker and reopened by a product session, two concurrent bots on both
routes, and the owned-fixture task suite (owned-fixture-suite.json, ports rewritten) under Lockdown;
its task success is reported as compatibility, not as a bypass verdict.
Separate-profile controls (D136): profile-sink.py, an owned cookie, storage and cache sink with
one site on two ports (`A`, `A2`) and another site (`B`, as `localhost`), logs every request's
Cookie header. A plain shared store shows B's cookie, storage, cache and service worker coming
along (`positive-shared-profile`); the product, on that store, keeps a same-site move in the
signed-in profile and opens a link or redirect to B in a separate, empty profile that is
discarded with the task (`product-separate-profile`). On the gateway route
(`product-separate-profile-gateway`) a lab of the driver's own injects an owned gateway route
into the product's gateway (its `startGateway` seam and `EgressGateway`'s test resolve/route
seam): reserved `.test` names of two sites resolve to fixed public addresses whose connections are
delivered to the cookie sink, so the product task runner moves, returns and submits forms between
sites through the bot's own gateway client, and one redirect's separate opening is refused by the
route (D136 review F5).
Every run includes positive controls. Pass = zero sink events in every product scenario; the
`target=_blank` scenarios are retained expected-failing controls and are reported, never hidden.
They stay outside the pass only while each stays inside D135's named exception: at most one
empty connection per anchor the page clicked or placed (its accept and read end), no request
and no UDP.
A product scenario counts only if its probe page loaded and reported without a fatal throw; a
path whose API the page lacks is listed (`apiAbsent`), not counted as measured. Each fail-closed
check is judged from what it recorded (a refusal code, a refused load, a probe that failed), never
assumed. After the driver exits, every sink listener gets a probe of its own (liveness.json); a
listener that did not log it was dead, so an empty log is never read as a clean run. A timeline
the driver did not finish, a non-zero driver exit, a dead sink or a sink event that no judged
scenario owns is never a pass.

  run-control.py prepare <label>                 -> prints state.json
  run-control.py build <state.json> <head|worktree>
  run-control.py run <state.json> <head|worktree> [--no-local-names] [--only <scenario>,...]
  run-control.py analyze <run-dir>

`--only` runs the named scenarios alone, for development; such a run is never a complete control.

Run build and run through the build lock. Scratch lives under the owned 0700 $MEMOSHI_BUILD_ROOT.
"""
import json
import os
import plistlib
import re
import select
import shutil
import signal
import stat
import subprocess
import sys
import time
import uuid
from urllib.parse import parse_qs, urlsplit
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
WORK = Path(os.environ.get("MEMOSHI_BUILD_ROOT") or sys.exit("set MEMOSHI_BUILD_ROOT to the owned 0700 build root"))
BROWSER_FILES = ["BrowserSession.swift", "BrowserSessionReview.swift", "BrowserDownloadController.swift",
                 "BrowserFrameTargeting.swift", "BrowserGateway.swift", "BrowserInputSynthesizer.swift",
                 "BrowserLiveView.swift", "BrowserReviewEvidence.swift", "BrowserReviewLab.swift",
                 "BrowserReviewModels.swift", "BrowserReviewReport.swift", "BrowserTaskRunner.swift"]
TREES = ["head", "worktree"]
REQUIRED_POSITIVE = [("tcp", "http4"), ("tcp", "http6"), ("tcp", "preconnect4"), ("tcp", "turn4"),
                     ("udp", "stun-main"), ("udp", "stun6"), ("udp", "quic4")]
# Alternate loopback spellings probe.js sends to the http4 sink; WebKit itself refuses `any`
# (0.0.0.0), so it is reported, not required.
LAN_SPELLINGS = ["short", "hex", "octal", "mapped"]
# Every data: frame path must reach a sink in the positive control.
DATA_TAGS = ["dataimg", "dataiframe", "datafetch", "datacssimport", "datacssbg"]
# What S3NoBypassControl.swift writes only when it finishes, and every scenario it runs (its
# `steps`). A timeline without the schema or without all of them is a truncated run, never a pass.
TIMELINE_SCHEMA = "memoshi.s3-no-bypass-control/1"
EXPECTED_SCENARIOS = ["positive-direct", "positive-direct-sw", "positive-gateway", "positive-blank",
                      "product-fixture", "product-fixture-sw", "product-proxy", "product-fixture-blank",
                      "product-proxy-blank", "fc-unconfigured-navigate", "fc-unconfigured-suite",
                      "fc-immediate-lab-page", "fc-revoked-fixture", "fc-revoked-proxy",
                      "fc-gateway-shutdown", "fc-local-name-grant",
                      # Owner-free controls added 2026-11-14 (design §9): trusted native clicks on
                      # `target=_blank`, a persistent `forIdentifier` store reopened under the product
                      # boundary, two concurrent bots, and the owned-fixture suite under Lockdown.
                      "positive-native-blank", "product-fixture-native-blank", "product-proxy-native-blank",
                      "positive-persistent-seed", "positive-persistent-reopen", "product-persistent-store",
                      "product-concurrent-bots", "product-lockdown-suite",
                      # Separate profile for another site (D136).
                      "positive-shared-profile", "product-separate-profile",
                      "product-separate-profile-gateway",
                      # The D136 review's follow-ups that need the driver itself (F3, F8, F9).
                      "product-separate-profile-edges", "product-rule-list-sweep"]
POSITIVE_SCENARIOS = [name for name in EXPECTED_SCENARIOS if name.startswith("positive-")]
# The product separate-profile run's tasks (S3NoBypassControl.swift).
SEPARATE_TASKS = ["same-site", "cross-site-link-and-return", "cross-site-redirect-and-sso-return",
                  "told-to-open", "cross-site-blank", "cross-site-script", "window-open", "cross-site-form-get",
                  "cross-site-form-post", "post-back-refused",
                  # The D136 review's follow-ups: a sandboxed frame's script move (F1), a form to an
                  # ungranted origin (F4), a form replayed after its hand-off (F7), native typing (F6).
                  "cross-site-sandboxed-frame", "cross-site-form-ungranted", "cross-site-form-replay",
                  "type-long-native", "type-doubled-space"]
# A POST form may be refused instead of opened separately (no body to hand over); it never
# counts against the suite, its own fact decides.
REQUIRED_SEPARATE_TASKS = [task for task in SEPARATE_TASKS if task != "cross-site-form-post"]
# The pages reached in a separate profile, by their `task`.
SEPARATE_PAGE_TASKS = ["link", "redirect", "blank", "script", "formget", "formpost", "pbpage", "sframe",
                       "formreplay"]
# The gateway separate-profile run (S3NoBypassControl.swift `GatewayHosts`): the bot's signed-in
# site (the cookie sink's A), another host of the same registrable domain (A2), another site (B)
# and a site no grant names; its runner tasks, and the separate profiles' pages by their `task`.
GATEWAY_BOT = "bot.d136.memoshi.test"
GATEWAY_SAME_SITE = "www.d136.memoshi.test"
GATEWAY_OTHER = "other.d136.memoshi-other.test"
GATEWAY_UNGRANTED = "ungranted.d136.memoshi-third.test"
GATEWAY_HOSTS = (GATEWAY_BOT, GATEWAY_SAME_SITE, GATEWAY_OTHER)
GATEWAY_TASKS = ["gw-same-site", "gw-link-and-return", "gw-form-post", "gw-form-ungranted", "gw-form-replay",
                 "gw-opening-fails"]
REQUIRED_GATEWAY_TASKS = [task for task in GATEWAY_TASKS if task != "gw-form-post"]
GATEWAY_SEPARATE_PAGE_TASKS = ["gw-link", "gw-formpost", "gw-formreplay"]
# The owned route's refusal of one separate opening (D136 review F5), and how soon the runner must
# report it: the 30 s commit wait F5 removed would take far longer.
GATEWAY_OPENING_REFUSAL = "controlRefusedSeparateGateway"
GATEWAY_OPENING_REPORTED_MS = 5000
SSO_CODE = "d136-code"
# What run-control.py sends each sinks.py TCP listener after the driver exited (liveness.json).
LIVENESS_PREFIX = "MEMOSHI-S3-LIVENESS "
UUID_TEXT = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
# D135's named exception: a `target=_blank` link makes WebKit open one empty connection to the
# link's host before the navigation policy is asked. The sink each anchor target reaches directly
# (`h`, a gateway-only `.invalid` name, reaches none), and the only sink events such a connection
# makes: its accept and, when the sink's read times out, its read end.
BLANK_ANCHOR_SINKS = {"d4": "http4"}
BLANK_ANCHOR_PATHS = ("a-target-blank", "a-target-blank-native")
PRECONNECT_EVENTS = ("tcp-accept", "tcp-read-end")
# The products the carrier app links (prepare's Package.swift), and a manifest's path dependency.
CARRIER_PRODUCTS = [("MemoshiApp", "AppCore"), ("MemoshiApp", "DesignSystem"), ("MemoshiIPC", "MemoshiTransport"),
                    ("MemoshiCore", "MemoshiEgress")]
PACKAGE_PATH = re.compile(r'\.package\(\s*path:\s*"([^"]+)"')


def owned_dir(path):
    facts = path.lstat()
    if not stat.S_ISDIR(facts.st_mode) or facts.st_uid != os.getuid() or stat.S_IMODE(facts.st_mode) != 0o700:
        raise RuntimeError(f"{path} must be an owned non-symlink 0700 directory")


def prepare(label, evidence_root):
    if not label.replace("-", "").isalnum():
        raise RuntimeError("use an alphanumeric run label")
    os.umask(0o077)
    owned_dir(WORK)
    identity = uuid.uuid4().hex[:12]
    scratch = WORK / ("S3NoBypass-" + identity)
    scratch.mkdir(mode=0o700)
    home = scratch / "home"
    for child in ["tmp", "Library/Application Support"]:
        (home / child).mkdir(parents=True, mode=0o700, exist_ok=True)
    package = scratch / "package"
    (package / "Sources/S3NoBypassControl").mkdir(parents=True, mode=0o700)
    pins = REPO / "apps/mac/Memoshi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    shutil.copy2(pins, package / "Package.resolved")
    packages = sorted({name for name, _ in CARRIER_PRODUCTS})
    refs = ", ".join(f'.product(name: "{product}", package: "{name}")' for name, product in CARRIER_PRODUCTS)
    (package / "Package.swift").write_text(
        "// swift-tools-version: 6.4\nimport PackageDescription\n"
        'let package = Package(name: "S3NoBypassCarrier", platforms: [.macOS("27.0")],\n'
        '  products: [.executable(name: "s3-no-bypass-control", targets: ["S3NoBypassControl"])],\n'
        "  dependencies: [" + ", ".join(f'.package(path: {json.dumps(str(REPO / "Packages" / n))})' for n in packages)
        + "],\n  targets: [.executableTarget(name: \"S3NoBypassControl\", dependencies: [" + refs + "])])\n")
    run = Path(evidence_root) / ("control-" + label + "-" + identity)
    run.mkdir(mode=0o700)
    state = {"run": str(run), "scratch": str(scratch), "home": str(home), "package": str(package),
             "bundlePrefix": "com.memoshi.s3-no-bypass." + identity, "identity": identity}
    with (run / "state.json").open("x") as stream:
        json.dump(state, stream, indent=2)
    print(run / "state.json")


def load_state(path):
    state = json.loads(Path(path).read_text())
    scratch = Path(state["scratch"])
    if scratch.parent != WORK or not scratch.name.startswith("S3NoBypass-"):
        raise RuntimeError(f"{scratch} is not an S3NoBypass- scratch directly below {WORK}")
    owned_dir(scratch)
    return state


def build_env(state):
    return {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ.get("HOME", "/tmp"),
            "LANG": "en_US.UTF-8", "TMPDIR": str(WORK / "tmp"), "GIT_ALLOW_PROTOCOL": "file",
            "GIT_TERMINAL_PROMPT": "0", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "CLANG_MODULE_CACHE_PATH": str(WORK / "cache/clang"),
            "SWIFTPM_MODULECACHE_OVERRIDE": str(WORK / "cache/swift")}


def source_bytes(tree, relative):
    if tree == "worktree":
        return (REPO / relative).read_bytes()
    return subprocess.run(["/usr/bin/git", "-C", str(REPO), "show", "HEAD:" + relative],
                          check=True, capture_output=True).stdout


def carrier_packages():
    """Every repository package the carrier builds from source: its products' packages and their
    `.package(path:)` dependencies inside `Packages/`, sorted. A path outside the repository
    (Pi_Swift) is pinned by its own prerequisite check."""
    packages = (REPO / "Packages").resolve()
    found, pending = set(), sorted({name for name, _ in CARRIER_PRODUCTS})
    while pending:
        name = pending.pop()
        if name in found:
            continue
        found.add(name)
        for path in PACKAGE_PATH.findall((packages / name / "Package.swift").read_text()):
            target = (packages / name / path).resolve()
            if target.parent == packages:
                pending.append(target.name)
    return sorted(found)


def package_changes():
    """The carrier packages' paths that differ from HEAD: modified, staged, deleted or untracked."""
    status = subprocess.run(["/usr/bin/git", "-C", str(REPO), "status", "--porcelain=v1", "--untracked-files=all",
                             "--"] + ["Packages/" + name for name in carrier_packages()],
                            check=True, capture_output=True, text=True).stdout
    return [line[3:] for line in status.splitlines() if line.strip()]


def build(state, tree):
    run = Path(state["run"])
    head = subprocess.run(["/usr/bin/git", "-C", str(REPO), "rev-parse", "HEAD"], check=True, capture_output=True,
                          text=True).stdout.strip()
    # SwiftPM builds the carrier's packages from the worktree, whichever tree the app files come
    # from; HEAD's app files compile against them only while they are HEAD's too.
    changed = package_changes()
    if tree == "head" and changed:
        raise RuntimeError("head build refused: it compiles HEAD's app files against the worktree packages, "
                           "which differ from HEAD in " + ", ".join(changed)
                           + "; commit them, or build the worktree tree")
    sources = Path(state["package"]) / "Sources/S3NoBypassControl"
    for old in sources.iterdir():
        old.unlink()
    manifest = []
    for relative in ["apps/mac/Memoshi/" + name for name in BROWSER_FILES] + ["apps/shared/BrowserReviewProfile.swift"]:
        data = source_bytes(tree, relative)
        (sources / Path(relative).name).write_bytes(data)
        manifest.append({"source": relative, "tree": tree, "bytes": len(data)})
    shutil.copy2(HERE / "S3NoBypassControl.swift", sources / "S3NoBypassControl.swift")
    with (run / f"sources-{tree}.json").open("x") as stream:
        json.dump({"head": head, "tree": tree, "sources": manifest,
                   "packages": "worktree " + ", ".join("Packages/" + name for name in carrier_packages()),
                   "packagesMatchHead": not changed, "packageChanges": changed}, stream, indent=2)
    args = ["--package-path", state["package"], "--scratch-path", str(Path(state["scratch"]) / "build"),
            "--cache-path", str(WORK / "cache"), "--disable-keychain", "--disable-netrc",
            "--disable-experimental-prebuilts"]
    env = build_env(state)
    for label, command in [("resolve", ["/usr/bin/swift", "package"] + args + ["--skip-update", "resolve"]),
                           ("build", ["/usr/bin/swift", "build"] + args + ["--disable-automatic-resolution",
                            "--jobs", "1", "-debug-info-format", "none", "--product", "s3-no-bypass-control"])]:
        with (run / f"{label}-{tree}.log").open("x") as log:
            code = subprocess.run(command, cwd=str(REPO), env=env, stdout=log, stderr=subprocess.STDOUT).returncode
        if code:
            print(f"{label} failed; see {run / (label + '-' + tree + '.log')}")
            return code
    binary = Path(state["scratch"]) / "build/debug/s3-no-bypass-control"
    app = Path(state["scratch"]) / f"S3NoBypass-{tree}.app"
    if app.exists():
        shutil.rmtree(app)
    (app / "Contents/MacOS").mkdir(parents=True, mode=0o700)
    shutil.copy2(binary, app / "Contents/MacOS/s3-no-bypass-control")
    with (app / "Contents/Info.plist").open("xb") as stream:
        plistlib.dump({"CFBundleExecutable": "s3-no-bypass-control",
                       "CFBundleIdentifier": state["bundlePrefix"] + "." + tree,
                       "CFBundleName": "Owned S3 No-Bypass Control", "CFBundlePackageType": "APPL",
                       "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
                       "LSMinimumSystemVersion": "27.0", "NSHighResolutionCapable": True,
                       "NSAppTransportSecurity": {"NSAllowsArbitraryLoadsInWebContent": True,
                                                  "NSAllowsLocalNetworking": True}}, stream)
    for resource in binary.parent.glob("*.bundle"):
        shutil.copytree(resource, app / "Contents/Resources" / resource.name)
    return 0


def free_port():
    import socket
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def wait_file(path, seconds=15):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if path.exists() and path.stat().st_size:
            return
        time.sleep(0.1)
    raise RuntimeError(f"{path} was not written")


def spawn(command, log, **options):
    """Starts a helper process that writes to `log`, which is created and never replaced. The
    parent closes its copy at once; the child keeps its own."""
    with log.open("x") as stream:
        return subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, **options)


def resolve_numeric(name):
    """Numeric answers from the system resolver, without zones; [] when the name does not resolve."""
    import socket
    try:
        infos = socket.getaddrinfo(name, 9, proto=socket.IPPROTO_TCP)
    except OSError:
        return []
    return sorted({info[4][0].split("%")[0] for info in infos})


def register_names(out, ports, run_id, processes):
    """Names that resolve to owned sinks, for the probe's `mdns*` targets.

    Random `.local` host records registered with `dns-sd -lo` on mDNSResponder's local-only
    interface (resolvable on this Mac, never announced), for the http4 sink and the first own
    IPv4 sink. Each name gets its A record and the same address as a v4-mapped AAAA record: with
    an A record alone every lookup waits 5 s for the missing family, longer than the probe's
    per-load bound. They are deregistered when their dns-sd processes stop. The host's LAN name
    is never used: a LAN hostname is not loaded even when it answers with this Mac's own address.
    Each dns-sd process is appended to `processes` as it starts, so the caller stops every one.
    Returns the extra port entries and the facts for mdns.json."""
    extra = {}
    targets = [("127.0.0.1", ports["http4"])]
    targets += [(label[4:], port) for label, port in sorted(ports.items())
                if label.startswith("own:") and ":" not in label[4:]][:1]
    facts = {"interface": "LocalOnly (kDNSServiceInterfaceIndexLocalOnly)", "records": [],
             "lanName": "not used: LAN hostnames are never loaded"}
    for index, (address, port) in enumerate(targets):
        name = f"memoshi-{run_id}-{index}.local"
        for family, record in (("4", address), ("6", "::ffff:" + address)):
            processes.append(spawn(
                ["/usr/bin/dns-sd", "-lo", "-P", f"memoshi-s3-{run_id}-{index}-{family}", "_memoshi-s3._tcp",
                 "local", str(port), name, record], out / f"dns-sd-{index}-{family}.log"))
        deadline = time.time() + 10
        while address not in resolve_numeric(name) and time.time() < deadline:
            time.sleep(0.1)
        started = time.time()
        answers = resolve_numeric(name)
        facts["records"].append({"name": name, "address": address, "port": port, "resolvedBefore": answers,
                                 "lookupSeconds": round(time.time() - started, 2)})
        if address in answers:
            extra["mdns:" + name] = port
    return extra, facts


def stop(process):
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def ready_record(log, key):
    """A sink log's `ready` record (`key` is `kind` for sinks.py, `listener` for profile-sink.py)."""
    if not log.exists():
        return {}
    for line in log.read_text().splitlines():
        record = json.loads(line)
        if record.get(key) == "ready":
            return record
    return {}


def probe_liveness(sink_log, profile_log, nonce):
    """One probe of its own for every listener the sinks' `ready` records name, sent after the
    driver exited and before the sinks stop: a line on each sinks.py TCP listener (it logs the
    first line and closes), a datagram to each UDP one, a GET /liveness to each profile-sink.py
    listener. The analyzer finds each in the logs; a dead sink or listener logs none."""
    import socket
    probes = []

    def family(host):
        return socket.AF_INET6 if ":" in host else socket.AF_INET

    for index, listener in enumerate(ready_record(sink_log, "kind").get("listeners") or []):
        token = f"{nonce}-{index}"
        probe = {"sink": "sinks", "label": listener["label"], "kind": listener["kind"], "token": token}
        try:
            if listener["kind"] == "udp":
                with socket.socket(family(listener["host"]), socket.SOCK_DGRAM) as sock:
                    # Bound first, so the address the sink logs is the one recorded here.
                    sock.bind((listener["host"], 0))
                    sock.sendto(token.encode(), (listener["host"], listener["port"]))
                    probe.update(peer=str(sock.getsockname()), bytes=len(token.encode()))
            else:
                with socket.create_connection((listener["host"], listener["port"]), timeout=5) as sock:
                    probe["peer"] = str(sock.getsockname())
                    sock.sendall((LIVENESS_PREFIX + token + "\r\n\r\n").encode())
                    sock.recv(1)
            probe["sent"] = True
        except OSError as error:
            probe.update(sent=False, error=type(error).__name__)
        probes.append(probe)
    for index, listener in enumerate(ready_record(profile_log, "listener").get("listeners") or []):
        token = f"{nonce}-p{index}"
        probe = {"sink": "profile", "label": listener["label"], "host": listener["host"], "token": token}
        try:
            with socket.create_connection((listener["host"], listener["port"]), timeout=5) as sock:
                sock.sendall(f"GET /liveness?n={token} HTTP/1.1\r\nHost: liveness\r\nConnection: close\r\n\r\n"
                             .encode())
                probe["status"] = sock.recv(64).decode("latin-1", "replace").split("\r\n", 1)[0]
            probe["sent"] = True
        except OSError as error:
            probe.update(sent=False, error=type(error).__name__)
        probes.append(probe)
    return probes


def run(state, tree, local_names=True, only=None):
    out = Path(state["run"]) / ("run-" + tree)
    out.mkdir(mode=0o700)
    run_id = uuid.uuid4().hex[:8]
    env = {"PATH": "/usr/bin:/bin", "HOME": state["home"], "CFFIXED_USER_HOME": state["home"],
           "TMPDIR": state["home"] + "/tmp", "LANG": "en_US.UTF-8"}
    if only:
        env["S3_CONTROL_ONLY"] = ",".join(only)
    sinks = spawn([sys.executable, "-B", str(HERE / "sinks.py"), str(out / "sinks.jsonl"),
                   str(out / "sink-ports.json")], out / "sinks.log", env=env)
    profile = spawn([sys.executable, "-B", str(HERE / "profile-sink.py"), str(out / "profile-sink.jsonl"),
                     str(out / "profile-ports.json")], out / "profile-sink.log", env=env)
    main_port, frame_port = free_port(), free_port()
    fixture = subprocess.Popen([sys.executable, "-B", str(HERE.parent / "serve-fixtures.py"), "--port", str(main_port),
                                "--frame-port", str(frame_port), "--no-bypass-dir", str(HERE)], env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    processes, facts = [], {}
    try:
        wait_file(out / "sink-ports.json")
        ready, _, _ = select.select([fixture.stdout], [], [], 15)
        if not ready:
            raise RuntimeError("fixture readiness deadline")
        (out / "fixture-start.log").write_bytes(fixture.stdout.readline())
        ports = json.loads((out / "sink-ports.json").read_text())
        wait_file(out / "profile-ports.json")
        profile_ports = {"profile-" + key: port for key, port in
                         json.loads((out / "profile-ports.json").read_text()).items()}
        if local_names:
            extra, facts = register_names(out, ports, run_id, processes)
        else:
            # The `.local` positive needs the Local Network permission; without names it is
            # reported as not run, and `fc-local-name-grant` as skipped.
            extra, facts = {}, {"skipped": "--no-local-names: no `.local` name registered", "records": []}
        with (out / "control-ports.json").open("x") as stream:
            # `fixture-frame`: the owned frame fixture, for the Lockdown owned-fixture suite.
            # `profile-*`: the separate-profile control's cookie sink listeners.
            json.dump(dict(ports, **extra, **{"fixture-frame": frame_port}, **profile_ports), stream,
                      sort_keys=True)
        binary = Path(state["scratch"]) / f"S3NoBypass-{tree}.app/Contents/MacOS/s3-no-bypass-control"
        command = [str(binary), str(out), str(out / "control-ports.json"), f"http://127.0.0.1:{main_port}",
                   str(HERE / "probe.js"), run_id, state["bundlePrefix"] + "." + tree,
                   str(HERE.parent / "owned-fixture-suite.json")]
        with (out / "control-command.json").open("x") as stream:
            json.dump({"argv": command, "credentialEnvironmentInherited": False}, stream, indent=2)
        with (out / "control.log").open("x") as log:
            try:
                code = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=1500).returncode
            except subprocess.TimeoutExpired:
                code = 124
        time.sleep(2)
        # The sinks are still running: each listener must answer a probe of its own.
        liveness = {"nonce": run_id, "startedAt": time.time(), "sinksProcessRunning": sinks.poll() is None,
                    "profileSinkProcessRunning": profile.poll() is None}
        liveness["probes"] = probe_liveness(out / "sinks.jsonl", out / "profile-sink.jsonl",
                                            run_id + "-" + uuid.uuid4().hex[:8])
        time.sleep(0.5)
        with (out / "liveness.json").open("x") as stream:
            json.dump(liveness, stream, indent=2, sort_keys=True)
    finally:
        stop(fixture)
        fixture.stdout.close()
        stop(sinks)
        stop(profile)
        for process in processes:
            stop(process)
        time.sleep(1)
        for record in facts.get("records", []):
            record["resolvedAfterRemoval"] = resolve_numeric(record["name"])
        with (out / "mdns.json").open("x") as stream:
            json.dump(facts, stream, indent=2, sort_keys=True)
    (out / "control-exit.json").write_text(json.dumps({"exitCode": code}))
    summary = analyze(out)
    print(json.dumps(summary["verdict"], indent=2))
    return code


def analyze(out):
    out = Path(out)
    timeline = json.loads((out / "timeline.json").read_text())
    raw_events = [json.loads(line) for line in (out / "sinks.jsonl").read_text().splitlines()]
    ports = json.loads((out / "sink-ports.json").read_text())
    own = sorted(label for label in ports if label.startswith("own:"))
    lan_keys = LAN_SPELLINGS + ["own" + "".join(c for c in label[4:] if c in "0123456789abcdefABCDEF")
                                for label in own]
    # Names registered for this run (absent in runs before they existed): `mdns0`, `mdns1`, ...
    named = out / "control-ports.json"
    named = json.loads(named.read_text()) if named.exists() else {}
    lan_keys += [f"mdns{i}" for i, _ in enumerate(sorted(k for k in named if k.startswith("mdns:")))]
    profile_log = out / "profile-sink.jsonl"
    raw_profile = [json.loads(line) for line in profile_log.read_text().splitlines()] if profile_log.exists() else []
    # The probes run-control.py sent after the driver exited are not scenario events; each must
    # have been logged, or a sink was dead and its empty log says nothing.
    liveness, raw_events, raw_profile = sink_liveness(out, raw_events, raw_profile)
    events = [e for e in raw_events if e["kind"] != "ready"]
    profile_events = [e for e in raw_profile if e.get("listener") != "ready"]
    exit_file = out / "control-exit.json"
    exit_code = json.loads(exit_file.read_text()).get("exitCode") if exit_file.exists() else None
    # A scenario owns every sink event from its start until the next scenario starts (the last
    # one until the sinks stop): the driver pauses between scenarios, and a connection that
    # lands in that pause is still a connection.
    starts = sorted(scenario["start"] for scenario in timeline["scenarios"])
    unattributed = sum(1 for e in events if not starts or e["t"] < starts[0])
    rows = []
    for scenario in timeline["scenarios"]:
        until = next((start for start in starts if start > scenario["start"]), float("inf"))
        window = [e for e in events if scenario["start"] <= e["t"] < until]
        profile_window = [e for e in profile_events if scenario["start"] <= e["t"] < until]
        by_class = {}
        paths = {}
        for e in window:
            key = ("tcp" if e["kind"].startswith("tcp") else "udp") + ":" + e["label"]
            counts = by_class.setdefault(key, {})
            counts[e["kind"]] = counts.get(e["kind"], 0) + 1
            if e["kind"] == "tcp-data":
                parts = e.get("first", "").split(" ")
                target = parts[1] if len(parts) > 1 else ""
                segments = target.split("?")[0].split("/")
                tag = segments[3] if len(segments) > 3 else "(untagged)"
                paths[tag] = paths.get(tag, 0) + 1
        gateway = list(scenario.get("gateway") or [])
        for bot in scenario.get("bots") or []:
            gateway += bot.get("gateway") or []
        probe_hosts = sorted({d["host"] for d in gateway if d["host"].endswith(".probe.memoshi.invalid")})
        local_hosts = sorted({d["host"] for d in gateway if is_local_host(d["host"])})
        row = {"name": scenario["name"], "kind": scenario.get("kind"), "sinkEvents": len(window),
               "byClass": by_class, "taggedPaths": paths,
               "gatewayDecisions": len(gateway),
               "gatewayAllowed": sum(1 for d in gateway if d.get("allowed")),
               "gatewayProbeHosts": len(probe_hosts),
               "gatewayLocalHosts": local_hosts,
               "lanTagsReached": sorted({t.split("-", 1)[1] for t in paths if "-" in t and t.split("-", 1)[1] in lan_keys}),
               "error": scenario.get("error")}
        page = scenario.get("page")
        probe_ran = page_ran(page, scenario.get("navigation", "started"))
        if isinstance(page, dict):
            results = page.get("results") or []
            row["pageReport"] = "missing" if page.get("missing") else f"{len(results)} results"
            row["apiAbsent"] = api_absent(page)
            feature = next((r for r in results if r.get("path") == "features"), None)
            if feature:
                row["features"] = json.loads(feature["outcome"])
        for key in ["navigation", "immediateResult", "laterResult", "fixtureRequestsDuring", "outcome",
                    "suiteOutcome", "addressResult", "immediateLoadStarted", "laterURL", "configurationCodes",
                    "reason", "configurationProblem", "nativeClicks", "storeMarker", "reopenedImmediateResult",
                    "lockdownActive", "separateProfiles", "separateMarkOnDisk", "separateRuleListsLeft",
                    "separateStoreIdentifiers", "separateBoundary", "profileBoundary", "separateGateway",
                    "separateSettle", "suiteProblem", "profilePageHostAfter", "profileCommitsDuringMove",
                    "returnClick", "returnSettle", "profileURLAfterReturn", "returnSeparateCodes"]:
            if key in scenario:
                row[key] = scenario[key]
        name = scenario["name"]
        if name in ("positive-direct",):
            missing = [f"{k}:{l}" for k, l in REQUIRED_POSITIVE if f"{k}:{l}" not in by_class]
            missing += [f"tcp:{label}" for label in own if f"tcp:{label}" not in by_class]
            missing += [f"lan:{key}" for key in lan_keys if key not in row["lanTagsReached"]]
            missing += [f"data:{tag}" for tag in DATA_TAGS if not any(t.startswith(tag + "-") for t in paths)]
            row["restrictedPortRefusedBeforeConnect"] = (
                "badport4" in ports and "tcp:badport4" not in by_class)
            if not row["restrictedPortRefusedBeforeConnect"]:
                missing.append("badport4 refused before connect")
            row["webKitRefusedUnspecified"] = not any(t.endswith("-any") for t in paths)
            row["controlExercised"] = not missing
            row["missingPositiveClasses"] = missing
        elif name == "positive-direct-sw":
            row["controlExercised"] = any(t.startswith("sw-") for t in paths)
        elif name == "positive-gateway":
            row["controlExercised"] = len(probe_hosts) > 0 and "tcp:http4" in by_class
        elif name == "positive-blank":
            row["controlExercised"] = "tcp:http4" in by_class
        elif name == "positive-native-blank":
            row["nativeClicksTrusted"] = native_clicks_trusted(scenario)
            row["controlExercised"] = row["nativeClicksTrusted"] and "tcp:http4" in by_class
        elif name == "positive-persistent-seed":
            row["storeMarkerPresent"] = marker_present(scenario, timeline.get("run"))
            row["controlExercised"] = row["storeMarkerPresent"] and any(t.startswith("sw-") for t in paths)
        elif name == "positive-persistent-reopen":
            # The seeded worker must fire again from the reopened store, or the store was not reused.
            row["storeMarkerPresent"] = marker_present(scenario, timeline.get("run"))
            row["controlExercised"] = row["storeMarkerPresent"] and any(t.startswith("swresurrect-") for t in paths)
        elif name == "positive-shared-profile":
            row["sharedProfile"] = shared_profile_facts(profile_window, scenario.get("marks") or {})
            row["controlExercised"] = all(row["sharedProfile"].values())
        elif name.endswith("-blank"):
            row["expectedFailingControl"] = True
            row["probeRan"] = probe_ran
            row["onlyEmptyPreconnect"] = only_empty_preconnect(page, window)
            row["passed"] = probe_ran and len(window) == 0
            if "native" in name:
                # Zero connections count only if every placed anchor got a trusted native click.
                row["nativeClicksTrusted"] = native_clicks_trusted(scenario)
                row["passed"] = row["passed"] and row["nativeClicksTrusted"]
        elif scenario.get("kind") == "product":
            extra = True
            if name == "product-persistent-store":
                row["storeMarkerPresent"] = marker_present(scenario, timeline.get("run"))
                extra = row["storeMarkerPresent"] and scenario.get("reopenedImmediateResult") not in (None, "loadStarted")
            elif name == "product-concurrent-bots":
                bots = scenario.get("bots") or []
                row["bots"] = [{"name": b.get("name"), "route": b.get("route"),
                                "probeRan": page_ran(b.get("page"), b.get("navigation", "started")),
                                "gatewayDecisions": len(b.get("gateway") or [])} for b in bots]
                row["apiAbsent"] = [f"{b.get('name')}: {entry}" for b in bots for entry in api_absent(b.get("page"))]
                # Both probes were in flight at once: each started before the other reported.
                row["overlapped"] = len(bots) == 2 and all(
                    isinstance(b.get("loadStarted"), (int, float)) and isinstance(b.get("reported"), (int, float))
                    for b in bots) and max(b["loadStarted"] for b in bots) < min(b["reported"] for b in bots)
                probe_ran = len(bots) == 2 and all(b["probeRan"] for b in row["bots"])
            elif name == "product-lockdown-suite":
                row["suite"] = suite_compatibility(scenario)
                # A completed suite ran only if an owned page loaded in it at least once.
                probe_ran = row["suite"]["state"] == "completed" and row["suite"]["navigated"] > 0
                extra = row["suite"]["lockdownActive"]
            elif name == "product-separate-profile":
                row["separateProfile"] = direct_separate_facts(scenario, profile_window)
                row["formPostOutcome"] = form_post_outcome(scenario, profile_window)
                probe_ran = row["separateProfile"]["suiteCompleted"]
                extra = all(row["separateProfile"].values())
            elif name == "product-separate-profile-gateway":
                row["separateProfile"] = gateway_separate_facts(scenario, profile_window)
                probe_ran = row["separateProfile"]["suiteCompleted"]
                extra = all(row["separateProfile"].values())
            elif name == "product-separate-profile-edges":
                row["separateProfile"] = edge_facts(scenario, profile_window)
                probe_ran = (row["separateProfile"]["cancelDuringReturn"]
                             and row["separateProfile"]["reauthorizeOpenedSeparate"]
                             and row["separateProfile"]["uploadStagedInSeparate"])
                extra = all(row["separateProfile"].values())
            elif name == "product-rule-list-sweep":
                row["separateProfile"] = sweep_facts(scenario)
                probe_ran = row["separateProfile"]["leftoversPlanted"]
                extra = all(row["separateProfile"].values())
            row["probeRan"] = probe_ran
            row["passed"] = (probe_ran and extra and len(window) == 0 and not scenario.get("error")
                             and row.get("gatewayProbeHosts", 0) == 0 and not local_hosts
                             and row.get("overlapped", True))
        elif scenario.get("kind") == "failClosed":
            # Each check is judged from what it recorded; a name without checks never passes.
            row["failClosed"] = fail_closed_facts(scenario)
            refused = bool(row["failClosed"]) and all(row["failClosed"].values())
            row["passed"] = refused and len(window) == 0 and not scenario.get("error")
        if "controlExercised" not in row and "passed" not in row:
            # A failed or skipped scenario has no verdict of its own to carry its sink events.
            unattributed += len(window)
        rows.append(row)
    positives = [r for r in rows if "controlExercised" in r]
    product = [r for r in rows if r.get("kind") == "product" and not r.get("expectedFailingControl")]
    fail_closed = [r for r in rows if r.get("kind") == "failClosed"]
    blank = [r for r in rows if r.get("expectedFailingControl")]
    names = [r["name"] for r in rows]
    missing_scenarios = [name for name in EXPECTED_SCENARIOS if names.count(name) != 1]
    verdict = {
        # The driver finished, exited cleanly and recorded each of its scenarios exactly once.
        "timelineComplete": (timeline.get("schema") == TIMELINE_SCHEMA and exit_code == 0
                             and not missing_scenarios and not timeline.get("only")),
        # `--only`: the scenarios a development run was limited to.
        "scenarioFilter": timeline.get("only"),
        # Every sink listener logged its own probe after the driver exited (liveness.json).
        "sinksAlive": liveness["alive"],
        "sinkLiveness": liveness,
        "controlExitCode": exit_code,
        "missingScenarios": missing_scenarios,
        # Sink events before the first scenario or inside one that has no verdict.
        "unattributedSinkEvents": unattributed,
        "positiveControlsExercised": (all(r["controlExercised"] for r in positives)
                                      and len(positives) == len(POSITIVE_SCENARIOS)),
        "productScenariosZeroSinkEvents": all(r.get("passed") for r in product),
        "failClosedChecksPassed": all(r.get("passed") for r in fail_closed),
        "targetBlankExpectedFailures": {r["name"]: r["sinkEvents"] for r in blank},
        # D135 accepts one empty connection per anchor; a request, UDP or a second connection is not.
        "retainedBlankOnlyEmptyPreconnect": all(r["onlyEmptyPreconnect"] for r in blank),
        # Paths that measured nothing because the page lacked their API, by scenario.
        "apiAbsent": {r["name"]: r["apiAbsent"] for r in rows if r.get("apiAbsent")},
        "perScenarioSinkEvents": {r["name"]: r["sinkEvents"] for r in rows},
        "ownAddressSinks": own,
        "positiveGatewayLocalHosts": next((r["gatewayLocalHosts"] for r in rows if r["name"] == "positive-gateway"), None),
        "driverFailures": timeline.get("failures", []),
        "skippedScenarios": {r["name"]: r.get("reason") for r in rows if r.get("kind") == "skipped"},
        "namedTargets": sorted(k for k in lan_keys if k.startswith("mdns")),
        "nativeClicksTrusted": {r["name"]: r["nativeClicksTrusted"] for r in rows if "nativeClicksTrusted" in r},
        "lockdownOwnedFixtureSuite": next((r["suite"] for r in rows if r["name"] == "product-lockdown-suite"), None),
        # Every gateway decision's refusal reason, across scenarios.
        "gatewayReasons": _tally(d.get("reason") for scenario in timeline["scenarios"]
                                 for d in scenario.get("gateway") or []),
    }
    by_row = {r["name"]: r for r in rows}
    shared = by_row.get("positive-shared-profile", {})
    direct = by_row.get("product-separate-profile", {})
    gateway = by_row.get("product-separate-profile-gateway", {})
    edges = by_row.get("product-separate-profile-edges", {})
    sweep = by_row.get("product-rule-list-sweep", {})
    verdict["separateProfile"] = {
        "shared": shared.get("sharedProfile", {}), "direct": direct.get("separateProfile", {}),
        "gateway": gateway.get("separateProfile", {}), "edges": edges.get("separateProfile", {}),
        "sweep": sweep.get("separateProfile", {}),
        "formPostOutcome": direct.get("formPostOutcome"),
        "passed": bool(shared.get("controlExercised") and direct.get("passed") and gateway.get("passed")
                       and edges.get("passed") and sweep.get("passed")),
    }
    verdict["passExcludingRetainedBlankControl"] = (verdict["timelineComplete"]
        and verdict["positiveControlsExercised"]
        and verdict["productScenariosZeroSinkEvents"] and verdict["failClosedChecksPassed"]
        and verdict["retainedBlankOnlyEmptyPreconnect"] and verdict["sinksAlive"]
        and not verdict["driverFailures"] and unattributed == 0)
    verdict["strictPass"] = verdict["passExcludingRetainedBlankControl"] and all(r.get("passed") for r in blank)
    summary = {"schema": "memoshi.s3-no-bypass-summary/1", "rows": rows, "verdict": verdict}
    (out / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True))
    return summary


def _tally(values):
    """Counts by value; keys are text, so an allowed decision's missing reason sorts with the rest."""
    counts = {}
    for value in values:
        key = str(value)
        counts[key] = counts.get(key, 0) + 1
    return counts


def is_local_host(host):
    """An IP literal, `localhost` or `.local` name: none may ever reach the gateway from a product page."""
    name = host.strip("[]").rstrip(".").lower()
    if name == "localhost" or name.endswith(".localhost") or name.endswith(".local"):
        return True
    try:
        import ipaddress
        ipaddress.ip_address(name)
        return True
    except ValueError:
        return False


def cookies(header):
    """A Cookie header or `document.cookie` as name -> value."""
    jar = {}
    for part in (header or "").split(";"):
        name, _, value = part.strip().partition("=")
        if name:
            jar[name] = value
    return jar


def sink_reports(window):
    """What each profile-sink page reported to /report, by its task (the first report wins)."""
    found = {}
    for e in window:
        if e.get("path") == "/report" and "seen" in (e.get("query") or {}):
            try:
                facts = json.loads(e["query"]["seen"])
            except ValueError:
                continue
            if isinstance(facts, dict):
                found.setdefault(facts.get("task"), facts)
    return found


def saw_nothing(facts):
    """A separate profile's page saw none of the bot profile's cookie, storage or worker."""
    return (isinstance(facts, dict) and "d136" not in cookies(facts.get("cookie"))
            and facts.get("storage") is None and facts.get("controlled") is False)


def normalized(code):
    """A configuration or boundary code with profile identities removed, for comparing profiles."""
    return UUID_TEXT.sub("<id>", code or "")


def shared_profile_facts(window, marks):
    """Outside the boundary one store follows a link to B: B's cookie, storage and worker come
    along, and the store's HTTP cache serves A's script again without a request (measured at A:
    a worker-controlled page at B re-requests its script). Without this the separate-profile
    checks would show nothing."""
    page = next((e for e in window if e["listener"] == "B" and e["path"] == "/page"
                 and e["query"].get("task") == "shared"), None)
    from_page = next((e for e in window if e["listener"] == "A" and e["path"] == "/page"
                      and e["query"].get("task") == "shared-from"), None)
    seen = sink_reports(window).get("shared") or {}
    return {"cookieShared": page is not None and cookies(page.get("cookie")).get("d136") == marks.get("B"),
            "storageShared": marks.get("B") is not None and seen.get("storage") == marks.get("B"),
            "cacheShared": from_page is not None and any(
                e["listener"] == "A" and e["path"] == "/cached.js" and e["t"] < from_page["t"] for e in window)
            and not any(e["listener"] == "A" and e["path"] == "/cached.js" and e["t"] > from_page["t"]
                        for e in window),
            "serviceWorkerShared": any(e["path"] == "/sw-hit" for e in window)}


def referer_task(event):
    """The `task` of the page a subresource was loaded for."""
    query = urlsplit(event.get("referer") or "").query
    return (parse_qs(query).get("task") or [None])[0]


def form_post_outcome(scenario, window):
    """How the cross-site POST form ended: opened in a separate profile with its body, refused
    because WebKit gave no body to hand over, or neither (a failure)."""
    if any(e["listener"] == "B" and e["path"] == "/page" and e.get("method") == "POST"
           and e["query"].get("task") == "formpost" for e in window):
        return "separateWithBody"
    if "form:false:separateProfileFormBodyUnavailable" in (scenario.get("configurationCodes") or []):
        return "refusedWithoutBody"
    return "none"


def task_window(scenario, task):
    """When the runner worked on `task`, as the driver saw it reach each task (`taskStarts`):
    from its start until the next task's; None when the driver never saw it."""
    starts = [s for s in scenario.get("taskStarts") or [] if isinstance(s.get("at"), (int, float))]
    for index, start in enumerate(starts):
        if start.get("task") == task:
            return start["at"], starts[index + 1]["at"] if index + 1 < len(starts) else float("inf")
    return None


def suite_step(suite, task, operation):
    """The first recorded step of `task` with `operation`, or {}."""
    return next((s for s in suite.get("steps") or [] if s.get("taskID") == task and s.get("operation") == operation),
                {})


def direct_separate_facts(scenario, window):
    """The product run on the seeded store (owned-fixture route). The bot's profile keeps a
    same-site move, a site its cookies belong to, and every return (a link back, an SSO-style
    redirect back); a link, a redirect, a `_blank` link, a script move, a sandboxed frame's
    script move and a confirmed form to B open a new separate, empty profile on the same route,
    rules and Lockdown, discarded with the task; `window.open` never reaches B in the bot's
    profile. A form to an ungranted origin is refused at the click and opens nothing; a form
    replayed into a frame after its hand-off is refused; native typing matches the field exactly."""
    marks = scenario.get("marks") or {}

    def pages(listener, task):
        return [e for e in window if e["listener"] == listener and e["path"] == "/page"
                and e["query"].get("task") == task]

    def own_cookie(event, key):
        return cookies(event.get("cookie")).get("d136") == marks.get(key)

    seen = sink_reports(window)
    separate = [e for e in window if e["listener"] == "B" and (
        e["query"].get("task") in SEPARATE_PAGE_TASKS or referer_task(e) in SEPARATE_PAGE_TASKS
        or (e["path"] == "/report" and (sink_reports([e]) or {}).keys() & set(SEPARATE_PAGE_TASKS)))]
    command = pages("B", "command")
    suite = scenario.get("suite") or {}
    profiles = scenario.get("separateProfiles") or []
    post = form_post_outcome(scenario, window)

    boundary = boundary_codes

    def reached_separately(task):
        return bool(pages("B", task)) and saw_nothing(seen.get(task))

    own = boundary(scenario.get("configurationCodes") or [])
    bot = scenario.get("profileDecisions") or []

    def during(task, at):
        span = task_window(scenario, task)
        return span is not None and isinstance(at, (int, float)) and span[0] <= at < span[1]

    def bot_codes(task):
        return [d.get("code") for d in bot if during(task, d.get("at"))]

    def posted(task, note):
        return [e for e in window if e.get("method") == "POST" and e["query"].get("task") == task
                and (e.get("form") or {}).get("note") == note]

    ungranted = "cross-site-form-ungranted"
    typed, doubled = suite_step(suite, "type-long-native", "type"), suite_step(suite, "type-doubled-space", "type")
    return {
        "suiteCompleted": suite.get("state") == "completed"
        and set(REQUIRED_SEPARATE_TASKS) <= set(suite.get("successfulTasks") or []),
        "sameSiteKeptProfile": any(own_cookie(e, "A") for e in pages("A2", "same")),
        "redirectSourceInProfile": any(own_cookie(e, "A") for e in window
                                       if e["listener"] == "A" and e["path"] == "/redirect"),
        "crossSiteLinkSeparate": reached_separately("link"),
        "crossSiteRedirectSeparate": reached_separately("redirect"),
        "blankLinkSeparate": reached_separately("blank"),
        "scriptMoveSeparate": reached_separately("script"),
        "confirmedGetFormSeparate": reached_separately("formget"),
        "postFormNeverInProfile": post == "refusedWithoutBody"
        or (post == "separateWithBody" and saw_nothing(seen.get("formpost"))),
        "linkBackReturnsToProfile": any(own_cookie(e, "A") for e in pages("A", "return")),
        "ssoReturnToProfileWithItsUrl": any(own_cookie(e, "A") and e["query"].get("code") == SSO_CODE
                                            for e in pages("A", "sso")),
        # A return arrives as a browser's cross-site top-level navigation from B would: the Lax
        # cookie comes, the Strict one does not, `Sec-Fetch-Site: cross-site`, and at most B's
        # origin as Referer. The same-site move shows the Strict cookie exists.
        "sameSiteCarriesStrictCookie": any(cookies(e.get("cookie")).get("d136s") == marks.get("A")
                                           for e in pages("A2", "same")),
        "returnsArriveCrossSite": bool(pages("A", "return") + pages("A", "sso")) and all(
            cross_site_arrival(e, marks.get("A")) for e in pages("A", "return") + pages("A", "sso")),
        # The refusal is recorded by the separate profile that refused it.
        "postBackRefused": any("form:false:separateProfileReturnWithBody" in (p.get("codes") or []) for p in profiles)
        and not any(e["listener"] == "A" and e.get("method") == "POST" for e in window),
        "windowOpenNeverInProfile": not any(cookies(e.get("cookie")).get("d136") for e in pages("B", "open")),
        "noProfileCookieAtOtherSite": bool(separate) and not any("d136" in cookies(e.get("cookie")) for e in separate),
        "cacheNotShared": any(e["path"] == "/cached.js" and referer_task(e) in SEPARATE_PAGE_TASKS for e in window
                              if e["listener"] == "B"),
        # The bot's own profile still serves B's script from its cache (seeded by the positive),
        # so the separate profiles' requests above are the cache being kept apart, not absent.
        "profileCacheStillUsed": bool(command) and not any(
            e["listener"] == "B" and e["path"] == "/cached.js" and referer_task(e) == "command" for e in window),
        "noServiceWorker": not any(e["path"] == "/sw-hit" for e in window),
        "toldToOpenCookieSiteUsesProfile": any(own_cookie(e, "B") for e in command),
        "exposureConfirmed": (scenario.get("exposureConfirmations") or 0) >= 1,
        "separateProfilesOpened": len(profiles) >= 2,
        "sameRouteRulesLockdown": bool(profiles) and any(c.startswith("configuration:true:boundary:lockdown,") for c in own)
        and all(boundary(p.get("codes") or []) == own for p in profiles),
        "discardedAfterTask": scenario.get("separateOpenAfterRun") is False,
        "noSeparateDataOnDisk": scenario.get("separateMarkOnDisk") == [] and scenario.get("profileMarkOnDisk") is True,
        "noRuleListsLeft": scenario.get("separateRuleListsLeft") == [],
        "noStoreLeft": scenario.get("separateStoreIdentifiers") == [],
        # F1: a sandboxed (opaque-origin) frame's script move is judged from the page it is on.
        "sandboxedFrameSeparate": reached_separately("sframe"),
        # F4: refused at the click, inside its own task; no separate profile opened then (every
        # profile's opening time is known) and no listener saw the form.
        "ungrantedFormRefused": task_window(scenario, ungranted) is not None
        and "click:false:siteNotGranted" in bot_codes(ungranted)
        and all(isinstance(p.get("openedAt"), (int, float)) for p in profiles)
        and not any(during(ungranted, p["openedAt"]) for p in profiles)
        and not any(e["query"].get("task") == "ungranted" for e in window),
        # F7: the form reached B from its separate profile; its replay into a frame of the page
        # left behind was refused for want of a permit and never arrived.
        "formReplayRefused": bool(posted("formreplay", "d136-post")) and saw_nothing(seen.get("formreplay"))
        and "form:false:unstagedForm" in bot_codes("cross-site-form-replay")
        and not any((e.get("form") or {}).get("note") == "d136-replay" for e in window),
        # F6: 300 typed characters match; a field that doubles a space fails the exact check.
        "longTypingMatched": typed.get("succeeded") is True and typed.get("code") is None,
        "doubledSpaceRefused": doubled.get("succeeded") is True and doubled.get("code") == "invalidResult",
    }


def cross_site_arrival(event, mark, fetch_metadata=True):
    """Lax cookie sent, Strict withheld, fetch metadata cross-site, Referer at most an origin.
    WebKit sends fetch metadata only to potentially trustworthy origins: the loopback fixtures
    get it, the gateway route's plain-http `.test` names never do (`fetch_metadata=False`), so
    there it must be absent or cross-site."""
    jar = cookies(event.get("cookie"))
    referer = urlsplit(event.get("referer") or "")
    site = event.get("secFetchSite")
    return (jar.get("d136l") == mark and "d136s" not in jar
            and (site == "cross-site" or (not fetch_metadata and site is None))
            and referer.path in ("", "/") and not referer.query)


def sweep_facts(scenario):
    """Leftover lists of a profile that no longer exists (as a crash or a quit leaves them) are
    removed at the next start; a saved profile's lists stay. T10: a real app process dies by
    SIGKILL while its throwaway profile (a non-persistent store under Lockdown with its compiled
    lists) shows an owned page (the crash child); the relaunch's sweep removes its lists and
    leaves no rule-list file for its profile."""
    crash = scenario.get("crashChild") if isinstance(scenario.get("crashChild"), dict) else {}
    page = urlsplit(crash.get("page") or "")
    return {"leftoversPlanted": (scenario.get("orphanListsBefore") or 0) == 2,
            "leftoversRemoved": scenario.get("orphanListsAfter") == 0,
            "savedProfileKept": scenario.get("keptListsAfter") == 2,
            "crashKilledWithLiveProfile": crash.get("terminationSignal") == signal.SIGKILL
            and crash.get("nonPersistent") is True and crash.get("lockdown") is True
            and page.hostname == "127.0.0.1" and page.path == "/page2",
            "crashListsLeft": (scenario.get("crashListsBefore") or 0) == 2
            and scenario.get("crashListsAfter") == 0,
            "crashNoFilesLeft": scenario.get("crashFilesLeft") == [],
            # The marker read is the one this child wrote: it carries the parent's nonce.
            "crashMarkerFromThisChild": crash.get("markerNonceMatched") is True}


def edge_facts(scenario, window):
    """The D136 review's follow-ups the driver runs itself, on the signed-in store and the owned-
    fixture route. F3: the runner is cancelled while a return to the bot's site is under way; the
    return never arrives, nothing commits in the bot's profile afterwards and no separate profile
    is open once the run stopped. F8: re-authorized without the site its separate profile shows,
    the bot has no separate profile open. F9: a file staged in a separate profile makes that profile
    hold private data; the exposure confirmation reaches it, so its form is allowed and submitted
    there. Spec gap 5: a page that sets a cookie in a profile that held nothing when it was
    configured embeds no frame of another origin."""
    def pages(listener, task, method="GET"):
        return [e for e in window if e["listener"] == listener and e["path"] == "/page"
                and e.get("method", "GET") == method and e["query"].get("task") == task]

    upload = scenario.get("uploadSeparateCodes") or []
    return {
        "cancelDuringReturn": scenario.get("returnDecidedBeforeCancel") is True
        and isinstance(scenario.get("cancelAt"), (int, float)) and bool(pages("B", "cancel")),
        "runCancelled": scenario.get("cancelRunState") == "cancelled",
        "noCommitAfterCancel": scenario.get("profileCommitsAfterCancel") == 0,
        "returnNeverArrived": not pages("A", "cancelreturn"),
        # A stopped return's navigation once opened its target in a new separate profile, after
        # the task ended (2026-11-20).
        "noSeparateAfterCancel": scenario.get("separateOpenAfterCancel") is False,
        "reauthorizeOpenedSeparate": scenario.get("reauthorizeSeparateBefore") is True,
        "reauthorizeApplied": scenario.get("reauthorizeApplied") is True,
        "reauthorizeClosedSeparate": scenario.get("reauthorizeSeparateAfter") is False,
        "uploadStagedInSeparate": "upload:true:staged" in upload,
        "confirmedFormAllowedInSeparate": "click:true:allowed" in upload,
        # No run has ever recorded `form:true:allowed`: willSubmitForm never fires here, and the
        # navigation gate that does decide records only refusals. The POST arriving is the proof.
        "uploadSubmittedInSeparate": "click:true:allowed" in upload and bool(pages("B", "uploaded", "POST")),
        "frameRefusedAfterCookie": scenario.get("framePrivateAtConfiguration") is False
        and bool(pages("A", "cookieframe"))
        and "navigation:false:exposureConfirmationRequired" in (scenario.get("frameProfileCodes") or [])
        and not any(e["query"].get("task") == "embedded" for e in window),
    }


def boundary_codes(codes):
    """A profile's recorded route and boundary, with profile identities removed."""
    return {normalized(c) for c in codes if c.startswith("configuration:true:boundary:")
            or c in ("configuration:true:directFixture", "configuration:true:authenticatedProxy")}


def gateway_separate_facts(scenario, window):
    """The gateway route, through the bot's own gateway client to pages at granted hosts (the
    cookie sink behind the owned route). A same-site link keeps the bot's profile and its cookie;
    a link to the other site opens a separate, empty, non-persistent profile on the same boundary,
    and the link back arrives in the bot's profile as a cross-site navigation; a confirmed POST
    form reaches the other site from a separate profile with its body; a form to an ungranted
    origin is refused at the click and reaches nothing; a form replayed into a frame after its
    hand-off is refused; a redirect whose separate opening the route refuses fails at once with
    that refusal's code (D136 review F5). Every page came by name through the gateway, and no
    decision is attributed to an identity other than the bot's."""
    marks = scenario.get("marks") or {}
    suite = scenario.get("suite") or {}
    profiles = scenario.get("separateProfiles") or []
    seen = sink_reports(window)
    bot_gateway = scenario.get("gateway") or []
    bot = scenario.get("profileDecisions") or []
    own = boundary_codes(scenario.get("configurationCodes") or [])

    def pages(listener, task, method=None):
        return [e for e in window if e["listener"] == listener and e["path"] == "/page"
                and e["query"].get("task") == task and (method is None or e.get("method", "GET") == method)]

    def during(task, at):
        span = task_window(scenario, task)
        return span is not None and isinstance(at, (int, float)) and span[0] <= at < span[1]

    def bot_codes(task):
        return [d.get("code") for d in bot if during(task, d.get("at"))]

    def posted(task, note):
        return [e for e in window if e.get("method") == "POST" and e["query"].get("task") == task
                and (e.get("form") or {}).get("note") == note]

    other = [e for e in window if e["listener"] == "B"]
    if posted("gw-formpost", "d136-post"):
        post = "separateWithBody"
    elif "form:false:separateProfileFormBodyUnavailable" in (scenario.get("configurationCodes") or []):
        post = "refusedWithoutBody"
    else:
        post = "none"
    opening = suite_step(suite, "gw-opening-fails", "click")
    ungranted = "gw-form-ungranted"
    return {
        "suiteCompleted": suite.get("state") == "completed"
        and set(REQUIRED_GATEWAY_TASKS) <= set(suite.get("successfulTasks") or []),
        # The cookie sink saw only the gateway's names: every page came through the owned route.
        "pagesThroughGatewayByName": bool(window) and all(e.get("host") in GATEWAY_HOSTS for e in window),
        "sameSiteKeptProfile": any(cookies(e.get("cookie")).get("d136") == marks.get("A")
                                   for e in pages("A2", "gw-same")),
        "crossSiteLinkSeparate": bool(pages("B", "gw-link")) and saw_nothing(seen.get("gw-link")),
        "noProfileCookieAtOtherSite": bool(other) and not any("d136" in cookies(e.get("cookie")) for e in other),
        "returnArrivesCrossSite": bool(pages("A", "gw-return")) and all(
            cross_site_arrival(e, marks.get("A"), fetch_metadata=False) for e in pages("A", "gw-return")),
        "postFormNeverInProfile": post == "refusedWithoutBody"
        or (post == "separateWithBody" and saw_nothing(seen.get("gw-formpost"))),
        "ungrantedFormRefused": task_window(scenario, ungranted) is not None
        and "click:false:siteNotGranted" in bot_codes(ungranted)
        and all(isinstance(p.get("openedAt"), (int, float)) for p in profiles)
        and not any(during(ungranted, p["openedAt"]) for p in profiles)
        and not any(e["query"].get("task") == "gw-ungranted" for e in window)
        and not any(d.get("host") == GATEWAY_UNGRANTED for d in bot_gateway),
        "formReplayRefused": bool(posted("gw-formreplay", "d136-post")) and saw_nothing(seen.get("gw-formreplay"))
        and "form:false:unstagedForm" in bot_codes("gw-form-replay")
        and not any((e.get("form") or {}).get("note") == "d136-replay" for e in window),
        # F5: the redirect's separate opening was refused by the route, the step failed with that
        # refusal's own code well before the old 30 s wait, and nothing reached the other site.
        "openingRefusalReportedAtOnce": opening.get("succeeded") is True
        and opening.get("code") == GATEWAY_OPENING_REFUSAL
        and isinstance(opening.get("durationMs"), (int, float))
        and opening["durationMs"] < GATEWAY_OPENING_REPORTED_MS
        and scenario.get("refusedOpenings") == 1
        and f"navigation:false:separateProfile.{GATEWAY_OPENING_REFUSAL}" in bot_codes("gw-opening-fails")
        and any(e["listener"] == "A" and e["path"] == "/redirect" and during("gw-opening-fails", e["t"])
                for e in window)
        and not pages("B", "gw-failed"),
        "exposureConfirmed": (scenario.get("exposureConfirmations") or 0) >= 1,
        "separateProfilesOpened": len(profiles) >= len(GATEWAY_SEPARATE_PAGE_TASKS),
        "separateNotPersistent": bool(scenario.get("separateSeen"))
        and all(s.get("persistent") is False for s in scenario["separateSeen"]),
        "sameRouteRulesLockdown": bool(profiles) and "configuration:true:authenticatedProxy" in own
        and any(c.startswith("configuration:true:boundary:lockdown,") and c.endswith(",gateway") for c in own)
        and all(boundary_codes(p.get("codes") or []) == own for p in profiles),
        "leftThroughBotGateway": any(d.get("host") == GATEWAY_OTHER and d.get("allowed") for d in bot_gateway),
        "onlyGrantedHostsAtGateway": bool(bot_gateway) and all(d.get("host") in GATEWAY_HOSTS for d in bot_gateway),
        "noGatewayIdentityOfItsOwn": scenario.get("separateGateway") == [],
        "discardedAfterTask": scenario.get("separateOpenAfterRun") is False,
        "noSeparateDataOnDisk": scenario.get("separateMarkOnDisk") == [],
        "noRuleListsLeft": scenario.get("separateRuleListsLeft") == [],
        "noStoreLeft": scenario.get("separateStoreIdentifiers") == [],
    }


def fetch_results(page):
    """A probe page's fetch results."""
    return [r for r in page.get("results") or [] if r.get("path") == "fetch"] if isinstance(page, dict) else []


def page_refused_or_reached_nothing(scenario):
    """An app-supplied page the boundary refused before it loaded (a `networkBoundary` refusal
    recorded and no report), or one that ran and whose every fetch failed."""
    page = scenario.get("page")
    codes = scenario.get("configurationCodes") or []
    refused = (isinstance(page, dict) and page.get("missing") is True
               and any(c.startswith("navigation:false:networkBoundary.") for c in codes))
    fetches = fetch_results(page)
    reached_nothing = page_ran(page) and bool(fetches) and all(
        str(r.get("outcome")).startswith("err:") for r in fetches)
    return refused or reached_nothing


def fail_closed_facts(scenario):
    """What each fail-closed check recorded, judged; an unknown check has none, so never passes."""
    name = scenario["name"]
    codes = scenario.get("configurationCodes") or []
    gateway = scenario.get("gateway") or []
    no_request = scenario.get("fixtureRequestsDuring") == 0
    suite_refused = scenario.get("suiteOutcome", scenario.get("outcome")) not in (None, "loaded")
    address_refused = scenario.get("addressResult") not in (None, "loadStarted")
    if name == "fc-unconfigured-navigate":
        return {"noFixtureRequest": no_request,
                "laterNavigationRefused": scenario.get("laterResult") not in (None, "loadStarted")}
    if name == "fc-unconfigured-suite":
        return {"noFixtureRequest": no_request, "suiteLoadRefused": suite_refused}
    if name == "fc-immediate-lab-page":
        return {"immediateLoadRefused": scenario.get("immediateLoadStarted") is False}
    if name == "fc-revoked-fixture":
        return {"noFixtureRequest": no_request, "suiteLoadRefused": suite_refused, "addressRefused": address_refused}
    if name == "fc-revoked-proxy":
        boundary = scenario.get("revokedBoundary") or ""
        return {"revokeRecorded": "configuration:false:revoked" in codes,
                "routeAndGatewayRemoved": ",route=none," in boundary and boundary.endswith(",noGateway"),
                "suiteLoadRefused": suite_refused, "addressRefused": address_refused,
                "pageRefusedOrReachedNothing": page_refused_or_reached_nothing(scenario),
                "noGatewayAllowed": not any(d.get("allowed") for d in gateway)}
    if name == "fc-gateway-shutdown":
        page = scenario.get("page")
        fetches = {r.get("target"): str(r.get("outcome")) for r in fetch_results(page)}
        # allowFailover=false: `sub` resolves to the loopback sink, so a direct fallback would have
        # reached it; `h` is a name only the gateway knew.
        return {"gatewayClosedBeforeLoad": scenario.get("gatewayClosedBeforeLoad") is True,
                "probeRan": page_ran(page),
                "everyFetchFailed": set(fetches) == {"sub", "h"}
                and all(outcome.startswith("err:") for outcome in fetches.values()),
                "noGatewayDecision": gateway == []}
    if name == "fc-local-name-grant":
        return {"localNameRefusedAtConfiguration": "configuration:false:egress.invalidRule" in codes,
                "noRouteConfigured": not any(c in ("configuration:true:authenticatedProxy",
                                                   "configuration:true:directFixture") for c in codes),
                "pageRefusedOrReachedNothing": page_refused_or_reached_nothing(scenario),
                "noGatewayAllowed": not any(d.get("allowed") for d in gateway)}
    return {}


def sink_liveness(out, raw_events, raw_profile):
    """Whether every sink listener was alive when the driver ended: each listener the sinks'
    `ready` records name logged the probe run-control.py sent it then (liveness.json), and both
    sink processes were still running. A dead listener never comes back, so this covers the whole
    run. Returns the facts and both logs without the probes' own records, which are matched by
    the probe's own address or token and only at or after the probe started."""
    path = out / "liveness.json"
    facts = json.loads(path.read_text()) if path.exists() else {}
    probes = facts.get("probes") or []
    since = facts.get("startedAt", float("inf"))
    peers = {p.get("peer") for p in probes if p.get("sink") == "sinks" and p.get("peer")}
    tokens = {p.get("token") for p in probes if p.get("sink") == "profile"}

    def sink_probe(e):
        return e.get("t", 0) >= since and e.get("peer") in peers

    def profile_probe(e):
        return e.get("t", 0) >= since and e.get("path") == "/liveness" and (e.get("query") or {}).get("n") in tokens

    def logged(probe):
        if probe is None or probe.get("sent") is not True:
            return False
        if probe["sink"] == "profile":
            return any(profile_probe(e) and e.get("listener") == probe["label"]
                       and e["query"].get("n") == probe["token"] for e in raw_profile)
        return any(sink_probe(e) and e.get("label") == probe["label"] and e.get("peer") == probe.get("peer")
                   and (e["kind"] == "udp" and e.get("bytes") == probe.get("bytes") if probe["kind"] == "udp"
                        else e["kind"] == "tcp-data" and e.get("first") == LIVENESS_PREFIX + probe["token"])
                   for e in raw_events)

    sink_listeners = next((e.get("listeners") for e in raw_events if e.get("kind") == "ready"), None) or []
    profile_listeners = next((e.get("listeners") for e in raw_profile if e.get("listener") == "ready"), None) or []
    missing = [f"sinks:{listener['label']}" for listener in sink_listeners if not logged(next(
        (p for p in probes if p.get("sink") == "sinks" and p.get("label") == listener["label"]), None))]
    missing += [f"profile:{listener['label']}@{listener['host']}" for listener in profile_listeners if not logged(next(
        (p for p in probes if p.get("sink") == "profile" and p.get("label") == listener["label"]
         and p.get("host") == listener["host"]), None))]
    processes = {"sinks": facts.get("sinksProcessRunning") is True,
                 "profileSink": facts.get("profileSinkProcessRunning") is True}
    result = {"checked": path.exists(), "listeners": len(sink_listeners) + len(profile_listeners),
              "missing": missing, "processesRunning": processes,
              "alive": bool(sink_listeners) and bool(profile_listeners) and all(processes.values()) and not missing}
    return (result, [e for e in raw_events if not sink_probe(e)], [e for e in raw_profile if not profile_probe(e)])


def page_ran(page, navigation="started"):
    """The probe ran only if its page loaded and reported, and its run did not throw: zero sink
    events from a page that never ran its probes, or that skipped the rest of them after a fatal
    throw (probe.js's `run`/`fatal`), says nothing about the boundary."""
    return (navigation == "started" and isinstance(page, dict) and not page.get("missing")
            and bool(page.get("results")) and not any(r.get("path") == "run" for r in page["results"]))


def api_absent(page):
    """The probe paths that measured nothing because the page lacked their API (Lockdown removes
    WebRTC, WebTransport and service workers): probe.js's `absent`, a `typeof` of `undefined`,
    sw.html's `available:undefined` and `err:no ...`, and a missing global's ReferenceError. Zero
    sink events on such a path is API absence, not a measured block."""
    results = (page.get("results") or []) if isinstance(page, dict) else []
    found = []
    for r in results:
        outcome = str(r.get("outcome"))
        if r.get("path") != "features" and (outcome in ("absent", "undefined")
                                            or outcome.startswith(("available:undefined", "err:no "))
                                            or "Can't find variable: " in outcome):
            found.append(f"{r.get('path')} {r.get('target')}: {outcome}")
    return found


def only_empty_preconnect(page, window):
    """A retained `target=_blank` row stays inside D135's exception: its sink events are only TCP
    accepts and read ends, with at most one connection per anchor the page reported clicking or
    placing, each at the sink that anchor targets. A request, UDP, a second connection or one no
    reported anchor explains is a bypass the exception does not cover."""
    results = (page.get("results") or []) if isinstance(page, dict) else []
    allowed = {}
    for r in results:
        label = BLANK_ANCHOR_SINKS.get(r.get("target")) if r.get("path") in BLANK_ANCHOR_PATHS else None
        if label:
            allowed[label] = allowed.get(label, 0) + 1
    connections = {kind: {} for kind in PRECONNECT_EVENTS}
    for e in window:
        if e["kind"] not in PRECONNECT_EVENTS:
            return False
        connections[e["kind"]][e["label"]] = connections[e["kind"]].get(e["label"], 0) + 1
    accepted, ended = connections["tcp-accept"], connections["tcp-read-end"]
    return (all(count <= allowed.get(label, 0) for label, count in accepted.items())
            and all(count <= accepted.get(label, 0) for label, count in ended.items()))


def marker_present(scenario, run_id):
    """Whether the seeded store's localStorage marker carried this run's value."""
    return (scenario.get("storeMarker") or {}).get("localStorage") == run_id


def native_clicks_trusted(scenario):
    """Every `target=_blank` anchor the page placed received a trusted (`isTrusted`) native click."""
    page = scenario.get("page") if isinstance(scenario.get("page"), dict) else {}
    placed = {r["target"] for r in page.get("results") or [] if r.get("path") == "a-target-blank-native"}
    clicked = {c.get("target") for c in scenario.get("nativeClicks") or [] if c.get("isTrusted") is True}
    return bool(placed) and placed <= clicked


def suite_compatibility(scenario):
    """Owned-fixture task success under Lockdown: a compatibility measure, never a bypass verdict."""
    suite = scenario.get("suite") or {}
    failed = {}
    for step in suite.get("steps") or []:
        if not step.get("succeeded") and step.get("taskID") not in failed:
            failed[step.get("taskID")] = f"{step.get('operation')}:{step.get('code')}"
    return {"state": suite.get("state"), "tasks": suite.get("taskCount"),
            "succeeded": len(suite.get("successfulTasks") or []), "failedTasks": failed,
            "navigated": sum(1 for s in suite.get("steps") or []
                             if s.get("operation") == "navigate" and s.get("succeeded") is True),
            "lockdownActive": scenario.get("lockdownActive") is True,
            "stepDurationsMs": {f"{s.get('taskID')}#{s.get('index')}:{s.get('operation')}": s.get("durationMs")
                                for s in suite.get("steps") or []}}


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    operation = sys.argv[1]
    if operation == "prepare":
        evidence = os.environ.get("S3_NO_BYPASS_EVIDENCE")
        if not evidence:
            sys.exit("set S3_NO_BYPASS_EVIDENCE to an existing evidence directory")
        prepare(sys.argv[2], evidence)
    elif operation == "analyze":
        print(json.dumps(analyze(sys.argv[2])["verdict"], indent=2))
    elif operation == "build" and len(sys.argv) == 4 and sys.argv[3] in TREES:
        sys.exit(build(load_state(sys.argv[2]), sys.argv[3]))
    elif operation == "run" and sys.argv[3:4] and sys.argv[3] in TREES and run_options(sys.argv[4:]) is not None:
        local_names, only = run_options(sys.argv[4:])
        sys.exit(run(load_state(sys.argv[2]), sys.argv[3], local_names=local_names, only=only))
    else:
        sys.exit(__doc__)


def run_options(arguments):
    """`run`'s options as (local_names, only), or None when they are not `[--no-local-names]
    [--only <known scenario>,...]` in that order."""
    local_names = arguments[:1] != ["--no-local-names"]
    rest = arguments[0 if local_names else 1:]
    if not rest:
        return local_names, None
    if len(rest) != 2 or rest[0] != "--only":
        return None
    only = rest[1].split(",")
    if not only or any(name not in EXPECTED_SCENARIOS for name in only):
        return None
    return local_names, only


if __name__ == "__main__":
    main()
