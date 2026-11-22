"""Release-tool behavior tests; run with python3 -m unittest discover -s scripts/tests -v.

Pure policy cases use domain data, not command-output mocks. macOS integration cases
compile real controlled Mach-O files and exercise Apple's actual ad-hoc codesign path;
no identity, account, profile, notarization, upload or device installation is used.
"""

import argparse
import copy
import datetime as dt
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import urllib.error

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/lib"))
import release_support as policy

SPEC = importlib.util.spec_from_file_location("memoshi_release", ROOT / "scripts/release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
NOW = dt.datetime(2026, 11, 3, 12, tzinfo=policy.UTC)
TEAM = "A1B2C3D4E5"


def profile(identifier=policy.APP_ID):
    # A provisioning profile authorizes restricted entitlements only; it never lists the
    # hardened-runtime resource keys (com.apple.security.*) that the signature alone grants.
    entitlements = {key: value for key, value in policy.intended_entitlements(TEAM, identifier, TEAM).items()
                    if not key.startswith("com.apple.security.")}
    return {"TeamIdentifier": [TEAM], "ApplicationIdentifierPrefix": [TEAM], "UUID": identifier,
            "ProvisionsAllDevices": identifier != policy.MOBILE_ID,
            "ExpirationDate": NOW + dt.timedelta(days=366), "Entitlements": entitlements,
            "DeveloperCertificates": [b"controlled-test-certificate"]}


def snapshot(age=1, expires=89, number="7", state="IN_BETA_TESTING", now=NOW):
    return {"appID": "12345", "bundleID": policy.MOBILE_ID, "complete": True, "fetchedAt": policy.iso(now),
            "data": [{"type": "builds", "id": "build-7", "attributes": {
                "version": number, "uploadedDate": policy.iso(now - dt.timedelta(days=age)),
                "expirationDate": policy.iso(now + dt.timedelta(days=expires)),
                "expired": False, "processingState": "VALID", "buildAudienceType": "INTERNAL_ONLY"},
                "relationships": {"app": {"data": {"type": "apps", "id": "12345"}},
                                  "preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": "v1"}},
                                  "buildBetaDetail": {"data": {"type": "buildBetaDetails", "id": "beta1"}}}}],
            "included": [{"type": "preReleaseVersions", "id": "v1", "attributes": {"platform": "IOS"}},
                         {"type": "buildBetaDetails", "id": "beta1", "attributes": {"internalBuildState": state}}]}


def with_upload(data, processing="PROCESSING", beta="PROCESSING", now=NOW):
    """Adds build 99, uploaded at `now`, in the given App Store Connect states."""
    upload = copy.deepcopy(data["data"][0])
    upload["id"] = "new-upload"
    upload["attributes"].update({"version": "99", "processingState": processing, "uploadedDate": policy.iso(now),
                                 "expirationDate": policy.iso(now + dt.timedelta(days=90))})
    upload["relationships"]["buildBetaDetail"]["data"]["id"] = "beta99"
    data["data"].append(upload)
    data["included"].append({"type": "buildBetaDetails", "id": "beta99", "attributes": {"internalBuildState": beta}})
    return data


