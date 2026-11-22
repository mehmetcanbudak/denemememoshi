#!/usr/bin/env python3
"""S3 D101 browser-boundary proof on the iOS Simulator (owned loopback fixtures only).

Compiles the unmodified product apps/shared/MobileBrowserReview*.swift sources (the SwiftUI view
is omitted) plus S3IOSSimDriver.swift into an owned iOS Simulator carrier app that links AppCore
and MemoshiEgress, then installs it on ONE existing simulator, runs it, collects the driver's JSON
from its data container, uninstalls it and shuts the simulator down if this run booted it.

  run-sim.py prepare <label> <evidence-root>   -> prints state.json
  run-sim.py build <state.json> [--ats-web-content]
  run-sim.py run <state.json> <simulator-udid>
  run-sim.py analyze <run-dir>/s3-ios-sim-result[-N].json
  run-sim.py clean <state.json>                -> deletes this run's owned scratch only

--ats-web-content adds NSAllowsArbitraryLoadsInWebContent to the carrier's ATS (default is
NSAllowsLocalNetworking only), so ATS cannot stop a positive-control spelling (e.g. `localhost.`)
and only WebKit content rules / Lockdown stand between product pages and the sinks.

Run build and run through the build lock. Scratch lives under the owned 0700 $MEMOSHI_BUILD_ROOT.
"""
import json
import os
import plistlib
import shutil
import signal
import stat
import subprocess
import sys
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
WORK = Path(os.environ.get("MEMOSHI_BUILD_ROOT") or sys.exit("set MEMOSHI_BUILD_ROOT to the owned 0700 build root"))
PRODUCT_FILES = ["apps/shared/" + name for name in [
    "MobileBrowserReviewSession.swift", "MobileBrowserReviewDelegate.swift",
    "MobileBrowserReviewTypes.swift", "MobileBrowserReviewSecurity.swift",
    "MobileBrowserReviewInput.swift", "MobileBrowserReviewFixture.swift",
    "MobileBrowserReviewGateway.swift", "BrowserReviewProfile.swift"]]
TARGET = "S3IOSSim"
PRODUCT = "s3-ios-sim"
TRIPLE = "arm64-apple-ios27.0-simulator"
RESULT = "s3-ios-sim-result.json"


def owned_dir(path):
    facts = path.lstat()
    if not stat.S_ISDIR(facts.st_mode) or facts.st_uid != os.getuid() or stat.S_IMODE(facts.st_mode) != 0o700:
        raise RuntimeError(f"{path} must be an owned non-symlink 0700 directory")


def prepare(label, evidence_root):
    if not label.replace("-", "").isalnum():
        raise RuntimeError("use an alphanumeric run label")
    os.umask(0o077)
    owned_dir(WORK)
    owned_dir(Path(evidence_root))
    identity = uuid.uuid4().hex[:12]
    scratch = WORK / ("S3IOSSim-" + identity)
    scratch.mkdir(mode=0o700)
    package = scratch / "package"
    (package / "Sources" / TARGET).mkdir(parents=True, mode=0o700)
    (scratch / "tmp").mkdir(mode=0o700)
    pins = REPO / "apps/mac/Memoshi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    shutil.copy2(pins, package / "Package.resolved")
    deps = [("MemoshiApp", "AppCore"), ("MemoshiCore", "MemoshiEgress")]
    refs = ", ".join(f'.product(name: "{product}", package: "{name}")' for name, product in deps)
    (package / "Package.swift").write_text(
        "// swift-tools-version: 6.4\nimport PackageDescription\n"
        'let package = Package(name: "S3IOSSimCarrier", platforms: [.iOS("27.0")],\n'
        f'  products: [.executable(name: "{PRODUCT}", targets: ["{TARGET}"])],\n'
        "  dependencies: [" + ", ".join(f'.package(path: {json.dumps(str(REPO / "Packages" / n))})'
                                        for n in sorted({n for n, _ in deps}))
        + f"],\n  targets: [.executableTarget(name: \"{TARGET}\", dependencies: [" + refs + "])])\n")
    run = Path(evidence_root) / ("run-" + label + "-" + identity)
    run.mkdir(mode=0o700)
    state = {"run": str(run), "scratch": str(scratch), "package": str(package),
             "bundleID": "com.memoshi.s3-ios-sim." + identity, "identity": identity}
    with (run / "state.json").open("x") as stream:
        json.dump(state, stream, indent=2)
    print(run / "state.json")


def load_state(path):
    state = json.loads(Path(path).read_text())
    scratch = Path(state["scratch"])
    assert scratch.parent == WORK and scratch.name.startswith("S3IOSSim-")
    owned_dir(scratch)
    return state


def env_for(state):
    return {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ.get("HOME", "/tmp"),
            "LANG": "en_US.UTF-8", "TMPDIR": str(Path(state["scratch"]) / "tmp"),
            "GIT_ALLOW_PROTOCOL": "file:https", "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            "CLANG_MODULE_CACHE_PATH": str(WORK / "cache/clang"),
            "SWIFTPM_MODULECACHE_OVERRIDE": str(WORK / "cache/swift")}


