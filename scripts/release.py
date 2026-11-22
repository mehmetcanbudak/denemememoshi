#!/usr/bin/env python3
"""Phase-0 release commands. Nothing signs, uploads, installs or changes accounts at import.

All mutating commands require explicit inputs and fresh output paths. Run only from a
trusted checkout with separately authorized signing/upload credentials. See --help.
"""

import argparse
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts/lib"))
from release_support import (  # noqa: E402
    AGENT, APIUnavailable, APP_ID, BuildPending, HELPER, HELPER_ID, MOBILE_ID, ReleaseError, UTC, artifact_files,
    build_number, check_sizes, ecdsa_jose, file_digest, fresh_snapshot,
    ios_builds, is_executable_mach_o, is_mach_o, iso, measure_sizes, missing_runtime_licences, require, team_id,
    testflight_status, validate_device_access_group, validate_entitlements, validate_profile, validate_release_gate,
)
import pi_swift_manifest  # noqa: E402

LOG_DIRECTORY = None
LOG_INDEX = 0
TESTFLIGHT_POLL_SECONDS = 60


def run(arguments, *, data=None, env=None, check=True, label=None, secret_output=False):
    global LOG_INDEX
    label = label or Path(str(arguments[0])).name
    try:
        result = subprocess.run([str(item) for item in arguments], cwd=ROOT, input=data,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, check=False)
    except OSError as error:
        raise ReleaseError(f"{label} is unavailable: {error.strerror}") from error
    LOG_INDEX += 1
    log = None
    if LOG_DIRECTORY is not None and not secret_output:
        log = LOG_DIRECTORY / f"{LOG_INDEX:03d}-{re.sub('[^a-zA-Z0-9-]', '-', label)}.log"
        # Never log command arguments, environment, private-key stdin or bearer headers, and
        # (secret_output) never the output of a command that prints a credential.
        log.write_bytes(result.stdout + b"\n" + result.stderr)
        log.chmod(0o600)
    if check and result.returncode:
        raise ReleaseError(f"{label} failed with exit {result.returncode}" + (f"; diagnostic output: {log}" if log else "; rerun the named tool with these explicit inputs for diagnostics"))
    return result


def json_file(path):
    with Path(path).open() as stream:
        return json.load(stream)


def plist_file(path):
    with Path(path).open("rb") as stream:
        return plistlib.load(stream)


def write_json(path, value):
    with Path(path).open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")
    Path(path).chmod(0o600)


def write_plist(path, value):
    with Path(path).open("xb") as stream:
        plistlib.dump(value, stream, sort_keys=True)
    Path(path).chmod(0o600)


def fresh_output(path, source=None):
    global LOG_DIRECTORY
    output = Path(path).expanduser().resolve()
    require(not output.exists(), f"output already exists: {output}; use a new path, never overwrite a release")
    if source is not None:
        require(not output.is_relative_to(Path(source).resolve()), "output must not be inside the source app")
    # mkdir(parents=True) would give new parents the default mode: create each one owner-only.
    for directory in reversed([parent for parent in output.parents if not parent.exists()]):
        directory.mkdir(mode=0o700)
    output.mkdir(mode=0o700)
    LOG_DIRECTORY = output / "logs"
    LOG_DIRECTORY.mkdir(mode=0o700)
    return output


def reject_untrusted_ci():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return
    require(os.environ.get("GITHUB_EVENT_NAME") not in ("pull_request", "pull_request_target"),
            "release credentials and commands must never run in pull-request jobs")
    require(os.environ.get("GITHUB_REF_PROTECTED") == "true", "release CI requires a protected main/tag ref and protected release environment")


def require_release_ready():
    pin = dict(re.findall(r"^(PI_SWIFT_[A-Z]+)=(\S+)$", (ROOT / "scripts/lib/pi-swift-pin.sh").read_text(), re.M))
    revision, checkout = pin.get("PI_SWIFT_REVISION", ""), pin.get("PI_SWIFT_CHECKOUT", "")
    require(re.fullmatch(r"[0-9a-f]{40}", revision) is not None and checkout.startswith("../"),
            "cannot bind release acceptance to the exact Pi consumer pin")
    problems = pi_swift_manifest.problems((ROOT / "Packages/MemoshiCore/Package.swift").read_text(), f"../../{checkout}")
    require(not problems, "MemoshiCore does not build the Pi_Swift checkout that the pin names, alone: " + "; ".join(problems))
    clone = ROOT / checkout
    require(not clone.is_symlink() and clone.is_dir()
            and clone.resolve() == ROOT.parent.resolve() / Path(checkout).name,
            "the Pi_Swift checkout is not its own directory")
    sdk = validate_release_gate(json_file(ROOT / "scripts/release-gates.json"), revision)
    actual = run(
        ["git", "-C", ROOT / checkout, "rev-parse", "--verify",
         f"refs/tags/{sdk['qualifyingTag']}^{{commit}}"], label="accepted-SDK-tag").stdout.decode().strip()
    require(actual == revision, "accepted SDK tag does not resolve to the consumer revision")
    head = run(["git", "-C", ROOT / checkout, "rev-parse", "HEAD"], label="SDK-checkout").stdout.decode().strip()
    require(head == revision, "the Pi_Swift checkout is not at the consumer revision")