class ReleasePolicyTests(unittest.TestCase):
    def test_app_and_helper_have_distinct_restricted_authority(self):
        app, _ = policy.validate_profile(profile(), TEAM, policy.APP_ID, NOW, b"controlled-test-certificate")
        helper, _ = policy.validate_profile(profile(policy.HELPER_ID), TEAM, policy.HELPER_ID, NOW)
        self.assertEqual(app["com.apple.developer.icloud-container-identifiers"], helper["com.apple.developer.icloud-container-identifiers"])
        self.assertIn("keychain-access-groups", app)
        self.assertNotIn("keychain-access-groups", helper)
        with self.assertRaisesRegex(policy.ReleaseError, "intended policy"):
            policy.validate_entitlements(app, helper)

    def test_only_the_mac_app_carries_the_camera_entitlement(self):
        # D125: the Mac app may use the camera, for the pairing scanner only; the helper never.
        camera = "com.apple.security.device.camera"
        app, _ = policy.validate_profile(profile(), TEAM, policy.APP_ID, NOW)
        helper, _ = policy.validate_profile(profile(policy.HELPER_ID), TEAM, policy.HELPER_ID, NOW)
        mobile, _ = policy.validate_profile(profile(policy.MOBILE_ID), TEAM, policy.MOBILE_ID, NOW)
        self.assertIs(app.get(camera), True)
        self.assertNotIn(camera, helper)
        self.assertNotIn(camera, mobile)
        policy.validate_entitlements(dict(app), app)
        for expected in (helper, {}):
            with self.subTest(expected=sorted(expected)), self.assertRaisesRegex(policy.ReleaseError, "intended policy"):
                policy.validate_entitlements({**expected, camera: True}, expected)
        # A signed Mac app without it could not open the scanner, so that is refused too.
        with self.assertRaisesRegex(policy.ReleaseError, "intended policy"):
            policy.validate_entitlements({key: value for key, value in app.items() if key != camera}, app)

    def test_a_profile_is_excused_only_the_entitlement_the_signature_grants(self):
        # The camera key is granted by the signature; any other expected key must be in the profile.
        self.assertEqual(policy.SIGNATURE_GRANTED, {"com.apple.security.device.camera"})
        expected = policy.intended_entitlements(TEAM, policy.APP_ID, TEAM)
        groups = {**expected, "com.apple.security.application-groups": [f"{TEAM}.com.mehmetcanbudak.memoshi"]}
        with mock.patch.object(policy, "intended_entitlements", return_value=groups), \
                self.assertRaisesRegex(policy.ReleaseError, "required entitlement com.apple.security.application-groups"):
            policy.validate_profile(profile(), TEAM, policy.APP_ID, NOW)

    def test_a_release_app_with_the_python_runtime_must_carry_its_retained_licence_texts(self):
        # D126: bundling the retained texts with the Python runtime is a release requirement.
        table = {"packages": [{"package": "controlled", "retained": {"notice": {"path": "retained/NOTICE", "sha256": "unused"},
                                                                     "texts": [{"path": "retained/LICENSE_FONT", "sha256": "unused"}]},
                               "withoutLicenceText": [{"part": "font", "evidence": [{"path": "retained/outside/OFL.txt", "sha256": "unused"}]}]}]}
        with tempfile.TemporaryDirectory() as directory:
            root, app = Path(directory) / "repository", Path(directory) / "Memoshi.app"
            for relative, content in (("retained/LICENSE_FONT", b"font terms"), ("retained/outside/OFL.txt", b"OFL terms"),
                                      ("retained/NOTICE", b"provenance")):
                (root / relative).parent.mkdir(parents=True, exist_ok=True)
                (root / relative).write_bytes(content)
            (app / "Contents/Resources").mkdir(parents=True)
            self.assertEqual(policy.missing_runtime_licences(app, table, root), [])
            runtime = app / "Contents/Resources/MemoshiApp_PyodideSpike.bundle/Runtime"
            runtime.mkdir(parents=True)
            (runtime / "pyodide.asm.wasm").write_bytes(b"controlled runtime")
            self.assertEqual(policy.missing_runtime_licences(app, table, root), ["retained/LICENSE_FONT", "retained/outside/OFL.txt"])
            (runtime / "Licences/matplotlib").mkdir(parents=True)
            (runtime / "Licences/matplotlib/LICENSE_FONT").write_bytes(b"font terms")
            (runtime / "Licences/matplotlib/OFL.txt").write_bytes(b"OFL terms, edited")
            self.assertEqual(policy.missing_runtime_licences(app, table, root), ["retained/outside/OFL.txt"])
            (runtime / "Licences/matplotlib/OFL.txt").write_bytes(b"OFL terms")
            self.assertEqual(policy.missing_runtime_licences(app, table, root), [])
            # The runtime is recognised by its file, whatever its directory is called.
            renamed = Path(directory) / "Renamed.app/Contents/Resources/Python"
            renamed.mkdir(parents=True)
            (renamed / "pyodide.asm.wasm").write_bytes(b"controlled runtime")
            self.assertEqual(policy.missing_runtime_licences(renamed.parents[2], table, root),
                             ["retained/LICENSE_FONT", "retained/outside/OFL.txt"])
            (renamed / "LICENSE_FONT").write_bytes(b"font terms")
            (renamed / "notices").mkdir()
            (renamed / "notices/OFL.txt").write_bytes(b"OFL terms")
            self.assertEqual(policy.missing_runtime_licences(renamed.parents[2], table, root), [])

    def test_distribution_profiles_fail_before_expiry_and_on_wrong_identity(self):
        for change in ({"ExpirationDate": NOW + dt.timedelta(days=365)}, {"TeamIdentifier": ["Z9Y8X7W6V5"]},
                       {"ProvisionsAllDevices": False}, {"ProvisionedDevices": ["device"]}):
            data = profile()
            data.update(change)
            with self.subTest(change=change), self.assertRaises(policy.ReleaseError):
                policy.validate_profile(data, TEAM, policy.APP_ID, NOW)
        with self.assertRaisesRegex(policy.ReleaseError, "certificate"):
            policy.validate_profile(profile(), TEAM, policy.APP_ID, NOW, b"another-certificate")

    def test_wildcard_appid_and_helper_keychain_profiles_are_refused(self):
        data = profile()
        data["Entitlements"]["com.apple.application-identifier"] = TEAM + ".*"
        with self.assertRaisesRegex(policy.ReleaseError, "exact App ID"):
            policy.validate_profile(data, TEAM, policy.APP_ID, NOW)
        # Apple Developer Portal unconditionally emits [TEAM + ".*"] on Developer ID profiles;
        # the signed helper binary itself still omits keychain-access-groups.
        data = profile(policy.HELPER_ID)
        data["Entitlements"]["keychain-access-groups"] = [TEAM + ".*"]
        helper_expected, _ = policy.validate_profile(data, TEAM, policy.HELPER_ID, NOW)
        self.assertNotIn("keychain-access-groups", helper_expected)
        # Explicit secret/device groups on the helper profile are still refused.
        data["Entitlements"]["keychain-access-groups"] = [f"{TEAM}.com.mehmetcanbudak.memoshi.secrets"]
        with self.assertRaisesRegex(policy.ReleaseError, "helper profile"):
            policy.validate_profile(data, TEAM, policy.HELPER_ID, NOW)
        # Real Apple profiles emit scalar "*" for com.apple.developer.icloud-services.
        for identifier in (policy.APP_ID, policy.HELPER_ID, policy.MOBILE_ID):
            real_shape = profile(identifier)
            real_shape["Entitlements"]["com.apple.developer.icloud-services"] = "*"
            policy.validate_profile(real_shape, TEAM, identifier, NOW)

    def test_production_cloudkit_and_push_are_required(self):
        for key in ("com.apple.developer.icloud-container-environment", "com.apple.developer.aps-environment"):
            data = profile()
            data["Entitlements"][key] = "development"
            with self.subTest(key=key), self.assertRaisesRegex(policy.ReleaseError, "required entitlement"):
                policy.validate_profile(data, TEAM, policy.APP_ID, NOW)

    def test_entitlement_exceptions_cannot_be_smuggled_into_other_code(self):
        for key in policy.FORBIDDEN:
            with self.subTest(key=key), self.assertRaisesRegex(policy.ReleaseError, "forbidden"):
                policy.validate_entitlements({key: True}, {})
        with self.assertRaisesRegex(policy.ReleaseError, "intended policy"):
            policy.validate_entitlements({"com.apple.security.app-sandbox": True}, {})
        with self.assertRaisesRegex(policy.ReleaseError, "intended policy"):
            policy.validate_entitlements({"com.apple.developer.kernel.increased-memory-limit": 1},
                                         {"com.apple.developer.kernel.increased-memory-limit": True})

    def test_testflight_profile_requires_beta_and_physical_distribution(self):
        data = profile(policy.MOBILE_ID)
        policy.validate_profile(data, TEAM, policy.MOBILE_ID, NOW)
        data["ProvisionedDevices"] = ["physical-device"]
        with self.assertRaisesRegex(policy.ReleaseError, "App Store distribution"):
            policy.validate_profile(data, TEAM, policy.MOBILE_ID, NOW)
        data = profile(policy.MOBILE_ID)
        data["Entitlements"]["beta-reports-active"] = False
        with self.assertRaisesRegex(policy.ReleaseError, "beta reporting"):
            policy.validate_profile(data, TEAM, policy.MOBILE_ID, NOW)

    def test_app_profiles_need_explicit_device_identity_authority_without_granting_it_to_helper(self):
        for identifier in (policy.APP_ID, policy.MOBILE_ID):
            data = profile(identifier)
            data["Entitlements"]["keychain-access-groups"] = [
                f"{TEAM}.com.mehmetcanbudak.memoshi.secrets"]
            with self.subTest(identifier=identifier), self.assertRaisesRegex(policy.ReleaseError, "required entitlement"):
                policy.validate_profile(data, TEAM, identifier, NOW)
        helper = profile(policy.HELPER_ID)
        helper["Entitlements"]["keychain-access-groups"] = [
            f"{TEAM}.com.mehmetcanbudak.memoshi.devices"]
        with self.assertRaisesRegex(policy.ReleaseError, "helper profile"):
            policy.validate_profile(helper, TEAM, policy.HELPER_ID, NOW)

    def test_bundle_identity_group_rejects_missing_unexpanded_and_wrong_prefixes(self):
        valid = {"MemoshiDeviceIdentityAccessGroup": f"{TEAM}.com.mehmetcanbudak.memoshi.devices"}
        policy.validate_device_access_group(valid, TEAM)
        for group in (None, "", "$(DEVELOPMENT_TEAM).com.mehmetcanbudak.memoshi.devices",
                      "Z9Y8X7W6V5.com.mehmetcanbudak.memoshi.devices",
                      f"{TEAM}.com.mehmetcanbudak.memoshi.secrets"):
            with self.subTest(group=group), self.assertRaises(policy.ReleaseError):
                policy.validate_device_access_group({"MemoshiDeviceIdentityAccessGroup": group}, TEAM)

    def test_size_growth_boundary_is_strictly_greater_than_ten_percent(self):
        baseline = {"schemaVersion": 1, "metric": "logical-file-bytes-plus-symlink-target-bytes",
                    "qualification": "Developer-ID-G2-notarized-stapled", "appTreeSHA256": "a" * 64,
                    "dmgSHA256": "b" * 64, "sizes": {"app": 100, "memoshid": 100, "installed_total": 200, "dmg": 100}}
        measured = copy.deepcopy(baseline)
        measured["sizes"]["memoshid"] = 110
        policy.check_sizes(baseline, measured)
        measured["sizes"]["memoshid"] = 111
        with self.assertRaisesRegex(policy.ReleaseError, "memoshid.*more than 10%"):
            policy.check_sizes(baseline, measured)
        measured["sizes"]["memoshid"] = 100
        measured["sizes"]["component:Contents/Helpers/new"] = 1
        with self.assertRaisesRegex(policy.ReleaseError, "inventory changed"):
            policy.check_sizes(baseline, measured)

    def test_measurements_partition_actual_file_bytes_without_double_counting(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "Memoshi.app"
            files = {"Contents/MacOS/Memoshi": b"a" * 100,
                     policy.HELPER + "/Contents/MacOS/memoshid": b"h" * 50,
                     "Contents/Helpers/tool": b"t" * 7,
                     "Contents/Frameworks/Sparkle.framework/Versions/A/Sparkle": b"s" * 9,
                     "Contents/PlugIns/Widget.appex/Contents/MacOS/Widget": b"w" * 11}
            for relative, content in files.items():
                path = app / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
            (app / "Contents/Resources").mkdir()
            (app / "Contents/Resources/alias").symlink_to("../MacOS/Memoshi")
            dmg = root / "Memoshi.dmg"
            dmg.write_bytes(b"d" * 70)
            result = policy.measure_sizes(app, dmg)
            self.assertEqual(result["sizes"]["memoshid"], 50)
            self.assertEqual(result["sizes"]["Sparkle"], 9)
            self.assertEqual(result["sizes"]["installed_total"], 177 + len(b"../MacOS/Memoshi"))
            self.assertEqual(result["sizes"]["dmg"], 70)
            before = result["appTreeSHA256"]
            (app / "Contents/MacOS/Memoshi").write_bytes(b"b" * 100)
            self.assertNotEqual(policy.measure_sizes(app, dmg)["appTreeSHA256"], before)
            (app / "Contents/Resources/escaped").symlink_to(dmg)
            with self.assertRaisesRegex(policy.ReleaseError, "escaped or broken symlink"):
                policy.measure_sizes(app, dmg)

    def test_testflight_uses_real_expiry_and_thirty_day_refresh(self):
        self.assertFalse(policy.testflight_status(snapshot(), "12345", NOW)["refreshDue"])
        result = policy.testflight_status(snapshot(age=30, expires=60), "12345", NOW)
        self.assertTrue(result["refreshDue"])
        self.assertEqual(result["nextBuildNumber"], "8")
        self.assertTrue(policy.testflight_status(snapshot(age=1, expires=30), "12345", NOW)["nearExpiry"])
        with self.assertRaisesRegex(policy.ReleaseError, "no unexpired"):
            policy.testflight_status(snapshot(expires=0), "12345", NOW)

    def test_processing_or_external_build_cannot_mask_missing_usable_internal_build(self):
        for change in ({"processingState": "PROCESSING"}, {"expired": True}, {"buildAudienceType": "APP_STORE_ELIGIBLE"}):
            data = snapshot()
            data["data"][0]["attributes"].update(change)
            with self.subTest(change=change), self.assertRaisesRegex(policy.ReleaseError, "no unexpired"):
                policy.testflight_status(data, "12345", NOW)
        with self.assertRaisesRegex(policy.ReleaseError, "no unexpired"):
            policy.testflight_status(snapshot(state="READY_FOR_BETA_TESTING"), "12345", NOW)

    def test_pending_new_upload_does_not_hide_older_expiring_available_build(self):
        data = snapshot(age=80, expires=10)
        pending = copy.deepcopy(data["data"][0])
        pending["id"] = "new-upload"
        pending["attributes"].update({"version": "99", "processingState": "PROCESSING", "uploadedDate": policy.iso(NOW)})
        data["data"].append(pending)
        result = policy.testflight_status(data, "12345", NOW)
        self.assertEqual(result["buildNumber"], "7")
        self.assertEqual(result["nextBuildNumber"], "100")
        self.assertTrue(result["nearExpiry"])

    def test_upload_confirmation_never_accepts_an_older_usable_build(self):
        # Build 7 is usable and recent; the upload under confirmation is build 99.
        with self.assertRaisesRegex(policy.BuildPending, "still processing"):
            policy.testflight_status(snapshot(), "12345", NOW, expect="99")
        for processing, beta in (("PROCESSING", "PROCESSING"), ("VALID", "READY_FOR_BETA_TESTING")):
            with self.subTest(processing=processing, beta=beta), self.assertRaisesRegex(policy.BuildPending, "still processing"):
                policy.testflight_status(with_upload(snapshot(), processing, beta), "12345", NOW, expect="99")
        result = policy.testflight_status(with_upload(snapshot(), "VALID", "IN_BETA_TESTING"), "12345", NOW, expect="99")
        self.assertEqual((result["buildID"], result["buildNumber"], result["nextBuildNumber"]), ("new-upload", "99", "100"))
        for processing in ("FAILED", "INVALID"):
            with self.subTest(processing=processing), self.assertRaisesRegex(policy.ReleaseError, "failed App Store Connect processing") as failure:
                policy.testflight_status(with_upload(snapshot(), processing), "12345", NOW, expect="99")
            self.assertNotIsInstance(failure.exception, policy.BuildPending)

    def test_first_upload_and_thirty_day_refresh_are_confirmed_on_the_new_build(self):
        first = snapshot()
        first["data"] = []
        with self.assertRaisesRegex(policy.BuildPending, "still processing"):
            policy.testflight_status(first, "12345", NOW, expect="99")
        refresh = with_upload(snapshot(age=30, expires=60), "VALID", "IN_BETA_TESTING")
        self.assertTrue(policy.testflight_status(refresh, "12345", NOW)["buildNumber"] == "99")
        result = policy.testflight_status(refresh, "12345", NOW, expect="99")
        self.assertEqual((result["buildNumber"], result["refreshDue"], result["nearExpiry"]), ("99", False, False))
        # While the refresh upload is processing, the 30-day-old build must not decide the outcome.
        with self.assertRaisesRegex(policy.BuildPending, "still processing"):
            policy.testflight_status(with_upload(snapshot(age=30, expires=60)), "12345", NOW, expect="99")

    def test_expiry_checks_refuse_partial_stale_and_wrong_app_snapshots(self):
        for change in ({"complete": False}, {"bundleID": "another.bundle"}, {"appID": "other"},
                       {"fetchedAt": policy.iso(NOW - dt.timedelta(hours=25))}):
            data = snapshot()
            data.update(change)
            with self.subTest(change=change), self.assertRaises(policy.ReleaseError):
                policy.testflight_status(data, "12345", NOW)
        data = snapshot()
        data["included"] = []
        with self.assertRaisesRegex(policy.ReleaseError, "platform cannot be verified"):
            policy.testflight_status(data, "12345", NOW)

    def test_an_upload_that_needs_action_is_refused_at_once_naming_its_state(self):
        # App Store Connect's InternalBetaState values that waiting does not turn into IN_BETA_TESTING.
        for state in ("MISSING_EXPORT_COMPLIANCE", "PROCESSING_EXCEPTION", "IN_EXPORT_COMPLIANCE_REVIEW", "EXPIRED"):
            with self.subTest(state=state), self.assertRaisesRegex(policy.ReleaseError, f"internalBuildState {state}") as failure:
                policy.testflight_status(with_upload(snapshot(), "VALID", state), "12345", NOW, expect="99")
            self.assertNotIsInstance(failure.exception, policy.BuildPending)
        # A build that may still become available names the states it was seen in.
        with self.assertRaisesRegex(policy.BuildPending, "processingState VALID, internalBuildState READY_FOR_BETA_TESTING"):
            policy.testflight_status(with_upload(snapshot(), "VALID", "READY_FOR_BETA_TESTING"), "12345", NOW, expect="99")

    def test_a_null_relationship_or_attribute_is_refused_not_a_traceback(self):
        def changed(change, expect=None):
            data = with_upload(snapshot(), "VALID", "IN_BETA_TESTING")
            change(data)
            return policy.testflight_status(data, "12345", NOW, expect=expect)

        cases = (
            (lambda data: data["data"][1]["relationships"]["preReleaseVersion"].update(data=None), "platform cannot be verified"),
            (lambda data: data["data"][1]["relationships"].update(preReleaseVersion=None), "platform cannot be verified"),
            (lambda data: data["data"][1]["relationships"]["app"].update(data=None), "another App Store app"),
            (lambda data: data["data"][1].update(relationships=None), "platform cannot be verified"),
            (lambda data: data["data"][1].update(attributes=None), "invalid App Store build number"),
            (lambda data: data["included"][0].update(attributes=None), "no iOS TestFlight builds exist"),
        )
        for change, message in cases:
            with self.subTest(message=message), self.assertRaisesRegex(policy.ReleaseError, message):
                changed(change)
        # A beta detail App Store Connect has not linked yet leaves the upload pending.
        with self.assertRaisesRegex(policy.BuildPending, "still processing"):
            changed(lambda data: data["data"][1]["relationships"]["buildBetaDetail"].update(data=None), expect="99")

    def test_runtime_licences_of_an_app_that_does_not_exist_are_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(policy.ReleaseError, "not an existing app directory"):
                policy.missing_runtime_licences(Path(directory) / "Missing.app", {"packages": []}, ROOT)

    def test_jwt_signature_conversion_and_integer_boundaries(self):
        der = b"\x30\x06\x02\x01\x01\x02\x01\x02"
        self.assertEqual(policy.ecdsa_jose(der), bytes(31) + b"\x01" + bytes(31) + b"\x02")
        for invalid in (der + b"x", b"\x30\x06\x02\x01\x81\x02\x01\x02", b"invalid"):
            with self.subTest(invalid=invalid), self.assertRaises(policy.ReleaseError):
                policy.ecdsa_jose(invalid)
        self.assertGreater(policy.build_number("8"), policy.build_number("7.99.99"))
        for invalid in ("0", "-1", "v1", "1.2.3.4", "1\n"):
            with self.subTest(invalid=invalid), self.assertRaises(policy.ReleaseError):
                policy.build_number(invalid)


class ReleaseCommandTests(unittest.TestCase):
    """release.py command paths, driven through the real argument parser; no gate is lowered."""

    def test_empty_baseline_is_refused_before_any_subprocess_or_upload(self):
        # An unset MEMOSHI_SIZE_BASELINE_PATH reaches release.py as `--baseline ""`.
        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory) / "key.p8"
            key.write_bytes(b"controlled-test-key")
            key.chmod(0o600)
            arguments = ["release.py", "package", "--app", directory, "--team-id", TEAM, "--identity", "A" * 40,
                         "--api-key", str(key), "--key-id", "ABCDEFGHIJ",
                         "--issuer-id", "00000000-0000-0000-0000-000000000000",
                         "--output", str(Path(directory) / "distribution"), "--baseline", ""]
            started = AssertionError("a subprocess started although --baseline named no reviewed budget file")
            with mock.patch.object(sys, "argv", arguments), \
                    mock.patch.object(release, "reject_untrusted_ci"), \
                    mock.patch.object(release, "require_release_ready"), \
                    mock.patch.object(release, "run", side_effect=started), \
                    self.assertRaisesRegex(policy.ReleaseError, "--baseline needs a reviewed size-baseline file"):
                release.main()
            self.assertFalse((Path(directory) / "distribution").exists())

    def confirm(self, states, timeout_minutes):
        """Runs confirm-testflight-upload with the real fetch and a real temporary signing key.

        The clock and App Store Connect's answers are controlled; no request leaves the process.
        Each state is one poll's build listing: None (upload not listed), the upload's
        (processingState, internalBuildState), or an exception the request raises.
        """
        if not Path("/usr/bin/openssl").is_file():
            self.skipTest("requires the installed openssl; no downloads")
        now = dt.datetime.now(policy.UTC)
        clock = [0.0]
        self.sleeps, self.polls = [], 0
        case = self

        class Service:
            def open(self, request, timeout):
                case.assertTrue(request.get_header("Authorization").startswith("Bearer "))
                if "/v1/apps/" in request.full_url:
                    return io.BytesIO(json.dumps({"data": {"attributes": {"bundleId": policy.MOBILE_ID}}}).encode())
                state = states[min(case.polls, len(states) - 1)]
                case.polls += 1
                if isinstance(state, Exception):
                    raise state
                data = snapshot(age=30, expires=60, now=now)
                if state is not None:
                    with_upload(data, *state, now=now)
                return io.BytesIO(json.dumps({"data": data["data"], "included": data["included"], "links": {}}).encode())

        def sleep(seconds):
            self.sleeps.append(seconds)
            clock[0] += seconds

        with tempfile.TemporaryDirectory() as directory:
            key, output = Path(directory) / "temporary-test-key.p8", Path(directory) / "processing"
            subprocess.run(["/usr/bin/openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key)], check=True, capture_output=True)
            key.chmod(0o600)
            arguments = ["release.py", "confirm-testflight-upload", "--api-key", str(key), "--key-id", "ABCDEFGHIJ",
                         "--issuer-id", "00000000-0000-0000-0000-000000000000", "--app-id", "12345",
                         "--build-number", "99", "--timeout-minutes", str(timeout_minutes), "--output", str(output)]
            with mock.patch.object(sys, "argv", arguments), \
                    mock.patch.object(release, "reject_untrusted_ci"), \
                    mock.patch.object(release.urllib.request, "build_opener", return_value=Service()), \
                    mock.patch.object(release.time, "sleep", side_effect=sleep), \
                    mock.patch.object(release.time, "monotonic", side_effect=lambda: clock[0]), \
                    mock.patch("builtins.print"):
                try:
                    return release.main()
                finally:
                    release.LOG_DIRECTORY = None
                    # The API token's signature is a credential for ten minutes: never on disk.
                    stored = sorted(path.name for path in output.rglob("*") if path.is_file())
                    self.assertEqual([name for name in stored if not re.fullmatch(r"builds-[0-9]{3}\.json", name)], [])

    def test_upload_confirmation_waits_for_the_uploaded_build(self):
        # Not listed yet, then processing, then available: the old 30-day build never decides.
        status = self.confirm([None, ("PROCESSING", "PROCESSING"), ("VALID", "IN_BETA_TESTING")], 45)
        self.assertEqual((status, self.sleeps, self.polls), (0, [60, 60], 3))

    def test_upload_confirmation_has_a_bounded_deadline_and_stops_on_failed_processing(self):
        with self.assertRaisesRegex(policy.ReleaseError, "still processing.*not confirmed within 2 minutes"):
            self.confirm([("PROCESSING", "PROCESSING")], 2)
        # A failed build is terminal: with a second snapshot that would pass, it is still refused.
        with self.assertRaisesRegex(policy.ReleaseError, "failed App Store Connect processing"):
            self.confirm([("FAILED", "PROCESSING"), ("VALID", "IN_BETA_TESTING")], 45)
        self.assertEqual((self.sleeps, self.polls), ([], 1))
        # A state that needs someone's action is terminal as well, and the refusal names it.
        with self.assertRaisesRegex(policy.ReleaseError, "internalBuildState MISSING_EXPORT_COMPLIANCE") as failure:
            self.confirm([("VALID", "MISSING_EXPORT_COMPLIANCE"), ("VALID", "IN_BETA_TESTING")], 45)
        self.assertNotIsInstance(failure.exception, policy.BuildPending)
        self.assertEqual((self.sleeps, self.polls), ([], 1))
        for invalid in ("0", "-5"):
            with self.subTest(timeout=invalid), self.assertRaisesRegex(policy.ReleaseError, "--timeout-minutes"):
                self.confirm([("VALID", "IN_BETA_TESTING")], invalid)

    def test_upload_confirmation_rides_out_failed_requests_but_not_a_refusal(self):
        url = "https://api.appstoreconnect.apple.com/v1/builds"
        unavailable = urllib.error.HTTPError(url, 503, "Service Unavailable", {}, None)
        # The upload has succeeded and its build number is spent: a server error, an unreachable
        # network or a timed-out read is waited out inside the same bounded deadline.
        status = self.confirm([unavailable, urllib.error.URLError("unreachable"), socket.timeout("timed out"),
                               ("VALID", "IN_BETA_TESTING")], 45)
        self.assertEqual((status, self.sleeps, self.polls), (0, [60, 60, 60], 4))
        with self.assertRaisesRegex(policy.ReleaseError, "HTTP 503.*not confirmed within 2 minutes"):
            self.confirm([unavailable], 2)
        self.assertEqual(self.polls, 3)
        # A refusal is definite: the key's role or app access will not change by waiting.
        for code in (401, 403, 404, 429):
            with self.subTest(code=code), self.assertRaisesRegex(policy.ReleaseError, f"HTTP {code}"):
                self.confirm([urllib.error.HTTPError(url, code, "refused", {}, None), ("VALID", "IN_BETA_TESTING")], 45)
            self.assertEqual((self.sleeps, self.polls), ([], 1))

    def test_relative_profile_path_names_one_file_for_the_check_and_the_decoder(self):
        # run() executes in the repository root, so a caller-relative path must be made absolute.
        decoded = []

        def decode(arguments, **_):
            decoded.append(arguments[-1])
            return subprocess.CompletedProcess(arguments, 0, plistlib.dumps({"UUID": "controlled"}), b"")

        with tempfile.TemporaryDirectory() as directory:
            profile_path = Path(directory).resolve() / "app.provisionprofile"
            profile_path.write_bytes(b"controlled-test-profile")
            previous = os.getcwd()
            os.chdir(directory)
            try:
                with mock.patch.object(release, "run", side_effect=decode):
                    self.assertEqual(release.profile_data("app.provisionprofile"), {"UUID": "controlled"})
            finally:
                os.chdir(previous)
            self.assertEqual([Path(item) for item in decoded], [profile_path])

    def fixture_app(self, directory, name, info, executable, content):
        app = Path(directory) / name
        binary = app / executable
        binary.parent.mkdir(parents=True)
        binary.write_bytes(content)
        binary.chmod(0o755)
        with (app / ("Contents/Info.plist" if (app / "Contents").is_dir() else "Info.plist")).open("wb") as stream:
            plistlib.dump({"MemoshiDeviceIdentityAccessGroup": f"{TEAM}.com.mehmetcanbudak.memoshi.devices", **info}, stream)
        return app

    def test_release_verification_scans_the_release_app_for_restricted_sign_in_clients(self):
        # A GitHub Copilot subscription client ID, one of check-signin-flows.sh's restricted IDs.
        restricted = b"controlled-code Iv1.b507a08c87ecfe98 controlled-code"
        for content, mac_stage, mobile_stage in (
                (restricted, "^sign-in-flows failed", "^mobile-sign-in-flows failed"),
                (b"controlled-code", "^bundle-layout-and-notices failed", "^mobile-release-composition failed")):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as directory:
                mac = self.fixture_app(directory, "Memoshi.app", {"CFBundleIdentifier": policy.APP_ID},
                                       "Contents/MacOS/Memoshi", content)
                helper = mac / policy.HELPER / "Contents"
                helper.mkdir(parents=True)
                with (helper / "Info.plist").open("wb") as stream:
                    plistlib.dump({"CFBundleIdentifier": policy.HELPER_ID}, stream)
                with self.assertRaisesRegex(policy.ReleaseError, mac_stage):
                    release.verify_mac(mac, TEAM)
                mobile = self.fixture_app(directory, "MemoshiMobile.app", {
                    "CFBundleIdentifier": policy.MOBILE_ID, "DTPlatformName": "iphoneos", "UIDeviceFamily": [1, 2],
                }, "MemoshiMobile", content)
                with self.assertRaisesRegex(policy.ReleaseError, mobile_stage):
                    release.verify_mobile(mobile, TEAM)

    def test_release_verification_refuses_a_python_runtime_without_its_licence_texts(self):
        with tempfile.TemporaryDirectory() as directory:
            mac = self.fixture_app(directory, "Memoshi.app", {"CFBundleIdentifier": policy.APP_ID}, "Contents/MacOS/Memoshi", b"controlled-code")
            helper = mac / policy.HELPER / "Contents"
            helper.mkdir(parents=True)
            with (helper / "Info.plist").open("wb") as stream:
                plistlib.dump({"CFBundleIdentifier": policy.HELPER_ID}, stream)
            mobile = self.fixture_app(directory, "MemoshiMobile.app", {
                "CFBundleIdentifier": policy.MOBILE_ID, "DTPlatformName": "iphoneos", "UIDeviceFamily": [1, 2],
            }, "MemoshiMobile", b"controlled-code")
            for app, verify in ((mac / "Contents/Resources", lambda: release.verify_mac(mac, TEAM)), (mobile, lambda: release.verify_mobile(mobile, TEAM))):
                runtime = app / "MemoshiApp_PyodideSpike.bundle/Runtime"
                runtime.mkdir(parents=True)
                (runtime / "pyodide.asm.wasm").write_bytes(b"controlled runtime")
                with self.assertRaisesRegex(policy.ReleaseError, "Python runtime without its retained licence texts.*LICENSE_BAKOMA"):
                    verify()

    def test_only_the_explicit_flag_selects_initial_baseline_mode(self):
        self.assertIsNone(release.size_baseline(argparse.Namespace(baseline=None, initial_size_baseline=True)))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "baseline.json"
            path.write_text('{"schemaVersion": 1}')
            self.assertEqual(release.size_baseline(argparse.Namespace(baseline=str(path), initial_size_baseline=False)),
                             {"schemaVersion": 1})

    def mac_and_mobile(self, directory):
        mac = self.fixture_app(directory, "Memoshi.app", {"CFBundleIdentifier": policy.APP_ID}, "Contents/MacOS/Memoshi", b"controlled-code")
        helper = mac / policy.HELPER / "Contents"
        helper.mkdir(parents=True)
        with (helper / "Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": policy.HELPER_ID}, stream)
        mobile = self.fixture_app(directory, "MemoshiMobile.app", {
            "CFBundleIdentifier": policy.MOBILE_ID, "DTPlatformName": "iphoneos", "UIDeviceFamily": [1, 2],
        }, "MemoshiMobile", b"controlled-code")
        return mac.resolve(), mobile.resolve()

    def test_every_release_bundle_is_scanned_for_debug_only_composition(self):
        bundle = str(ROOT / "scripts/check-bundle.sh")
        calls = []

        class Stop(Exception):
            pass

        def run(arguments, **options):
            calls.append((options.get("label"), [str(item) for item in arguments]))
            if options.get("label") in ("release-composition", "mobile-release-composition"):
                raise Stop
            return subprocess.CompletedProcess(arguments, 0, b"", b"")

        with tempfile.TemporaryDirectory() as directory:
            mac, mobile = self.mac_and_mobile(directory)
            with mock.patch.object(release, "run", side_effect=run):
                with self.assertRaises(Stop):
                    release.verify_mac(mac, TEAM)
                with self.assertRaises(Stop):
                    release.verify_mobile(mobile, TEAM)
            self.assertEqual(calls, [
                ("sign-in-flows", [str(ROOT / "scripts/check-signin-flows.sh"), str(mac)]),
                ("bundle-layout-and-notices", [bundle, str(mac)]),
                ("release-composition", [bundle, "--release-composition", str(mac)]),
                ("mobile-sign-in-flows", [str(ROOT / "scripts/check-signin-flows.sh"), str(mobile)]),
                ("mobile-release-composition", [bundle, "--release-composition", str(mobile)]),
            ])

    def test_an_unsigned_mac_archive_is_scanned_for_debug_only_composition(self):
        calls = []

        def run(arguments, **options):
            arguments = [str(item) for item in arguments]
            calls.append((options.get("label"), arguments))
            if options.get("label") == "Release-archive":
                info = Path(arguments[arguments.index("-archivePath") + 1]) / "Products/Applications/Memoshi.app/Contents/Info.plist"
                info.parent.mkdir(parents=True)
                with info.open("wb") as stream:
                    plistlib.dump({"CFBundleVersion": "7", "CFBundleShortVersionString": "1.2.3",
                                   "MemoshiDeviceIdentityAccessGroup": f"{TEAM}.com.mehmetcanbudak.memoshi.devices"}, stream)
            return subprocess.CompletedProcess(arguments, 0, b"", b"")

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory).resolve() / "archive"
            args = argparse.Namespace(platform="macos", version="1.2.3", source_tag="v1.2.3", build_number="7",
                                      output=str(output), team_id=TEAM, identity=None, profile=None, builds_json=None, app_id=None)
            with mock.patch.object(release, "reject_untrusted_ci"), mock.patch.object(release, "require_release_ready"), \
                    mock.patch.object(release, "release_source", return_value="a" * 40), \
                    mock.patch.object(release, "run", side_effect=run), mock.patch("builtins.print"):
                try:
                    release.archive(args)
                finally:
                    release.LOG_DIRECTORY = None
            app = str(output / "Memoshi.xcarchive/Products/Applications/Memoshi.app")
            bundle = str(ROOT / "scripts/check-bundle.sh")
            self.assertEqual(calls[1:], [("archived-bundle-layout", [bundle, app]),
                                         ("archived-release-composition", [bundle, "--release-composition", app])])
            self.assertEqual(json.loads((output / "archive.json").read_text())["sourceCommit"], "a" * 40)

    def test_release_source_checks_the_regenerated_outputs_and_the_tree_after_building(self):
        for after, refused in ((b"", False), (b" M Packages/MemoshiMLS/Generated/include/module.modulemap\n", True)):
            statuses, labels = [b"", after], []

            def run(arguments, **options):
                labels.append(options.get("label"))
                if options.get("label") in ("release-tag", "release-HEAD"):
                    return subprocess.CompletedProcess(arguments, 0, b"a" * 40 + b"\n", b"")
                if options.get("label").startswith("release-clean-checkout"):
                    return subprocess.CompletedProcess(arguments, 0, statuses.pop(0), b"")
                return subprocess.CompletedProcess(arguments, 0, b"", b"")

            with self.subTest(after=after), mock.patch.object(release, "run", side_effect=run):
                if refused:
                    with self.assertRaisesRegex(policy.ReleaseError, "building the release changed the checkout"):
                        release.release_source("v1.2.3", "1.2.3")
                else:
                    self.assertEqual(release.release_source("v1.2.3", "1.2.3"), "a" * 40)
                self.assertEqual(labels, ["release-tag", "release-HEAD", "release-clean-checkout",
                                          "SDK-and-release-disk-prerequisites", "qualified-toolchain", "pinned-native-MLS",
                                          "checked-in-native-MLS-outputs", "XcodeGen", "release-clean-checkout-after-build"])

    def test_fresh_output_creates_every_new_directory_owner_only(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory).resolve()
            try:
                output = release.fresh_output(base / "new/parent/release")
            finally:
                release.LOG_DIRECTORY = None
            for path in (base / "new", base / "new/parent", output, output / "logs"):
                self.assertEqual(path.stat().st_mode & 0o777, 0o700, path)

    @staticmethod
    def release_ready_root(directory, manifest):
        base = Path(directory).resolve()
        root, clone = base / "Memoshi", base / "Pi_Swift-slice-1"
        clone.mkdir()
        environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        git = ["git", "-c", "user.name=Memoshi tests", "-c", "user.email=tests@memoshi.invalid", "-c", "commit.gpgsign=false",
               "-c", "tag.gpgsign=false", "-c", "init.defaultBranch=main", "-C", str(clone)]
        for arguments in (["init", "--quiet"], ["commit", "--quiet", "--allow-empty", "-m", "slice-1"],
                          ["tag", "--annotate", "--message", "slice-1", "slice-1"]):
            subprocess.run(git + arguments, check=True, capture_output=True, env=environment)
        revision = subprocess.run(git + ["rev-parse", "HEAD"], check=True, capture_output=True, text=True, env=environment).stdout.strip()
        (root / "scripts/lib").mkdir(parents=True)
        (root / "scripts/lib/pi-swift-pin.sh").write_text(
            f"PI_SWIFT_TAG=slice-1\nPI_SWIFT_REVISION={revision}\nPI_SWIFT_CHECKOUT=../Pi_Swift-slice-1\n")
        (root / "scripts/release-gates.json").write_text(json.dumps({
            "schemaVersion": 1, "holds": {"releaseBlocked": False, "broaderQualificationBlocked": False},
            "sdk": {"consumerRevision": revision, "qualification": "accepted", "qualifyingTag": "slice-1",
                    "acceptedBy": "controlled test", "evidenceSHA256": "0" * 64}}))
        (root / "Packages/MemoshiCore").mkdir(parents=True)
        (root / "Packages/MemoshiCore/Package.swift").write_text(manifest)
        return root

    def test_release_readiness_builds_the_pinned_pi_swift_checkout_alone(self):
        pinned = '.package(path: "../../../Pi_Swift-slice-1"),\n'
        checkout = re.search(r"^PI_SWIFT_CHECKOUT=\.\./(\S+)$", (ROOT / "scripts/lib/pi-swift-pin.sh").read_text(), re.M)[1]
        committed = (ROOT / "Packages/MemoshiCore/Package.swift").read_text().replace(checkout, "Pi_Swift-slice-1")
        for manifest, refused in ((pinned, False), (committed, False),
                                  (pinned + '.package(url: "https://github.com/x/Pi_Swift.git", from: "1.0.0"),\n', True),
                                  (pinned + '.package(path: "../../../PiFork"),\n', True),
                                  ("// " + pinned + '.package(path: "../../../Elsewhere/Pi_Swift-slice-1"),\n', True)):
            with self.subTest(manifest=manifest[-70:]), tempfile.TemporaryDirectory() as directory:
                with mock.patch.object(release, "ROOT", self.release_ready_root(directory, manifest)):
                    if refused:
                        with self.assertRaisesRegex(policy.ReleaseError, "does not build the Pi_Swift checkout that the pin names, alone"):
                            release.require_release_ready()
                    else:
                        release.require_release_ready()
        # check-release-gates is the same check, through the command line.
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(release, "ROOT", self.release_ready_root(directory, pinned)), \
                mock.patch.object(sys, "argv", ["release.py", "check-release-gates"]), mock.patch("builtins.print") as printed:
            self.assertEqual(release.main(), 0)
        printed.assert_called_once_with("Explicit release and SDK acceptance gates passed")
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(release, "ROOT", self.release_ready_root(directory, pinned + '.package(path: "../../../PiFork"),\n')), \
                mock.patch.object(sys, "argv", ["release.py", "check-release-gates"]), \
                self.assertRaisesRegex(policy.ReleaseError, 'PiFork"\\) is neither the pinned Pi_Swift checkout'):
            release.main()


