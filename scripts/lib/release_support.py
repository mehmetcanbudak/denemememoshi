"""Pure release policy. No credentials, subprocesses, downloads or invented size budgets."""

import datetime as dt
import hashlib
import os
from pathlib import Path
import re
import stat
import struct

APP_ID = "com.mehmetcanbudak.memoshi.mac"
HELPER_ID = "com.mehmetcanbudak.memoshi.memoshid"
MOBILE_ID = "com.mehmetcanbudak.memoshi"
CONTAINER = "iCloud.com.mehmetcanbudak.memoshi"
HELPER = "Contents/Helpers/memoshid.app"
AGENT = f"Contents/Library/LaunchAgents/{HELPER_ID}.plist"
UTC = dt.timezone.utc
FORBIDDEN = {
    "com.apple.security.cs.allow-jit",
    "com.apple.security.cs.allow-unsigned-executable-memory",
    "com.apple.security.cs.disable-library-validation",
    "com.apple.security.cs.allow-dyld-environment-variables",
    "com.apple.security.cs.disable-executable-page-protection",
    "com.apple.security.get-task-allow",
    "get-task-allow",
}
# Entitlements that the signature alone grants and no provisioning profile lists (D125).
SIGNATURE_GRANTED = frozenset({"com.apple.security.device.camera"})
MACH_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}
# App Store Connect InternalBetaState values (a build beta detail's internalBuildState) that
# waiting out processing does not turn into IN_BETA_TESTING: export compliance needs an answer or
# Apple's review, processing failed, or the build expired. PROCESSING and READY_FOR_BETA_TESTING
# stay pending.
TERMINAL_INTERNAL_STATES = frozenset({"MISSING_EXPORT_COMPLIANCE", "PROCESSING_EXCEPTION", "IN_EXPORT_COMPLIANCE_REVIEW", "EXPIRED"})


class ReleaseError(Exception):
    pass


class BuildPending(ReleaseError):
    """The expected upload is not usable yet; a later snapshot may show it."""


class APIUnavailable(ReleaseError):
    """A request got no answer (network failure, timeout or server error); nothing was refused."""


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


def timestamp(value):
    if isinstance(value, dt.datetime):
        return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
    require(isinstance(value, str), "missing or invalid timestamp")
    result = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(result.tzinfo is not None, "timestamp must include a timezone")
    return result.astimezone(UTC)


def iso(value):
    return timestamp(value).isoformat().replace("+00:00", "Z")


def team_id(value):
    require(re.fullmatch(r"[A-Z0-9]{10}", value) is not None, "--team-id must be a ten-character Apple Team ID")
    return value


def intended_entitlements(team, bundle_id, prefix):
    team_id(team)
    require(bundle_id in (APP_ID, HELPER_ID, MOBILE_ID), "unsupported provisioned bundle identifier")
    require(re.fullmatch(r"[A-Z0-9]{10}", prefix) is not None, "invalid AppIdentifierPrefix in profile")
    mobile = bundle_id == MOBILE_ID
    result = {
        "application-identifier" if mobile else "com.apple.application-identifier": f"{prefix}.{bundle_id}",
        "com.apple.developer.team-identifier": team,
        "com.apple.developer.icloud-services": ["CloudKit"],
        "com.apple.developer.icloud-container-identifiers": [CONTAINER],
        "com.apple.developer.icloud-container-environment": "Production",
        "aps-environment" if mobile else "com.apple.developer.aps-environment": "production",
    }
    if bundle_id == APP_ID:
        # D125: the Mac app may use the camera, for the pairing scanner only; memoshid never.
        result["com.apple.security.device.camera"] = True
    if bundle_id != HELPER_ID:
        result["keychain-access-groups"] = [
            f"{team}.com.mehmetcanbudak.memoshi.secrets",
            f"{team}.com.mehmetcanbudak.memoshi.devices",
        ]
    if mobile:
        result.update({
            "com.apple.developer.kernel.increased-memory-limit": True,
            "com.apple.developer.kernel.extended-virtual-addressing": True,
            "beta-reports-active": True,
            "get-task-allow": False,
        })
    return result


def validate_device_access_group(info, team):
    """Reject unresolved/legacy-prefix bundle metadata before credential or device operations."""
    team_id(team)
    require(isinstance(info, dict) and info.get("MemoshiDeviceIdentityAccessGroup") ==
            f"{team}.com.mehmetcanbudak.memoshi.devices",
            "app Info.plist device identity access group must resolve to the selected Team ID")