def release_source(reference, version):
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?", version) is not None, "--version must be exact SemVer")
    require(reference == "v" + version, "--source-tag must be v followed by --version")
    tag = run(["git", "rev-parse", "--verify", f"refs/tags/{reference}^{{commit}}"], label="release-tag").stdout.strip()
    head = run(["git", "rev-parse", "HEAD"], label="release-HEAD").stdout.strip()
    require(tag == head, "checkout HEAD does not match the exact release tag")
    require(not run(["git", "status", "--porcelain", "--untracked-files=normal"], label="release-clean-checkout").stdout,
            "release archives require a clean checkout, including untracked files")
    env = {**os.environ, "MEMOSHI_REQUIRE_RELEASE_DISK": "true"}
    run([ROOT / "scripts/check-prerequisites.sh"], env=env, label="SDK-and-release-disk-prerequisites")
    run([ROOT / "scripts/check-toolchain.sh"], label="qualified-toolchain")
    run([ROOT / "scripts/build-memoshi-mls.sh"], label="pinned-native-MLS")
    run([ROOT / "scripts/check-mls-generated.sh"], label="checked-in-native-MLS-outputs")
    run([ROOT / "scripts/generate-project.sh"], label="XcodeGen")
    # The builds above regenerate tracked files; the archive is of the tagged tree only.
    require(not run(["git", "status", "--porcelain", "--untracked-files=normal"], label="release-clean-checkout-after-build").stdout,
            "building the release changed the checkout (tracked or untracked files); the archive must be of the tagged tree")
    return head.decode()


def profile_data(path):
    path = Path(path).resolve()  # run() executes in ROOT; decode the file the caller named.
    require(path.is_file(), f"missing provisioning profile: {path}")
    return plistlib.loads(run(["/usr/bin/security", "cms", "-D", "-i", path], label="decode-profile").stdout)