@unittest.skipUnless(sys.platform == "darwin" and Path("/usr/bin/clang").is_file(), "requires installed Apple compiler/codesign; no downloads")
class ControlledMachOTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="memoshi-release-tests-")
        cls.root = Path(cls.temporary.name)
        source = cls.root / "controlled.c"
        source.write_text("int main(void) { return 0; }\n")
        cls.binary = cls.root / "controlled"
        subprocess.run(["/usr/bin/clang", "-arch", "arm64", str(source), "-o", str(cls.binary)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_inventory_orders_actual_nested_code_inside_out(self):
        with tempfile.TemporaryDirectory(dir=self.root) as directory:
            physical_parent = Path(directory)
            alias = physical_parent / "input-alias"
            alias.symlink_to(physical_parent, target_is_directory=True)
            app = alias / "Memoshi.app"
            for bundle, name, identifier in ((app, "Memoshi", policy.APP_ID), (app / policy.HELPER, "memoshid", policy.HELPER_ID)):
                executable = bundle / "Contents/MacOS" / name
                executable.parent.mkdir(parents=True)
                shutil.copy2(self.binary, executable)
                with (bundle / "Contents/Info.plist").open("wb") as stream:
                    plistlib.dump({"CFBundleIdentifier": identifier, "CFBundleExecutable": name}, stream)
            tool = app / policy.HELPER / "Contents/Helpers/pi-env"
            tool.parent.mkdir()
            shutil.copy2(self.binary, tool)
            targets = release.code_targets(app)
            paths = [item[0].resolve() for item in targets]
            self.assertLess(paths.index(tool.resolve()), paths.index((app / policy.HELPER).resolve()))
            self.assertLess(paths.index((app / policy.HELPER).resolve()), paths.index(app.resolve()))
            self.assertTrue(policy.is_executable_mach_o(tool))
            bad = app / "Contents/Resources/hidden-code"
            bad.parent.mkdir()
            shutil.copy2(self.binary, bad)
            with self.assertRaisesRegex(policy.ReleaseError, "hidden under Resources"):
                release.code_targets(app)

    def test_real_adhoc_runtime_signature_never_passes_distribution_validation(self):
        with tempfile.TemporaryDirectory(dir=self.root) as directory:
            executable = Path(directory) / "controlled"
            shutil.copy2(self.binary, executable)
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--options", "runtime", "--identifier", policy.APP_ID, str(executable)], check=True, capture_output=True)
            with self.assertRaises(policy.ReleaseError):
                release.verify_signature(executable, policy.APP_ID, TEAM, {})

    def test_openssl_real_p256_signature_has_valid_jose_width(self):
        with tempfile.TemporaryDirectory(dir=self.root) as directory:
            key = Path(directory) / "temporary-test-key.pem"
            subprocess.run(["/usr/bin/openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key)], check=True, capture_output=True)
            key.chmod(0o600)
            signature = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-sign", str(key)], input=b"controlled-release-test", check=True, capture_output=True).stdout
            self.assertEqual(len(policy.ecdsa_jose(signature)), 64)


if __name__ == "__main__":
    unittest.main()