def git(*args):
    return subprocess.run(["/usr/bin/git", "-C", str(REPO)] + list(args), capture_output=True, text=True).stdout.strip()


def attempt_suffix(directory, first):
    """'' for the first attempt, then '-2', '-3', ... so evidence files stay create-only."""
    n = 1
    while (directory / (first if n == 1 else first.replace(".", f"-{n}.", 1))).exists():
        n += 1
    return "" if n == 1 else f"-{n}"


def build(state, ats_web_content=False):
    run = Path(state["run"])
    # The first file an attempt creates names it: a failed resolve leaves no build.log behind.
    suffix = attempt_suffix(run, "sources.json")
    sources = Path(state["package"]) / "Sources" / TARGET
    for old in sources.iterdir():
        old.unlink()
    manifest = []
    for relative in PRODUCT_FILES:
        data = (REPO / relative).read_bytes()
        (sources / Path(relative).name).write_bytes(data)
        manifest.append({"source": relative, "bytes": len(data),
                         "worktreeBlob": git("hash-object", relative),
                         "headBlob": git("rev-parse", "HEAD:" + relative)})
    shutil.copy2(HERE / "S3IOSSimDriver.swift", sources / "S3IOSSimDriver.swift")
    manifest.append({"source": "spikes/S3-webkit-browser/ios-simulator/S3IOSSimDriver.swift",
                     "worktreeBlob": git("hash-object", "spikes/S3-webkit-browser/ios-simulator/S3IOSSimDriver.swift")})
    sdk = subprocess.run(["/usr/bin/xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"],
                         capture_output=True, text=True, check=True).stdout.strip()
    with (run / f"sources{suffix}.json").open("x") as stream:
        json.dump({"head": git("rev-parse", "HEAD"), "sdk": sdk, "triple": TRIPLE,
                   "sources": manifest, "packages": "worktree Packages/MemoshiApp, Packages/MemoshiCore"},
                  stream, indent=2)
    common = ["--package-path", state["package"], "--scratch-path", str(Path(state["scratch"]) / "build"),
              "--cache-path", str(WORK / "cache"), "--disable-keychain", "--disable-netrc",
              "--disable-experimental-prebuilts"]
    target = ["--triple", TRIPLE, "--sdk", sdk]
    jobs = os.environ.get("MEMOSHI_BUILD_JOBS", "2")
    env = env_for(state)
    for label, command in [
            ("resolve", ["/usr/bin/swift", "package"] + common + ["--skip-update", "resolve"]),
            ("build", ["/usr/bin/swift", "build"] + common + target + [
                "--disable-automatic-resolution", "--jobs", jobs, "-debug-info-format", "none",
                "--product", PRODUCT])]:
        with (run / f"{label}{suffix}.log").open("x") as log:
            log.write("$ " + " ".join(command) + "\n")
            log.flush()
            code = subprocess.run(command, cwd=str(REPO), env=env, stdout=log, stderr=subprocess.STDOUT).returncode
            log.write(f"\nexit {code}\n")
        if code:
            print(f"{label} failed; see {run / (label + suffix + '.log')}")
            return code
    bin_path = Path(subprocess.run(["/usr/bin/swift", "build"] + common + target + ["--show-bin-path"],
                                   cwd=str(REPO), env=env, capture_output=True, text=True, check=True).stdout.strip())
    app = Path(state["scratch"]) / "S3IOSSim.app"
    if app.exists():
        shutil.rmtree(app)
    app.mkdir(mode=0o700)
    shutil.copy2(bin_path / PRODUCT, app / PRODUCT)
    for resource in bin_path.glob("*.bundle"):
        shutil.copytree(resource, app / resource.name)
    with (app / "Info.plist").open("xb") as stream:
        plistlib.dump({
            "CFBundleExecutable": PRODUCT, "CFBundleIdentifier": state["bundleID"],
            "CFBundleName": "S3 iOS Sim Boundary", "CFBundleDisplayName": "S3 iOS Sim Boundary",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
            "CFBundleInfoDictionaryVersion": "6.0", "CFBundleDevelopmentRegion": "en",
            "CFBundleSupportedPlatforms": ["iPhoneSimulator"], "MinimumOSVersion": "27.0",
            "LSRequiresIPhoneOS": True, "UIDeviceFamily": [1, 2], "UILaunchScreen": {},
            "UIApplicationSceneManifest": {
                "UIApplicationSupportsMultipleScenes": False,
                "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{
                    "UISceneConfigurationName": "Default",
                    "UISceneDelegateClassName": TARGET + ".S3SimSceneDelegate"}]}},
            "NSAppTransportSecurity": dict({"NSAllowsLocalNetworking": True},
                                           **({"NSAllowsArbitraryLoadsInWebContent": True} if ats_web_content else {}))},
            stream)
    # Ad-hoc ("Sign to Run Locally"), as Xcode does for simulator builds; no signing identity.
    with (run / f"codesign{suffix}.log").open("x") as log:
        code = subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(app)],
                              stdout=log, stderr=subprocess.STDOUT).returncode
        log.write(f"exit {code}\n")
    print(app)
    return code