def identity_preflight(identity, team, mobile=False):
    team_id(team)
    require(re.fullmatch(r"[0-9A-Fa-f]{40}", identity) is not None, "--identity must be the exact certificate SHA-1 from security find-identity, not a name or ad-hoc '-' signing")
    listing = run(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"], label="installed-signing-identities").stdout.decode()
    matches = [line for line in listing.splitlines() if identity.upper() in line.upper()]
    expected = "Apple Distribution:" if mobile else "Developer ID Application:"
    require(len(matches) == 1 and expected in matches[0] and f"({team})" in matches[0],
            f"no valid installed {expected} identity matches --identity and --team-id; install it separately with authorization")


def certificate_details(path, developer_id=True):
    with tempfile.TemporaryDirectory(prefix="memoshi-release-certs-") as directory:
        prefix = Path(directory) / "certificate"
        run(["/usr/bin/codesign", "--display", f"--extract-certificates={prefix}", path], label="extract-signing-chain")
        leaf, intermediate = Path(str(prefix) + "0"), Path(str(prefix) + "1")
        require(leaf.is_file() and intermediate.is_file(), "signature has no complete Apple signing certificate chain")
        if developer_id:
            subject = run(["/usr/bin/openssl", "x509", "-inform", "DER", "-in", intermediate, "-noout", "-subject", "-nameopt", "RFC2253"], label="certificate-intermediate").stdout.decode()
            require("CN=Developer ID Certification Authority" in subject and re.search(r"(?:^|,)OU=G2(?:,|$)", subject.strip()) is not None,
                    "signature was not issued by the Developer ID G2 Sub-CA")
        expiry = run(["/usr/bin/openssl", "x509", "-inform", "DER", "-in", leaf, "-noout", "-enddate"], label="certificate-expiration").stdout.decode().strip()
        return leaf.read_bytes(), expiry.removeprefix("notAfter=")


def info_path(bundle):
    for relative in ("Contents/Info.plist", "Resources/Info.plist", "Info.plist"):
        candidate = bundle / relative
        if candidate.is_file():
            return candidate
    raise ReleaseError(f"code bundle has no Info.plist: {bundle}")


def code_targets(app):
    app = app.resolve(strict=True)
    files = artifact_files(app)
    binaries = [path for path in files if not path.is_symlink() and is_mach_o(path)]
    require(binaries, "app contains no Mach-O code")
    bundles = {app}
    for binary in binaries:
        require("/Contents/Resources/" not in "/" + binary.relative_to(app).as_posix(), f"Mach-O code must not be hidden under Resources: {binary}")
        for parent in binary.parents:
            if not parent.is_relative_to(app):
                break
            if parent.suffix in (".app", ".framework", ".appex", ".xpc", ".bundle"):
                bundles.add(parent)
    main_binaries = set()
    targets = []
    for bundle in bundles:
        info = plist_file(info_path(bundle))
        name = info.get("CFBundleExecutable")
        require(isinstance(name, str) and name and Path(name).name == name, f"invalid CFBundleExecutable in {bundle}")
        executable = bundle / ("Contents/MacOS" if (bundle / "Contents").is_dir() else "") / name
        require(executable.is_file() and os.access(executable, os.X_OK), f"bundle executable is missing or not executable: {executable}")
        require(executable.resolve() in binaries, f"bundle executable is not admitted Mach-O code: {executable}")
        main_binaries.add(executable.resolve())
        identifier = info.get("CFBundleIdentifier")
        require(isinstance(identifier, str) and identifier, "code bundle lacks an identifier")
        targets.append((bundle, executable, identifier))
    for binary in binaries:
        if binary.resolve() not in main_binaries:
            relative = binary.relative_to(app).as_posix()
            suffix = hashlib.sha256(relative.encode()).hexdigest()[:16]
            targets.append((binary, binary, f"{MOBILE_ID}.code.{suffix}"))
    targets.sort(key=lambda item: (-len(item[0].parts), str(item[0])))
    require(len({item[2] for item in targets}) == len(targets), "different code objects share a signing identifier")
    return targets


def verify_signature(path, identifier, team, expected, require_runtime=True):
    requirement = f'=anchor apple generic and certificate leaf[subject.OU] = "{team}"'
    run(["/usr/bin/codesign", "--verify", "--strict", "--all-architectures", "-R", requirement, path], label="strict-code-signature")
    result = run(["/usr/bin/codesign", "--display", "--verbose=4", path], label="signature-metadata")
    details = (result.stdout + result.stderr).decode()
    require(f"Identifier={identifier}\n" in details and f"TeamIdentifier={team}\n" in details,
            f"unexpected signing identifier or Team ID: {path}")
    require("Authority=Developer ID Application:" in details and "Signature=adhoc" not in details,
            f"release code is not Developer ID Application signed: {path}")
    require(re.search(r"^Timestamp=.+$", details, re.MULTILINE) is not None, f"signature has no secure timestamp: {path}")
    if require_runtime:
        flags = re.search(r"flags=0x([0-9a-fA-F]+)", details)
        require(flags is not None and int(flags.group(1), 16) & 0x10000, f"hardened runtime is missing: {path}")
        data = run(["/usr/bin/codesign", "--display", "--entitlements", "-", "--xml", path], label="signed-entitlements").stdout
        validate_entitlements(plistlib.loads(data) if data.strip() else {}, expected)
    certificate, expiry = certificate_details(path)
    return certificate, {"identifier": identifier, "certificateSHA256": hashlib.sha256(certificate).hexdigest(), "certificateExpiresAt": expiry}


def require_runtime_licences(app):
    """D126: a release that bundles the Python runtime carries the licence texts retained for it."""
    missing = missing_runtime_licences(app, json_file(ROOT / "scripts/pyodide-licenses.json"), ROOT)
    require(not missing, "app bundles the Python runtime without its retained licence texts (D126): " + ", ".join(missing))


def verify_mac(app, team, stapled=False):
    team_id(team)
    app = Path(app).expanduser().resolve(strict=True)
    info = plist_file(app / "Contents/Info.plist")
    require(info.get("CFBundleIdentifier") == APP_ID, "wrong outer app bundle identifier")
    validate_device_access_group(info, team)
    require(plist_file(app / HELPER / "Contents/Info.plist").get("CFBundleIdentifier") == HELPER_ID, "wrong memoshid bundle identifier")
    require_runtime_licences(app)
    # The Release app is the product build; CI's own scan sees only the Debug build.
    run([ROOT / "scripts/check-signin-flows.sh", app], label="sign-in-flows")
    run([ROOT / "scripts/check-bundle.sh", app], label="bundle-layout-and-notices")
    # No Debug-only development tool is compiled into a Release bundle.
    run([ROOT / "scripts/check-bundle.sh", "--release-composition", app], label="release-composition")
    profiles = {}
    intended = {}
    for identifier, bundle in ((APP_ID, app), (HELPER_ID, app / HELPER)):
        profile = profile_data(bundle / "Contents/embedded.provisionprofile")
        entitlements, receipt = validate_profile(profile, team, identifier, dt.datetime.now(UTC))
        profiles[identifier] = (profile, receipt)
        intended[identifier] = entitlements
    require(profiles[APP_ID][1]["uuid"] != profiles[HELPER_ID][1]["uuid"], "app and helper must embed separate provisioning profiles")
    agent = plist_file(app / AGENT)
    require(agent.get("SpawnConstraint") == {"team-identifier": team, "signing-identifier": HELPER_ID}, "release LaunchAgent must constrain the helper Team ID and signing identifier")
    objects = []
    for target, binary, identifier in code_targets(app):
        require(run(["/usr/bin/lipo", "-archs", binary], label="release-architectures").stdout.decode().strip() == "arm64", f"Mac release contains non-arm64 code: {target}")
        certificate, receipt = verify_signature(target, identifier, team, intended.get(identifier, {}))
        if identifier in profiles:
            validate_profile(profiles[identifier][0], team, identifier, dt.datetime.now(UTC), certificate)
        receipt["path"] = target.relative_to(app).as_posix()
        objects.append(receipt)
    run(["/usr/bin/codesign", "--verify", "--strict", "--deep", app], label="nested-signature-seals")
    if stapled:
        run(["/usr/bin/xcrun", "stapler", "validate", app], label="app-staple-validation")
        run(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", app], label="app-Gatekeeper-assessment")
    return {"teamID": team, "profiles": {key: value[1] for key, value in profiles.items()}, "code": objects, "stapled": stapled}


def verify_mobile(app, team, required_profile=None):
    team_id(team)
    app = Path(app).resolve(strict=True)
    info = plist_file(app / "Info.plist")
    validate_device_access_group(info, team)
    require(info.get("CFBundleIdentifier") == MOBILE_ID and info.get("DTPlatformName") == "iphoneos"
            and info.get("UIDeviceFamily") == [1, 2], "upload needs a real universal physical-device iOS Memoshi archive")
    require_runtime_licences(app)
    run([ROOT / "scripts/check-signin-flows.sh", app], label="mobile-sign-in-flows")
    run([ROOT / "scripts/check-bundle.sh", "--release-composition", app], label="mobile-release-composition")
    for notice in ("LICENSE", "NOTICE"):
        bundled = app / notice
        require(bundled.is_file() and not bundled.is_symlink()
                and bundled.read_bytes() == (ROOT / notice).read_bytes(),
                "mobile archive is missing unchanged " + notice)
    run([sys.executable, ROOT / "scripts/memoshi-mls-payload-manifest.py",
         "--bundle-notices", app / "MemoshiMLS"], label="mobile-native-MLS-notices")
    name = info.get("CFBundleExecutable")
    require(isinstance(name, str) and Path(name).name == name, "mobile archive has an invalid executable")
    main = app / name
    embedded = profile_data(app / "embedded.mobileprovision")
    expected, receipt = validate_profile(embedded, team, MOBILE_ID, dt.datetime.now(UTC))
    if required_profile is not None:
        require(receipt["uuid"] == required_profile, "archive embedded a different provisioning profile than the explicit input")
    requirement = f'=anchor apple generic and certificate leaf[subject.OU] = "{team}"'
    run(["/usr/bin/codesign", "--verify", "--strict", "--deep", "-R", requirement, app], label="mobile-nested-signature-seals")
    binaries = [path for path in artifact_files(app) if not path.is_symlink() and is_mach_o(path)]
    require(main in binaries, "mobile archive executable is not Mach-O code")
    for binary in binaries:
        require(run(["/usr/bin/lipo", "-archs", binary], label="mobile-release-architectures").stdout.decode().strip() == "arm64",
                "mobile distribution contains simulator or unsupported architecture code")
        run(["/usr/bin/codesign", "--verify", "--strict", "-R", requirement, binary], label="mobile-code-signature")
        metadata = run(["/usr/bin/codesign", "--display", "--verbose=4", binary], label="mobile-signature-metadata")
        details = (metadata.stdout + metadata.stderr).decode()
        require("Authority=Apple Distribution:" in details and f"TeamIdentifier={team}\n" in details,
                "mobile archive contains code not signed by the selected Apple Distribution team")
        data = run(["/usr/bin/codesign", "--display", "--entitlements", "-", "--xml", binary], label="mobile-signed-entitlements").stdout
        validate_entitlements(plistlib.loads(data) if data.strip() else {}, expected if binary == main else {})
        if binary == main:
            require(f"Identifier={MOBILE_ID}\n" in details, "mobile signing identifier is not Memoshi")
            certificate, _ = certificate_details(app, developer_id=False)
            validate_profile(embedded, team, MOBILE_ID, dt.datetime.now(UTC), certificate)
    return info


def sign(args):
    reject_untrusted_ci()
    require_release_ready()
    identity_preflight(args.identity, args.team_id)
    source = Path(args.app).expanduser().resolve(strict=True)
    validate_device_access_group(plist_file(source / "Contents/Info.plist"), args.team_id)
    entitlements, profiles = {}, {}
    for identifier, profile_path in ((APP_ID, args.app_profile), (HELPER_ID, args.helper_profile)):
        entitlements[identifier], profiles[identifier] = validate_profile(profile_data(profile_path), args.team_id, identifier, dt.datetime.now(UTC))
    require(profiles[APP_ID]["uuid"] != profiles[HELPER_ID]["uuid"], "app and helper need distinct profiles")
    code_targets(source)  # Validate paths before copying or signing any code.
    output = fresh_output(args.output, source)
    app = output / "Memoshi.app"
    run(["/usr/bin/ditto", source, app], label="copy-unsigned-release-input")
    for identifier, bundle, profile in ((APP_ID, app, args.app_profile), (HELPER_ID, app / HELPER, args.helper_profile)):
        shutil.copyfile(profile, bundle / "Contents/embedded.provisionprofile")
        write_plist(output / f"{identifier}.entitlements", entitlements[identifier])
    agent = plist_file(app / AGENT)
    require(agent.get("Label") == HELPER_ID and agent.get("BundleProgram") == HELPER + "/Contents/MacOS/memoshid", "release LaunchAgent does not target memoshid's app-shaped helper")
    agent["SpawnConstraint"] = {"team-identifier": args.team_id, "signing-identifier": HELPER_ID}
    with (app / AGENT).open("wb") as stream:
        plistlib.dump(agent, stream)
    library_constraint = {"$or": {"team-identifier": args.team_id, "validation-category": 1}}
    parent_constraint = {"$or-array": [["$and", {"is-init-proc": True}], ["$and", {"team-identifier": args.team_id, "signing-identifier": APP_ID}]]}
    write_plist(output / "library.coderequirement", library_constraint)
    write_plist(output / "memoshid-parent.coderequirement", parent_constraint)
    write_plist(output / "pi-env-parent.coderequirement", {"team-identifier": args.team_id, "signing-identifier": HELPER_ID})
    validation = run(["/usr/bin/codesign", "--validate-constraint", output / "library.coderequirement", output / "memoshid-parent.coderequirement", output / "pi-env-parent.coderequirement"], label="launch-and-library-constraint-syntax")
    require(b"LWCRVerificationError" not in validation.stderr, "launch or library constraint plist failed LWCR validation")
    for target, binary, identifier in code_targets(app):
        # Omit --enforce-constraint-validity (broken on macOS 27.0.1 where valid LWCRs fail
        # serialization) and fail closed on any LWCRVerificationError warning emitted by codesign.
        command = ["/usr/bin/codesign", "--force", "--sign", args.identity, "--identifier", identifier, "--options", "runtime", "--timestamp"]
        if identifier in entitlements:
            command += ["--entitlements", output / f"{identifier}.entitlements"]
        if is_executable_mach_o(binary):
            command += ["--library-constraint", output / "library.coderequirement"]
        if identifier == HELPER_ID:
            command += ["--launch-constraint-parent", output / "memoshid-parent.coderequirement"]
        elif binary.name == "pi-env":
            command += ["--launch-constraint-parent", output / "pi-env-parent.coderequirement"]
        signed = run(command + [target], label="inside-out-signing")
        require(b"LWCRVerificationError" not in signed.stderr and b"Lightweight Code requirement failed validation" not in signed.stderr,
                f"codesign reported invalid launch/library constraint while signing {target}")
    write_json(output / "signing.json", verify_mac(app, args.team_id))
    print(f"Signed and statically validated copied app: {app}; not notarization, SMAppService or CloudKit proof")


def api_inputs(args):
    key = Path(args.api_key).expanduser().resolve(strict=True)
    require(key.is_file() and key.stat().st_mode & 0o077 == 0, "API private key must be an existing owner-only file (mode 0600 or stricter)")
    require(re.fullmatch(r"[A-Z0-9]{10}", args.key_id) is not None, "--key-id must be an App Store Connect API key ID")
    uuid.UUID(args.issuer_id)
    return key


def notary(artifact, args, output, label):
    result = run(["/usr/bin/xcrun", "notarytool", "submit", artifact, "--key", api_inputs(args), "--key-id", args.key_id, "--issuer", args.issuer_id, "--wait", "--output-format", "json"], check=False, label=label + "-notary-submit")
    try:
        receipt = json.loads(result.stdout)
    except (ValueError, UnicodeError) as error:
        raise ReleaseError(f"{label} notarytool returned no JSON receipt; authentication/network prerequisite failed; see protected logs") from error
    write_json(output / f"{label}-notary.json", receipt)
    submission = receipt.get("id")
    require(isinstance(submission, str) and re.fullmatch(r"[0-9a-fA-F-]{36}", submission) is not None, "notarytool returned no submission ID")
    # Download warnings even on an accepted submission. Never accept an exit-zero upload alone.
    run(["/usr/bin/xcrun", "notarytool", "log", submission, "--key", api_inputs(args), "--key-id", args.key_id, "--issuer", args.issuer_id, output / f"{label}-notary-log.json"], label=label + "-notary-log")
    (output / f"{label}-notary-log.json").chmod(0o600)
    require(result.returncode == 0 and receipt.get("status") == "Accepted", f"{label} notarization was not accepted; inspect {output / (label + '-notary-log.json')}")


def verify_dmg(dmg, app, team):
    dmg = Path(dmg).resolve(strict=True)
    verify_signature(dmg, MOBILE_ID + ".dmg", team, {}, require_runtime=False)
    run(["/usr/bin/hdiutil", "verify", dmg], label="DMG-integrity")
    run(["/usr/bin/xcrun", "stapler", "validate", dmg], label="DMG-staple-validation")
    run(["/usr/sbin/spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=4", dmg], label="DMG-Gatekeeper-assessment")
    with tempfile.TemporaryDirectory(prefix="memoshi-release-mount-") as directory:
        mount = Path(directory) / "volume"
        mount.mkdir()
        attached = False
        try:
            run(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", mount, dmg], label="mount-owned-release-DMG")
            attached = True
            link = mount / "Applications"
            require(link.is_symlink() and os.readlink(link) == "/Applications", "DMG lacks drag-to-Applications link")
            verify_mac(mount / "Memoshi.app", team, stapled=True)
            require(measure_sizes(mount / "Memoshi.app", dmg)["appTreeSHA256"] == measure_sizes(app, dmg)["appTreeSHA256"], "DMG app bytes differ from the validated release input")
        finally:
            if attached or mount.is_mount():
                run(["/usr/bin/hdiutil", "detach", mount], label="detach-owned-release-DMG")


def check_dmg(args):
    verify_mac(args.app, args.team_id, stapled=True)
    verify_dmg(args.dmg, args.app, args.team_id)
    print("App and DMG signatures, staples, Gatekeeper assessments and exact embedded app bytes are valid; clean-VM launch is still a separate gate")


def record_size_baseline(args):
    require(not Path(args.output).expanduser().exists(), "baseline output already exists; use a new path and review the measured change")
    check_dmg(args)
    measurement = measure_sizes(args.app, args.dmg)
    measurement.update({"measuredAt": iso(dt.datetime.now(UTC)), "qualification": "Developer-ID-G2-notarized-stapled"})
    write_json(Path(args.output).expanduser(), measurement)
    print(f"Actual qualified component measurements recorded at {args.output}; no repository baseline was changed")


def size_baseline(args):
    """None only for the explicit first-release flag; an empty or unset --baseline is refused."""
    if args.initial_size_baseline:
        return None
    require(args.baseline, "--baseline needs a reviewed size-baseline file; use --initial-size-baseline only for the first release")
    return json_file(args.baseline)


def package(args):
    reject_untrusted_ci()
    require_release_ready()
    baseline = size_baseline(args)  # Before any credential read, subprocess, upload or output.
    api_inputs(args)
    identity_preflight(args.identity, args.team_id)
    source = Path(args.app).expanduser().resolve(strict=True)
    verify_mac(source, args.team_id)
    output = fresh_output(args.output, source)
    app = output / "Memoshi.app"
    run(["/usr/bin/ditto", source, app], label="copy-signed-release-input")
    upload = output / "notary-upload.zip"
    run(["/usr/bin/ditto", "-c", "-k", "--keepParent", app, upload], label="archive-app-for-notarization")
    notary(upload, args, output, "app")
    run(["/usr/bin/xcrun", "stapler", "staple", app], label="staple-app")
    write_json(output / "app-validation.json", verify_mac(app, args.team_id, stapled=True))
    # The distributed ZIP must contain the stapled app, not the pre-notary upload copy.
    run(["/usr/bin/ditto", "-c", "-k", "--keepParent", app, output / "Memoshi.zip"], label="archive-stapled-app")
    with tempfile.TemporaryDirectory(prefix="memoshi-release-dmg-") as directory:
        stage = Path(directory) / "stage"
        stage.mkdir()
        run(["/usr/bin/ditto", app, stage / "Memoshi.app"], label="stage-stapled-app")
        (stage / "Applications").symlink_to("/Applications")
        dmg = output / "Memoshi.dmg"
        run(["/usr/bin/hdiutil", "create", "-volname", "Memoshi", "-srcfolder", stage, "-format", "UDZO", "-fs", "HFS+", dmg], label="create-drag-to-Applications-DMG")
    run(["/usr/bin/codesign", "--force", "--sign", args.identity, "--identifier", MOBILE_ID + ".dmg", "--timestamp", dmg], label="sign-DMG")
    notary(dmg, args, output, "dmg")
    run(["/usr/bin/xcrun", "stapler", "staple", dmg], label="staple-DMG")
    verify_dmg(dmg, app, args.team_id)
    measurement = measure_sizes(app, dmg)
    measurement.update({"measuredAt": iso(dt.datetime.now(UTC)), "qualification": "Developer-ID-G2-notarized-stapled"})
    write_json(output / "sizes.json", measurement)
    if baseline is not None:
        check_sizes(baseline, measurement)
    else:
        write_json(output / "size-baseline.json", measurement)
        print("Initial measured size baseline recorded; review it explicitly before committing or using it as CI authority")
    with (output / "SHA256SUMS").open("x") as stream:
        for filename in ("Memoshi.zip", "Memoshi.dmg"):
            stream.write(f"{file_digest(output / filename)}  {filename}\n")
    upload.unlink()  # Not a distributable: it contains the app before stapling.
    print(f"Validated release artifacts: {output}; clean-VM/physical-Mac and live service/device acceptance remain separate")


def archive(args):
    reject_untrusted_ci()
    require_release_ready()
    team_id(args.team_id)
    require(re.fullmatch(r"[1-9][0-9]*", args.build_number) is not None, "new archive --build-number must be an increasing integer")
    output = Path(args.output).expanduser().resolve()
    require(not output.exists(), "archive output already exists; use a new output path")
    source = release_source(args.source_tag, args.version)
    extra = []
    if args.platform == "ios":
        identity_preflight(args.identity, args.team_id, mobile=True)
        snapshot = json_file(args.builds_json)
        fresh_snapshot(snapshot, dt.datetime.now(UTC))
        builds = ios_builds(snapshot, args.app_id)
        require(all(build_number(args.build_number) > build_number(item["version"]) for item in builds), "new build number must exceed every existing iOS build, including expired and failed uploads")
        intended, receipt = validate_profile(profile_data(args.profile), args.team_id, MOBILE_ID, dt.datetime.now(UTC))
        output = fresh_output(output)
        entitlements = output / "MemoshiMobile.entitlements"
        write_plist(entitlements, intended)
        extra = [
            f"DEVELOPMENT_TEAM={args.team_id}",
            "MEMOSHI_MOBILE_CODE_SIGN_STYLE=Manual",
            f"MEMOSHI_MOBILE_CODE_SIGN_IDENTITY={args.identity}",
            f"MEMOSHI_MOBILE_PROVISIONING_PROFILE_SPECIFIER={receipt['uuid']}",
            f"MEMOSHI_MOBILE_CODE_SIGN_ENTITLEMENTS={entitlements}",
        ]
    else:
        output = fresh_output(output)
        extra = [f"DEVELOPMENT_TEAM={args.team_id}", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO"]
    name = "MemoshiMobile" if args.platform == "ios" else "Memoshi"
    archive_path = output / f"{name}.xcarchive"
    run(["/usr/bin/xcodebuild", "archive", "-quiet", "-project", ROOT / "apps/mac/Memoshi.xcodeproj", "-scheme", name,
         "-configuration", "Release", "-destination", "generic/platform=iOS" if args.platform == "ios" else "generic/platform=macOS",
         "-archivePath", archive_path, "-derivedDataPath", output / "DerivedData",
         "-disableAutomaticPackageResolution",  # Only the lock that generate-project.sh wrote from the committed pins.
         "ARCHS=arm64", "ONLY_ACTIVE_ARCH=NO",
         f"MARKETING_VERSION={args.version}", f"CURRENT_PROJECT_VERSION={args.build_number}"] + extra, label="Release-archive")
    app = archive_path / f"Products/Applications/{name}.app"
    info = plist_file(app / ("Info.plist" if args.platform == "ios" else "Contents/Info.plist"))
    require(info.get("CFBundleVersion") == args.build_number and info.get("CFBundleShortVersionString") == args.version, "archived version/build does not match the explicit release inputs")
    validate_device_access_group(info, args.team_id)
    if args.platform == "macos":
        run([ROOT / "scripts/check-bundle.sh", app], label="archived-bundle-layout")
        run([ROOT / "scripts/check-bundle.sh", "--release-composition", app], label="archived-release-composition")
    else:
        verify_mobile(app, args.team_id, receipt["uuid"])
    write_json(output / "archive.json", {"sourceCommit": source, "sourceTag": args.source_tag, "version": args.version, "buildNumber": args.build_number, "platform": args.platform})
    print(f"Release archive: {archive_path}; no upload or device installation performed")


def upload_testflight(args):
    reject_untrusted_ci()
    require_release_ready()
    key = api_inputs(args)
    team_id(args.team_id)
    identity_preflight(args.identity, args.team_id, mobile=True)
    archive_path = Path(args.archive).expanduser().resolve(strict=True)
    info = plist_file(archive_path / "Products/Applications/MemoshiMobile.app/Info.plist")
    verify_mobile(archive_path / "Products/Applications/MemoshiMobile.app", args.team_id)
    snapshot = json_file(args.builds_json)
    fresh_snapshot(snapshot, dt.datetime.now(UTC))
    require(all(build_number(info.get("CFBundleVersion")) > build_number(item["version"]) for item in ios_builds(snapshot, args.app_id)), "archived build number is not newer than all existing uploads")
    profile = profile_data(args.profile)
    _, receipt = validate_profile(profile, args.team_id, MOBILE_ID, dt.datetime.now(UTC))
    # Ask the selected toolchain for support rather than silently omitting internal-only.
    help_result = run(["/usr/bin/xcodebuild", "-help"], label="export-options-support")
    require(b"testFlightInternalTestingOnly" in help_result.stdout + help_result.stderr, "selected Xcode cannot guarantee TestFlight internal-only export")
    output = fresh_output(args.output)
    options = {"method": "app-store-connect", "destination": "upload", "teamID": args.team_id,
               "signingStyle": "manual", "signingCertificate": args.identity,
               "provisioningProfiles": {MOBILE_ID: receipt["uuid"]}, "testFlightInternalTestingOnly": True,
               "manageAppVersionAndBuildNumber": False, "uploadSymbols": True}
    write_plist(output / "ExportOptions.plist", options)
    run(["/usr/bin/xcodebuild", "-exportArchive", "-archivePath", archive_path,
         "-exportOptionsPlist", output / "ExportOptions.plist", "-exportPath", output / "export",
         "-authenticationKeyPath", key, "-authenticationKeyID", args.key_id,
         "-authenticationKeyIssuerID", args.issuer_id], label="TestFlight-internal-only-upload")
    write_json(output / "upload.json", {"appID": args.app_id, "bundleID": MOBILE_ID, "buildNumber": info["CFBundleVersion"], "uploadedAt": iso(dt.datetime.now(UTC)), "internalOnly": True, "processingConfirmed": False})
    print("Upload command completed; confirm-testflight-upload must confirm this build's processing/internal availability. Physical installs are not proved.")


def fetch_testflight(args):
    reject_untrusted_ci()
    key = api_inputs(args)
    require(args.app_id.isdecimal(), "--app-id must be the App Store Connect numeric app resource ID")
    require(not Path(args.output).exists(), "snapshot output already exists; use a fresh path")
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
    now = int(dt.datetime.now(UTC).timestamp())
    header = encode(json.dumps({"alg": "ES256", "kid": args.key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    claims = encode(json.dumps({"iss": args.issuer_id, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    signing_input = header + b"." + claims
    # The signature completes a bearer token that is valid for ten minutes: it is never logged.
    signature = run(["/usr/bin/openssl", "dgst", "-sha256", "-sign", key], data=signing_input, label="API-JWT-signature", secret_output=True).stdout
    token = (signing_input + b"." + encode(ecdsa_jose(signature))).decode()

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, request, response, code, message, headers, new_url):
            raise ReleaseError("refusing to redirect an App Store Connect bearer token")

    opener = urllib.request.build_opener(NoRedirect)

    def get(url):
        parsed = urllib.parse.urlsplit(url)
        require(parsed.scheme == "https" and parsed.netloc == "api.appstoreconnect.apple.com" and parsed.path.startswith("/v1/"), "refusing a non-App-Store-Connect API/pagination URL")
        request = urllib.request.Request(url, headers={"Authorization": "Bearer " + token, "Accept": "application/json"})
        try:
            with opener.open(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # A server error refuses nothing; every other status is App Store Connect's answer.
            failure = APIUnavailable if error.code >= 500 else ReleaseError
            raise failure(f"App Store Connect API returned HTTP {error.code}; check authorized key role/app access, not account quotas or billing workarounds") from error
        except OSError as error:  # URLError, a timed-out read or a reset connection.
            raise APIUnavailable("App Store Connect API network prerequisite failed") from error

    app = get(f"https://api.appstoreconnect.apple.com/v1/apps/{args.app_id}?fields[apps]=bundleId")
    require(app.get("data", {}).get("attributes", {}).get("bundleId") == MOBILE_ID, "App Store Connect app ID is not MemoshiMobile")
    query = urllib.parse.urlencode({"filter[app]": args.app_id, "include": "app,preReleaseVersion,buildBetaDetail", "sort": "-uploadedDate", "limit": "200"})
    url = "https://api.appstoreconnect.apple.com/v1/builds?" + query
    document = {"appID": args.app_id, "bundleID": MOBILE_ID, "fetchedAt": iso(dt.datetime.now(UTC)), "complete": False, "data": [], "included": []}
    visited, included = set(), {}
    while url:
        require(url not in visited, "App Store Connect returned a pagination loop; snapshot is incomplete")
        visited.add(url)
        page = get(url)
        require(isinstance(page.get("data"), list), "App Store Connect returned no builds array")
        document["data"].extend(page["data"])
        for item in page.get("included", []):
            included[(item["type"], item["id"])] = item
        url = page.get("links", {}).get("next")
    document["included"] = list(included.values())
    document["complete"] = True
    ios_builds(document, args.app_id)
    write_json(args.output, document)
    print(f"Fetched complete App Store Connect build snapshot: {args.output}; no upload/account changes")


def confirm_testflight_upload(args):
    """Poll fresh complete snapshots until the uploaded build itself is usable by internal testers."""
    reject_untrusted_ci()
    build_number(args.build_number)
    require(args.timeout_minutes > 0, "--timeout-minutes must be a positive bound on the processing wait")
    output = fresh_output(args.output)
    deadline = time.monotonic() + args.timeout_minutes * 60
    attempt = 0
    while True:
        attempt += 1
        snapshot = output / f"builds-{attempt:03d}.json"
        try:
            fetch_testflight(argparse.Namespace(**{**vars(args), "output": snapshot}))
            return testflight_status(json_file(snapshot), args.app_id, dt.datetime.now(UTC), expect=args.build_number)
        except (BuildPending, APIUnavailable) as pending:
            # The upload succeeded and its build number is spent, so a failed request is waited
            # out like a build that is still processing; a refusal (HTTP 4xx) or an invalid
            # snapshot is not.
            require(time.monotonic() + TESTFLIGHT_POLL_SECONDS <= deadline,
                    f"{pending}; not confirmed within {args.timeout_minutes} minutes")
            time.sleep(TESTFLIGHT_POLL_SECONDS)


def report_testflight(result):
    print(json.dumps(result, indent=2))
    if result["refreshDue"] or result["nearExpiry"]:
        print("warning: rebuild the latest release with a higher build number and upload internal-only before expiry", file=sys.stderr)
        return 2
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    command = sub.add_parser("check-release-gates", help="read-only check of explicit holds and the accepted exact SDK tag")
    command.set_defaults(action=lambda args: (require_release_ready(), print("Explicit release and SDK acceptance gates passed")))

    def mac_inputs(command):
        command.add_argument("--app", required=True, help="actual Memoshi.app input; never a simulator or fabricated bundle")
        command.add_argument("--team-id", required=True)

    def api_arguments(command):
        command.add_argument("--api-key", required=True, help="existing owner-only .p8 file; never imported or copied")
        command.add_argument("--key-id", required=True)
        command.add_argument("--issuer-id", required=True)

    command = sub.add_parser("sign", help="copy and sign all nested Mac code inside-out; embed two separately supplied profiles")
    mac_inputs(command)
    command.add_argument("--identity", required=True, help="installed Developer ID Application certificate SHA-1")
    command.add_argument("--app-profile", required=True)
    command.add_argument("--helper-profile", required=True)
    command.add_argument("--output", required=True, help="new output directory; input app is never modified")
    command.set_defaults(action=sign)

    command = sub.add_parser("check-mac", help="fail-closed static verification of every Mach-O, identity, entitlement and profile")
    mac_inputs(command)
    command.add_argument("--stapled", action="store_true", help="also require app staple and Gatekeeper acceptance")
    command.set_defaults(action=lambda args: print(json.dumps(verify_mac(args.app, args.team_id, args.stapled), indent=2)))

    command = sub.add_parser("check-dmg", help="verify actual signed/stapled DMG, read-only mount and exact embedded app; no notarization upload")
    mac_inputs(command)
    command.add_argument("--dmg", required=True)
    command.set_defaults(action=check_dmg)

    command = sub.add_parser("record-size-baseline", help="record budgets only from verified actual Developer ID/notarized/stapled artifacts")
    mac_inputs(command)
    command.add_argument("--dmg", required=True)
    command.add_argument("--output", required=True, help="new JSON file; explicitly review before committing it as the CI baseline")
    command.set_defaults(action=record_size_baseline)

    command = sub.add_parser("package", help="notarize/staple copied app, then sign/notarize/staple/validate DMG and enforce measured budgets")
    mac_inputs(command)
    api_arguments(command)
    command.add_argument("--identity", required=True)
    command.add_argument("--output", required=True)
    budgets = command.add_mutually_exclusive_group(required=True)
    budgets.add_argument("--baseline", help="previously reviewed actual release size-baseline JSON")
    budgets.add_argument("--initial-size-baseline", action="store_true", help="only for first actual notarized artifacts; records measurements, never invents numbers")
    command.set_defaults(action=package)

    command = sub.add_parser("check-sizes", help="measure real app/DMG bytes and reject ANY component growing more than 10%%")
    command.add_argument("--app", required=True)
    command.add_argument("--dmg", required=True)
    command.add_argument("--baseline", required=True)
    command.set_defaults(action=lambda args: (check_sizes(json_file(args.baseline), measure_sizes(args.app, args.dmg)), print("All measured components are within their reviewed 10% growth limits")))

    command = sub.add_parser("archive", help="Release archive from a clean exact tag; enforce the existing SDK/toolchain/disk prerequisites")
    command.add_argument("--platform", choices=("macos", "ios"), required=True)
    command.add_argument("--version", required=True)
    command.add_argument("--source-tag", required=True)
    command.add_argument("--build-number", required=True)
    command.add_argument("--output", required=True)
    command.add_argument("--team-id", required=True, help="selected Apple Team ID; resolves device identity metadata even in an unsigned Mac archive")
    for name in ("identity", "profile", "builds-json", "app-id"):
        command.add_argument("--" + name, help="required for --platform ios")
    command.set_defaults(action=archive)

    command = sub.add_parser("upload-testflight", help="upload an actual iOS archive with internal-only enforcement; never submits App Review")
    api_arguments(command)
    for name in ("archive", "team-id", "identity", "profile", "builds-json", "app-id", "output"):
        command.add_argument("--" + name, required=True)
    command.set_defaults(action=upload_testflight)

    command = sub.add_parser("fetch-testflight", help="read-only complete App Store Connect snapshot for monotonically increasing builds/expiry")
    api_arguments(command)
    command.add_argument("--app-id", required=True)
    command.add_argument("--output", required=True)
    command.set_defaults(action=fetch_testflight)

    command = sub.add_parser("confirm-testflight-upload", help="after an upload: poll fresh snapshots until exactly that build number is processed and available to internal testers; an older usable build never satisfies it")
    api_arguments(command)
    command.add_argument("--app-id", required=True)
    command.add_argument("--build-number", required=True, help="the build number that was just uploaded")
    command.add_argument("--timeout-minutes", required=True, type=int, help="bounded wait for App Store Connect processing")
    command.add_argument("--output", required=True, help="new directory for the polled snapshots")
    command.set_defaults(action=None)

    command = sub.add_parser("testflight-status", help="fail without a current usable internal build; exit 2 when the 30-day refresh/expiry warning is due")
    command.add_argument("--builds-json", required=True)
    command.add_argument("--app-id", required=True)
    command.set_defaults(action=None)

    command = sub.add_parser("next-build-number", help="choose an integer greater than EVERY iOS build in a fresh complete ASC snapshot")
    command.add_argument("--builds-json", required=True)
    command.add_argument("--app-id", required=True)
    command.set_defaults(action=None)

    args = parser.parse_args()
    if args.command == "archive" and args.platform == "ios":
        for name in ("identity", "team_id", "profile", "builds_json", "app_id"):
            require(getattr(args, name) is not None, f"--platform ios requires --{name.replace('_', '-')}; profiles/identity must already be installed separately")
    if args.command in ("testflight-status", "next-build-number"):
        document = json_file(args.builds_json)
        fresh_snapshot(document, dt.datetime.now(UTC))
        if args.command == "next-build-number":
            builds = ios_builds(document, args.app_id)
            print(max((build_number(item["version"])[0] for item in builds), default=0) + 1)
            return 0
        return report_testflight(testflight_status(document, args.app_id, dt.datetime.now(UTC)))
    if args.command == "confirm-testflight-upload":
        return report_testflight(confirm_testflight_upload(args))
    args.action(args)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ReleaseError, OSError, ValueError, TypeError, KeyError, plistlib.InvalidFileException) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