def canonical(value):
    if isinstance(value, dict):
        return {key: canonical(item) for key, item in sorted(value.items())}
    if isinstance(value, list):
        return sorted((canonical(item) for item in value), key=repr)
    return type(value).__name__, value


def validate_entitlements(actual, expected):
    require(isinstance(actual, dict), "signed entitlements must be a dictionary")
    require(not any(actual.get(key) is not None and actual.get(key) is not False for key in FORBIDDEN),
            "release code carries a forbidden JIT, debugger or hardened-runtime exception entitlement")
    require(canonical(actual) == canonical(expected),
            f"signed entitlements differ from intended policy (keys: {', '.join(sorted(actual)) or 'none'})")


def authorizes(allowed, requested):
    if isinstance(requested, list):
        if isinstance(allowed, str):
            return all(authorizes(allowed, wanted) for wanted in requested)
        return isinstance(allowed, list) and all(any(authorizes(item, wanted) for item in allowed) for wanted in requested)
    if isinstance(allowed, list):
        return any(authorizes(item, requested) for item in allowed)
    if isinstance(requested, str) and isinstance(allowed, str):
        # Apple profile wildcards are trailing-prefix wildcards, not arbitrary glob patterns.
        return allowed == requested or (allowed.endswith("*") and "*" not in allowed[:-1] and requested.startswith(allowed[:-1]))
    return type(allowed) is type(requested) and allowed == requested


def validate_profile(profile, team, bundle_id, now, certificate=None):
    require(isinstance(profile, dict), "provisioning profile is not a dictionary")
    require(profile.get("TeamIdentifier") == [team], "profile belongs to a different Team ID")
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    require(isinstance(prefixes, list) and len(prefixes) == 1, "profile must have one explicit AppIdentifierPrefix")
    expected = intended_entitlements(team, bundle_id, prefixes[0])
    entitlements = profile.get("Entitlements", {})
    require(isinstance(entitlements, dict), "profile has no entitlement dictionary")
    identity_key = "application-identifier" if bundle_id == MOBILE_ID else "com.apple.application-identifier"
    require(entitlements.get(identity_key) == expected[identity_key], "profile is not for this exact App ID (wildcard profiles are not release inputs)")
    require(entitlements.get("get-task-allow", False) is False and entitlements.get("com.apple.security.get-task-allow", False) is False,
            "development/debuggable profile cannot authorize distribution")
    if bundle_id == MOBILE_ID:
        require(not profile.get("ProvisionedDevices") and not profile.get("ProvisionsAllDevices"),
                "TestFlight needs an App Store distribution profile, not development, ad-hoc or enterprise")
        require(entitlements.get("beta-reports-active") is True, "profile does not authorize TestFlight beta reporting")
        minimum = dt.timedelta(0)
    else:
        require(profile.get("ProvisionsAllDevices") is True and not profile.get("ProvisionedDevices"),
                "Mac release needs a Developer ID provisioning profile")
        minimum = dt.timedelta(days=365)
    expiry = timestamp(profile.get("ExpirationDate"))
    require(expiry > timestamp(now) + minimum,
            "Developer ID profile expires within one year" if bundle_id != MOBILE_ID else "TestFlight signing profile has expired")
    require(isinstance(profile.get("UUID"), str) and profile["UUID"], "profile has no UUID")
    for key, value in expected.items():
        require(key in SIGNATURE_GRANTED or authorizes(entitlements.get(key), value),
                f"profile does not authorize required entitlement {key}")
    if bundle_id == HELPER_ID:
        # Apple Developer Portal unconditionally injects [f"{team}.*"] into every Developer ID
        # provisioning profile; the helper binary itself is still signed without keychain-access-groups
        # (enforced by intended_entitlements + validate_entitlements). Reject any explicit group here.
        helper_groups = entitlements.get("keychain-access-groups")
        require(not helper_groups or helper_groups == [f"{team}.*"],
                "helper profile must not authorize explicit Keychain groups")
    if certificate is not None:
        require(certificate in profile.get("DeveloperCertificates", []), "signing certificate is not authorized by this profile")
    return expected, {"uuid": profile["UUID"], "expiresAt": iso(expiry), "appID": expected[identity_key]}