def simctl(log, *args, timeout=120, extra_env=None):
    command = ["/usr/bin/xcrun", "simctl"] + list(args)
    log.write(f"\n$ {' '.join(command)}\n")
    log.flush()
    env = dict(os.environ)
    env.update(extra_env or {})
    try:
        done = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                              timeout=timeout, env=env)
        log.write(done.stdout + f"exit {done.returncode}\n")
        log.flush()
        return done.returncode, done.stdout
    except subprocess.TimeoutExpired as error:
        log.write((error.stdout or b"").decode() if isinstance(error.stdout, bytes) else (error.stdout or ""))
        log.write(f"timeout after {timeout}s\n")
        log.flush()
        return 124, ""


def device_state(udid):
    listing = json.loads(subprocess.run(["/usr/bin/xcrun", "simctl", "list", "devices", "-j"],
                                        capture_output=True, text=True, check=True).stdout)
    for runtime, devices in listing["devices"].items():
        for device in devices:
            if device["udid"] == udid:
                return device["state"], runtime, device["name"]
    raise RuntimeError("simulator not found: " + udid)


def run(state, udid):
    out = Path(state["run"])
    app = Path(state["scratch"]) / "S3IOSSim.app"
    bundle = state["bundleID"]
    facts = {"udid": udid, "bundleID": bundle, "steps": []}
    initial, runtime, name = device_state(udid)
    facts.update({"initialState": initial, "runtime": runtime, "name": name})
    booted_here = False
    suffix = attempt_suffix(out, "simulator-run.log")
    with (out / f"simulator-run{suffix}.log").open("x") as log:
        def step(label, *args, **kwargs):
            code, text = simctl(log, *args, **kwargs)
            facts["steps"].append({"step": label, "exit": code})
            return code, text
        try:
            if initial != "Booted":
                code, _ = step("boot", "boot", udid)
                booted_here = code == 0
                if code:
                    return 1
            step("bootstatus", "bootstatus", udid, "-b", timeout=600)
            code, _ = step("install", "install", udid, str(app))
            if code:
                return 1
            code, console = step("launch", "launch", "--console-pty", "--terminate-running-process", udid, bundle,
                                 timeout=900, extra_env={"SIMCTL_CHILD_S3_HEAD": git("rev-parse", "HEAD")})
            if code == 124:
                step("terminate", "terminate", udid, bundle)
            code, container = step("container", "get_app_container", udid, bundle, "data")
            source = Path(container.strip()) / "Documents" / RESULT
            if code == 0 and source.is_file():
                with (out / RESULT.replace(".json", suffix + ".json")).open("xb") as stream:
                    stream.write(source.read_bytes())
                facts["resultCollected"] = True
            else:
                facts["resultCollected"] = False
        finally:
            step("uninstall", "uninstall", udid, bundle)
            if booted_here:
                step("shutdown", "shutdown", udid)
            facts["bootedHere"] = booted_here
            facts["finalState"] = device_state(udid)[0]
            with (out / f"simulator-run{suffix}.json").open("x") as stream:
                json.dump(facts, stream, indent=2)
    print(json.dumps(facts, indent=2))
    return 0 if facts.get("resultCollected") else 1


def analyze(path):
    path = Path(path)
    result = json.loads(path.read_text())
    rows = [(c["status"], c["name"]) for c in result["checks"]]
    summary = {"result": path.name, "error": result["error"], "counts": result["counts"],
               "nonPassing": [name for status, name in rows if status != "pass"],
               "checks": [f"{status:12} {name}" for status, name in rows]}
    with (path.parent / ("summary-" + path.name)).open("x") as stream:
        json.dump(summary, stream, indent=2)
    print(json.dumps(summary, indent=2))
    return 0 if not summary["nonPassing"] and not result["error"] else 1


def clean(state):
    scratch = Path(state["scratch"])
    shutil.rmtree(scratch)
    print("removed", scratch)
    return 0


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == "prepare":
        prepare(args[1], args[2])
    elif len(args) in (2, 3) and args[0] == "build" and args[2:] in ([], ["--ats-web-content"]):
        sys.exit(build(load_state(args[1]), ats_web_content=args[2:] == ["--ats-web-content"]))
    elif len(args) == 3 and args[0] == "run":
        sys.exit(run(load_state(args[1]), args[2]))
    elif len(args) == 2 and args[0] == "analyze":
        sys.exit(analyze(args[1]))
    elif len(args) == 2 and args[0] == "clean":
        sys.exit(clean(load_state(args[1])))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