def missing_runtime_licences(app, table, root):
    """Retained licence files (D126) that an app with the Python runtime does not carry.

    `table` is scripts/pyodide-licenses.json and `root` the repository. The runtime is any
    directory that holds pyodide.asm.wasm, whatever it is called; an app without one needs
    none. Otherwise every licence text the table retains from a source release, and every
    piece of outside evidence, must be inside a runtime directory with the retained bytes.
    Returns the repository paths that are not.
    """
    require(Path(app).is_dir(), f"{app} is not an existing app directory; its runtime licences cannot be checked")
    runtimes = sorted(path.parent for path in Path(app).rglob("pyodide.asm.wasm"))
    if not runtimes:
        return []
    needed = {}
    for row in table["packages"]:
        items = list(row.get("retained", {}).get("texts", []))
        for part in row.get("withoutLicenceText", []):
            items.extend(part.get("evidence", []))
        for item in items:
            needed[item["path"]] = (Path(root) / item["path"]).read_bytes()
    sizes = {len(content) for content in needed.values()}
    carried = set()
    for runtime in runtimes:
        for path in runtime.rglob("*"):
            if path.is_file() and not path.is_symlink() and path.stat().st_size in sizes:
                carried.add(path.read_bytes())
    return sorted(path for path, content in needed.items() if content not in carried)


def artifact_files(root):
    """Physical paths only; reject escaped links and special files before signing/copying."""
    root = Path(root).resolve(strict=True)
    require(root.is_dir(), "app input is not a directory")
    result = []
    for directory, names, files in os.walk(root, followlinks=False):
        names.sort()
        files.sort()
        for name in names + files:
            path = Path(directory) / name
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                try:
                    path.resolve(strict=True).relative_to(root)
                except (ValueError, OSError, RuntimeError):
                    raise ReleaseError(f"bundle contains an escaped or broken symlink: {path.relative_to(root)}")
                result.append(path)
            elif stat.S_ISREG(mode):
                result.append(path)
            else:
                require(stat.S_ISDIR(mode), f"bundle contains a special file: {path.relative_to(root)}")
    return result


def is_mach_o(path):
    if path.is_symlink():
        return False
    with path.open("rb") as stream:
        return stream.read(4) in MACH_MAGICS


def is_executable_mach_o(path):
    little = {b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe", b"\xbe\xba\xfe\xca", b"\xbf\xba\xfe\xca"}
    fat = {b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
    fat64 = {b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
    with path.open("rb") as stream:
        def number(endian, width=4):
            data = stream.read(width)
            require(len(data) == width, f"truncated Mach-O header: {path}")
            return struct.unpack(endian + ("Q" if width == 8 else "I"), data)[0]

        magic = stream.read(4)
        require(magic in MACH_MAGICS, f"not a Mach-O file: {path}")
        endian = "<" if magic in little else ">"
        if magic in fat:
            require(number(endian) > 0, f"empty universal Mach-O header: {path}")
            stream.seek(16)
            offset = number(endian, 8 if magic in fat64 else 4)
            require(8 <= offset <= path.stat().st_size - 16, f"invalid universal Mach-O slice offset: {path}")
            stream.seek(offset)
            magic = stream.read(4)
            require(magic in MACH_MAGICS - fat, f"invalid universal Mach-O slice: {path}")
            endian = "<" if magic in little else ">"
        stream.seek(8, 1)
        return number(endian) == 2


def component_name(relative):
    parts = Path(relative).parts
    if relative == HELPER or relative.startswith(HELPER + "/"):
        return "memoshid"
    for index, part in enumerate(parts):
        if part == "Sparkle.framework":
            return "Sparkle"
        if index >= 2 and parts[index - 1] in ("Helpers", "PlugIns", "Plug-ins", "Frameworks", "XPCServices"):
            return "component:" + "/".join(parts[:index + 1])
    return "app"


def measure_sizes(app, dmg):
    app, dmg = Path(app).expanduser().resolve(strict=True), Path(dmg).expanduser()
    require(dmg.is_file() and not dmg.is_symlink(), "DMG input must be a regular file, not a symlink")
    dmg = dmg.resolve(strict=True)
    sizes = {"app": 0, "memoshid": 0}
    tree = hashlib.sha256()
    for path in artifact_files(app):
        relative = path.relative_to(app).as_posix()
        component = component_name(relative)
        link = path.is_symlink()
        size = len(os.fsencode(os.readlink(path))) if link else path.stat().st_size
        digest = hashlib.sha256(os.fsencode(os.readlink(path))).hexdigest() if link else file_digest(path)
        sizes[component] = sizes.get(component, 0) + size
        tree.update(f"{relative}\0{int(link)}\0{path.lstat().st_mode & 0o7777:o}\0{size}\0{digest}\n".encode())
    require(sizes["app"] > 0 and sizes["memoshid"] > 0, "app and memoshid must both be present and nonempty")
    sizes["installed_total"] = sum(sizes.values())
    sizes["dmg"] = dmg.stat().st_size
    require(sizes["dmg"] > 0, "DMG is empty")
    return {"schemaVersion": 1, "metric": "logical-file-bytes-plus-symlink-target-bytes",
            "sizes": sizes, "appTreeSHA256": tree.hexdigest(), "dmgSHA256": file_digest(dmg)}


def file_digest(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def check_sizes(baseline, measured):
    require(baseline.get("schemaVersion") == 1 and baseline.get("metric") == measured["metric"], "size baseline uses an unsupported metric/schema")
    require(baseline.get("qualification") == "Developer-ID-G2-notarized-stapled", "size baseline must come from qualified actual release artifacts")
    for key in ("appTreeSHA256", "dmgSHA256"):
        require(re.fullmatch(r"[0-9a-f]{64}", baseline.get(key, "")) is not None, "size baseline lacks artifact digests")
    limits = baseline.get("sizes", {})
    require(limits.keys() == measured["sizes"].keys(), "component inventory changed; measure and explicitly review a new qualified baseline")
    failures = []
    for name, current in measured["sizes"].items():
        budget = limits[name]
        require(type(budget) is int and budget > 0, f"missing measured budget for {name}")
        if current * 10 > budget * 11:
            failures.append(f"{name}: {current} bytes exceeds measured {budget}-byte budget by more than 10%")
    require(not failures, "; ".join(failures))


def build_number(value):
    require(isinstance(value, str) and re.fullmatch(r"[1-9][0-9]*(?:\.[0-9]+){0,2}", value) is not None, "invalid App Store build number")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def _object(value):
    """A JSON object, or {} for an absent or null one: App Store Connect sends null relationships."""
    return value if isinstance(value, dict) else {}


def ios_builds(document, app_id):
    require(document.get("complete") is True, "build snapshot must be a complete fetch-testflight snapshot (all pages)")
    require(document.get("appID") == app_id and document.get("bundleID") == MOBILE_ID, "TestFlight snapshot belongs to another app")
    require(isinstance(document.get("data"), list), "TestFlight snapshot has no builds array")
    included = {(item["type"], item["id"]): item for item in document.get("included", [])}
    result = []
    for build in document["data"]:
        require(isinstance(build, dict) and build.get("type") == "builds", "snapshot includes an unexpected resource")
        relationships = _object(build.get("relationships"))
        relation = _object(_object(relationships.get("preReleaseVersion")).get("data"))
        version = included.get((relation.get("type"), relation.get("id")))
        require(version is not None, "build snapshot lacks included preReleaseVersion; platform cannot be verified")
        if _object(version.get("attributes")).get("platform") != "IOS":
            continue
        app_relation = _object(_object(relationships.get("app")).get("data"))
        require(app_relation.get("id") == app_id and app_relation.get("type") == "apps", "build belongs to another App Store app")
        attributes = _object(build.get("attributes"))
        build_number(attributes.get("version"))
        detail = _object(_object(relationships.get("buildBetaDetail")).get("data"))
        beta = _object(_object(included.get((detail.get("type"), detail.get("id")))).get("attributes"))
        result.append({"id": build["id"], **attributes, "internalBuildState": beta.get("internalBuildState")})
    return result


def fresh_snapshot(document, now):
    fetched = timestamp(document.get("fetchedAt"))
    require(dt.timedelta(0) <= timestamp(now) - fetched <= dt.timedelta(hours=24), "App Store snapshot must have been fetched within the last 24 hours")


def testflight_status(document, app_id, now, expect=None):
    """Status of the newest usable internal build, or of exactly build number `expect`.

    After an upload pass `expect`: an older usable build then never answers for the new one,
    and a build that App Store Connect has not finished processing raises BuildPending.
    """
    fresh_snapshot(document, now)
    builds = ios_builds(document, app_id)
    candidates = builds
    if expect is not None:
        wanted = build_number(expect)
        candidates = [item for item in builds if build_number(item["version"]) == wanted]
        if not candidates:
            raise BuildPending(f"uploaded build {expect} is still processing: App Store Connect does not list it yet")
        require(len(candidates) == 1, f"App Store Connect lists build {expect} more than once")
        require(candidates[0].get("processingState") not in ("FAILED", "INVALID"),
                f"uploaded build {expect} failed App Store Connect processing")
        state = candidates[0].get("internalBuildState")
        require(state not in TERMINAL_INTERNAL_STATES,
                f"uploaded build {expect} needs more than processing before internal testers can use it: App Store Connect reports "
                f"internalBuildState {state}")
    else:
        require(builds, "no iOS TestFlight builds exist; an initial signed internal upload is required")
    eligible = [item for item in candidates if item.get("processingState") == "VALID"
                and item.get("buildAudienceType") == "INTERNAL_ONLY"
                and item.get("expired") is False
                and item.get("internalBuildState") == "IN_BETA_TESTING"
                and timestamp(item.get("expirationDate")) > timestamp(now)]
    if expect is not None and not eligible:
        raise BuildPending(f"uploaded build {expect} is still processing or not yet available to internal testers "
                           f"(processingState {candidates[0].get('processingState')}, "
                           f"internalBuildState {candidates[0].get('internalBuildState')})")
    require(eligible, "no unexpired, processed internal-only iOS build is available to testers")
    newest = max(eligible, key=lambda item: timestamp(item.get("uploadedDate")))
    uploaded, expires = timestamp(newest.get("uploadedDate")), timestamp(newest.get("expirationDate"))
    require(uploaded <= timestamp(now) < expires and expires > uploaded, "TestFlight dates are inconsistent")
    refresh_due = timestamp(now) - uploaded >= dt.timedelta(days=30)
    near_expiry = expires - timestamp(now) <= dt.timedelta(days=30)
    return {"buildID": newest["id"], "buildNumber": newest["version"], "uploadedAt": iso(uploaded),
            "expiresAt": iso(expires), "refreshDue": refresh_due, "nearExpiry": near_expiry,
            "nextBuildNumber": str(max(build_number(item["version"])[0] for item in builds) + 1)}


def ecdsa_jose(der):
    """Convert an OpenSSL P-256 DER signature to JWT's fixed-width r || s."""
    require(len(der) >= 8 and der[0] == 0x30 and der[1] == len(der) - 2, "invalid ES256 DER signature")
    offset, values = 2, []
    for _ in range(2):
        require(offset + 2 <= len(der) and der[offset] == 2, "invalid ES256 integer")
        length = der[offset + 1]
        value = der[offset + 2:offset + 2 + length]
        require(len(value) == length and length > 0 and value[0] < 0x80, "invalid ES256 integer length/sign")
        value = value.lstrip(b"\0")
        require(len(value) <= 32, "ES256 signature is not P-256")
        values.append(value.rjust(32, b"\0"))
        offset += length + 2
    require(offset == len(der), "trailing ES256 signature bytes")
    return b"".join(values)


def validate_release_gate(record, consumer_revision):
    """Validate checked-in human acceptance metadata; it is not SDK conformance evidence."""
    require(isinstance(record, dict) and record.get("schemaVersion") == 1,
            "release qualification record is missing or has an unsupported schema")
    holds = record.get("holds", {})
    require(holds.get("releaseBlocked") is False and
            holds.get("broaderQualificationBlocked") is False,
            "release and broader qualification remain explicitly blocked")
    sdk = record.get("sdk", {})
    require(sdk.get("consumerRevision") == consumer_revision,
            "SDK acceptance does not match the exact consumer revision")
    require(sdk.get("qualification") == "accepted" and
            isinstance(sdk.get("qualifyingTag"), str) and
            re.fullmatch(r"slice-[1-9][0-9]*(?:\.[0-9]+)*", sdk["qualifyingTag"]) is not None,
            "release requires an accepted qualifying SDK slice tag, not development proof")
    require(isinstance(sdk.get("acceptedBy"), str) and sdk["acceptedBy"].strip() and
            isinstance(sdk.get("evidenceSHA256"), str) and
            re.fullmatch(r"[0-9a-f]{64}", sdk["evidenceSHA256"]) is not None,
            "SDK acceptance requires its reviewer and immutable evidence digest")
    return sdk
