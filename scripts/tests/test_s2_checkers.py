"""The offline S2 checkers and runner; run with python3 -m unittest discover -s scripts/tests -v.

Each checker runs for real, as a separate process, on a minimal synthetic S2 output directory
that passes every check, and then on one changed copy. Nothing is built or measured here.
"""

import base64
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
GIT = ["git", "-c", "user.name=Memoshi tests", "-c", "user.email=tests@memoshi.invalid",
       "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main"]

MAC, PHONE, IPAD = "device-mac", "device-phone", "device-ipad"
HELD = "held-conversation"
HELD_EPOCH = 5
GROUP_EPOCH = 55
# Wall-clock milliseconds: the authority's reply to the removal, as the journal records it.
REVOKED_AT = 1_700_000_000_000
# The counters a check compares with 0, by report section: an absent one must never read as 0.
MUST_BE_ZERO = [(section, name) for section in ("qualified", "stress") for name in (
    "pairing.unexpectedRefusal", "expiry.oldRunner.concurrentAccepted", "expiry.staleAccepted",
)] + [("once", name) for name in (
    "qr.afterWrongKey.refused", "qr.expired.accepted", "qr.replay.accepted", "qr.void.accepted", "qr.wrongKey.accepted",
    "revoke.relay.accepted", "revoke.claim.accepted", "revoke.link.accepted", "revoke.authority.accepted",
    "revoke.renew.accepted", "revoke.write.accepted", "revoke.write.afterRevocation",
)]


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=1, sort_keys=True) + "\n")


def write_lines(path, items):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(item, sort_keys=True) + "\n" for item in items))


def run_script(name, *arguments, optimize=False):
    command = [sys.executable] + (["-O"] if optimize else []) + [str(SCRIPTS / name)] + [str(item) for item in arguments]
    environment = {key: value for key, value in os.environ.items() if key != "PYTHONOPTIMIZE"}
    return subprocess.run(command, capture_output=True, text=True, env=environment)


class Clock:
    """Monotonic nanoseconds shared by the synthetic device logs."""

    def __init__(self):
        self.now = 1_000_000

    def __call__(self):
        self.now += 1_000
        return self.now


def node(clock, kind, **fields):
    return {"event": "node", "kind": kind, "at": clock(), **fields}


def audit_counters(label, commits, epochs, writers):
    values = {"commits": commits, "epochs": epochs, "writers": writers, "commitsWithoutEpoch": 0,
              "epochWentBackwards": 0, "twoWriterEpochs": 0, "requiredWriters": writers,
              "requiredEpochs": epochs, "replicaRejections": 0}
    return {f"audit.{label}.{field}": value for field, value in values.items()}


def phase_counters():
    return {"pairing.unexpectedRefusal": 0, "expiry.beforeFreeze.accepted": 20,
            "expiry.oldRunner.concurrentAccepted": 0, "expiry.oldRunner.concurrentRefused": 3,
            "expiry.successor.concurrentAccepted": 3, "expiry.staleRefused": 20, "expiry.staleAccepted": 0,
            "expiry.renewRefusedOnMac": 2}


def d123_output(out):
    """Writes an S2 output directory on which check_d123_v2.py passes every check."""
    clock = Clock()
    mac = [{"event": "ready", "deviceId": MAC}]
    phone = [{"event": "ready", "deviceId": PHONE}]
    ipad = [{"event": "ready", "deviceId": IPAD}]
    mac += [node(clock, "paired") for _ in range(53)]
    mac += [node(clock, "refused", detail=detail) for detail in ("alreadyUsed", "voided", "expired")]
    phone += [{"op": "pairProbe", "id": index, "ok": True, "paired": True} for index in range(50)]
    phone += [{"op": "pairProbe", "ok": True, "paired": paired, "refusal": refusal} for paired, refusal in (
        (False, "alreadyUsed"), (False, "voided"), (False, "wrongKey"), (True, None), (False, "expired"))]
    # Two-writer audits: one conversation per phase and label, told apart by their commit counts.
    counters, stress_counters = phase_counters(), phase_counters()
    for phase, target in (("qualified", counters), ("stress", stress_counters)):
        for label, commits in (("chat", 4), ("session", 5), ("expiry", 6)):
            commits += 3 if phase == "stress" else 0
            conversation = f"{phase}-{label}"
            if label == "session":
                mac += [node(clock, "committed", conversation=conversation, epoch=1) for _ in range(commits)]
                target.update(audit_counters(label, commits, 1, 1))
            else:
                first = commits // 2
                mac += [node(clock, "committed", conversation=conversation, epoch=1) for _ in range(first)]
                phone += [node(clock, "committed", conversation=conversation, epoch=2) for _ in range(commits - first)]
                target.update(audit_counters(label, commits, 2, 2))
            if label == "expiry":
                mac += [node(clock, "renewRefused", conversation=conversation) for _ in range(2)]
    # The revoked iPad held a lease, wrote and renewed before its revocation, and nothing after.
    ipad += [node(clock, "committed", conversation=HELD, epoch=HELD_EPOCH) for _ in range(3)]
    ipad.append(node(clock, "renewed", conversation=HELD, detail=f"expires_at={REVOKED_AT - 1_000} ttl_ms=5000"))
    mac.append(node(clock, "revoked", peer=IPAD))
    mac.append(node(clock, "refused", route="direct", detail="unknownPeer"))
    mac += [node(clock, "committed", conversation=HELD, epoch=HELD_EPOCH + 1) for _ in range(3)]
    ipad += [
        {"op": "rawRelayHello", "ok": True, "accepted": False},
        {"op": "rawClaim", "ok": True, "answered": False, "granted": False},
        {"op": "rawLink", "ok": True, "linked": False},
        {"op": "rawRenew", "ok": True, "renewed": False},
        {"op": "commitStream", "ok": True, "accepted": 3, "refused": 0, "refusedBy": {"fence": 0, "membership": 0},
         "failed": 0, "errors": []},
        {"op": "commitStream", "ok": True, "accepted": 0, "refused": 2, "refusedBy": {"fence": 0, "membership": 2},
         "failed": 0, "errors": []},
    ]
    # The member control claim on the revoked device's path: granted, then released.
    mac.append({"op": "rawClaimAndRelease", "ok": True, "answered": True, "granted": True, "released": True})
    # Write loops: refusals are fence or membership refusals only; any other failure is counted.
    mac.append({"op": "writeLoop", "ok": True, "accepted": 10, "refused": 2, "refusedBy": {"fence": 2, "membership": 0},
                "failed": 0, "errors": []})
    phone.append({"op": "writeLoop", "ok": True, "accepted": 12, "refused": 0, "refusedBy": {"fence": 0, "membership": 0},
                  "failed": 0, "errors": []})
    counters.update({"group.qualified.devices": 8, "group.stress.devices": 54, "group.once.devices": 54})
    # The scenarios that run once, after the stress phase, report in their own section.
    once_counters = audit_counters("revoked", 6, 2, 2)
    once_counters.update({
        "revoke.groupEpoch": GROUP_EPOCH,
        "qr.expired.refused": 1, "qr.expired.accepted": 0,
        "qr.replay.refused": 1, "qr.replay.accepted": 0, "qr.void.refused": 1, "qr.void.accepted": 0,
        "qr.wrongKey.refused": 1, "qr.wrongKey.accepted": 0, "qr.afterWrongKey.paired": 1, "qr.afterWrongKey.refused": 0,
        "revoke.relay.refused": 1, "revoke.relay.accepted": 0,
        "revoke.claim.refused": 1, "revoke.claim.accepted": 0, "revoke.claim.connectionClosed": 1,
        "revoke.link.refused": 1, "revoke.link.accepted": 0,
        "revoke.lease.held": 1, "revoke.renewals.beforeRevocation": 1, "revoke.lease.expiredAtRemoval": 1,
        "revoke.authority.refused": 1, "revoke.authority.accepted": 0, "revoke.control.rawClaimGranted": 1,
        "revoke.renew.refused": 1, "revoke.renew.accepted": 0, "revoke.renew.connectionClosed": 0,
        "revoke.write.accepted": 0, "revoke.write.refused": 2, "revoke.write.afterRevocation": 0,
        "revoke.write.refusedByFence": 0, "revoke.write.refusedByMembership": 2,
        "revoke.successor.accepted": 3,
    })
    write_lines(out / "logs/mac.stdout.jsonl", mac)
    write_lines(out / "logs/phone.stdout.jsonl", phone)
    write_lines(out / "logs/ipad.stdout.jsonl", ipad)
    write_lines(out / "logs/relay.stdout.jsonl", [{"op": "stats", "ok": True, "refusals": 1}, {
        "op": "revokedProbe", "ok": True, "isRevoked": True, "revokedRefusals": 2, "claimAnswered": False,
        "claimGranted": False, "renewAnswered": False, "renewed": False, "leaseUnchanged": True,
        "leaseEpoch": HELD_EPOCH + 1, "leaseRunner": None, "memberClaimGranted": True}, {"op": "stats", "ok": True, "refusals": 3}])
    # The main relay's journal: the roster grows from 2 to 54 members, then the iPad is removed.
    messages = []
    for size in range(2, 55):
        commit = base64.b64encode(json.dumps({"members": list(range(size))}).encode()).decode()
        messages.append((2, {"type": "group.commit", "payload": {"change": "add", "commit": commit}, "from": {"deviceId": MAC}}))
    commit = base64.b64encode(json.dumps({"members": list(range(53))}).encode()).decode()
    messages.append((2, {"type": "group.commit", "payload": {"change": "remove", "commit": commit}, "from": {"deviceId": MAC}}))
    messages.append((3, {"type": "group.commitResult", "payload": {"accepted": True, "epoch": GROUP_EPOCH},
                         "sentAt": REVOKED_AT, "to": {"deviceId": MAC}}))
    journal = b"".join(struct.pack(">BI", kind, len(body)) + body
                       for kind, body in [(kind, json.dumps(message).encode()) for kind, message in messages] + [(1, b"send")])
    (out / "main-relay-journal.bin").write_bytes(journal)
    summary = {
        "duplicateGrants": 0,
        "journal": {"closed": {"counts": {"entries": len(messages) + 1, "bytes": len(journal) - 5 * (len(messages) + 1)}}},
        "statistics": {"refusals": 4},
        "counters": {"groupCommitsApplied": 54, "groupCommitsDenied": 0, "revokedRefusals": 2},
        "grantLog": [
            {"runner": IPAD, "conversationID": HELD, "epoch": HELD_EPOCH, "grantedAt": REVOKED_AT - 10_000},
            {"runner": MAC, "conversationID": HELD, "epoch": HELD_EPOCH + 1, "grantedAt": REVOKED_AT + 1_000},
            {"runner": MAC, "conversationID": "control-conversation", "epoch": 1, "grantedAt": REVOKED_AT + 2_000},
        ],
    }
    write_json(out / "main-relay-summary.json", summary)
    relays = {"main": summary}
    # The load relays keep no grant log, so their summaries carry no grant or duplicate count.
    relays.update({f"load-{index}": {"journal": {"closed": {}}} for index in range(4)})
    report = {
        "passed": True, "failures": [], "quick": False, "realQRExpirySelected": True, "authorityLoadSelected": True,
        "counters": counters,
        "series": {"pairing.probe.total": {"n": 5}, "pairing.device.total": {"n": 2},
                   "expiry.takeOverAfterFreeze": {"n": 20}},
        "qualified": {"groupDevices": 8},
        "stress": {"groupDevices": 54, "counters": stress_counters,
                   "series": {"pairing.probe.total": {"n": 45}, "expiry.takeOverAfterFreeze": {"n": 20}}},
        "once": {"groupDevices": 54, "what": "the scenarios that run once, in the stress group",
                 "counters": once_counters, "series": {"revoke.successor.takeOver": {"n": 1}}},
        "relays": relays,
    }
    write_json(out / "s2-measurements.json", report)
    return report


class CheckD123Tests(unittest.TestCase):
    """check_d123_v2.py: a "must be 0" safety counter that is absent fails, never reads as 0."""

    def check(self, change=None, retained_main=False):
        """`retained_main`: the change is the main relay's own, so its retained summary carries it too."""
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "output"
            report = d123_output(out)
            if change is not None:
                change(report)
                write_json(out / "s2-measurements.json", report)
                if retained_main:
                    write_json(out / "main-relay-summary.json", report["relays"]["main"])
            result = Path(directory) / "result.json"
            process = run_script("check_d123_v2.py", out, 0, result)
            self.assertTrue(result.is_file(), process.stderr)
            return process, json.loads(result.read_text())

    def test_a_complete_output_passes_every_check(self):
        process, result = self.check()
        failed = [item for item in result["checks"] if not item["ok"]]
        self.assertEqual(failed, [])
        self.assertEqual((process.returncode, result["allChecksOk"]), (0, True), process.stdout)

    def test_every_counted_check_can_fail(self):
        # A check that is true whatever the run measured is not a pass; the value is a fact.
        _, result = self.check()
        self.assertEqual([item["check"] for item in result["checks"] if item["expected"] == "reported"], [])
        self.assertEqual(result["facts"]["revokeClaimConnectionClosed"]["value"], 1)

    def test_an_absent_must_be_zero_counter_fails(self):
        for section, name in MUST_BE_ZERO:
            def remove(report):
                del (report if section == "qualified" else report[section])["counters"][name]

            with self.subTest(section=section, counter=name):
                process, result = self.check(remove)
                self.assertEqual((process.returncode, result["allChecksOk"]), (1, False))
                failed = [item for item in result["checks"] if not item["ok"]]
                self.assertIn({"section": section, "counter": name},
                              [item["measured"] for item in failed if item["check"] == "required counter present"])

    def test_a_must_be_zero_counter_above_zero_fails(self):
        def accepted(report):
            report["once"]["counters"]["revoke.write.accepted"] = 1

        process, result = self.check(accepted)
        self.assertEqual((process.returncode, result["allChecksOk"]), (1, False))
        self.assertEqual([item["check"] for item in result["checks"] if not item["ok"]], ["revoke.write.*"])

    def test_duplicate_grants_count_only_on_the_relay_that_kept_its_grant_log(self):
        def vacuous(report):
            report["relays"]["load-0"]["duplicateGrants"] = 0

        def unmeasured_main(report):
            del report["relays"]["main"]["duplicateGrants"]

        def duplicated(report):
            report["relays"]["main"]["duplicateGrants"] = 1

        for change, main in ((vacuous, False), (unmeasured_main, True), (duplicated, True)):
            with self.subTest(change=change.__name__):
                process, result = self.check(change, retained_main=main)
                self.assertEqual((process.returncode, result["allChecksOk"]), (1, False))
                self.assertEqual(
                    [item["check"] for item in result["checks"] if not item["ok"]],
                    ["duplicateGrants 0 on the main relay, not measured on the load relays, every journal closed"])

    def test_once_only_scenarios_are_read_from_their_own_section(self):
        def moved_back(report):
            report["counters"].update(report.pop("once")["counters"])

        def split(report):
            report["once"]["counters"]["revoke.write.refusedByFence"] = 1

        def control(report):
            report["once"]["counters"]["revoke.control.rawClaimGranted"] = 0

        def group(report):
            report["once"]["groupDevices"] = 13

        def relay(report):
            # The relay counted 4 refusals; the probes it refused now number 5.
            report["once"]["counters"].update({"revoke.relay.refused": 3, "revoke.renew.connectionClosed": 1})

        for change, failing in ((moved_back, None), (split, "revoke.write.*"),
                                (control, "a member's raw claim on the same path is granted and released"),
                                (group, "qualified, stress and once-only group sizes"), (relay, "the relay's own refusal count")):
            with self.subTest(change=change.__name__):
                process, result = self.check(change)
                self.assertEqual((process.returncode, result["allChecksOk"]), (1, False))
                if failing is not None:
                    self.assertEqual([item["check"] for item in result["checks"] if not item["ok"]], [failing])

    def changed_reply(self, device, op, change):
        """Runs the checker after `change` to the last `op` reply in `device`'s log."""
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "output"
            d123_output(out)
            log = out / f"logs/{device}.stdout.jsonl"
            lines = [json.loads(line) for line in log.read_text().splitlines()]
            [line for line in lines if line.get("op") == op][-1].update(change)
            write_lines(log, lines)
            process = run_script("check_d123_v2.py", out, 0, Path(directory) / "result.json")
            return process, json.loads((Path(directory) / "result.json").read_text())

    def test_a_failed_or_unsplit_commit_stream_reply_fails(self):
        for change in ({"failed": 1, "errors": ["store closed"]}, {"refusedBy": {"fence": 0, "membership": 1}},
                       {"refusedBy": {"membership": 2}}):
            with self.subTest(change=change):
                process, result = self.changed_reply("ipad", "commitStream", change)
                self.assertEqual((process.returncode, result["allChecksOk"]), (1, False))
                self.assertEqual([item["check"] for item in result["checks"] if not item["ok"]],
                                 ["the revoked device's commits after the revocation"])

    def test_a_failed_or_unsplit_write_loop_reply_fails(self):
        for device, change in (("mac", {"failed": 1, "errors": ["store closed"]}), ("phone", {"errors": ["store closed"]}),
                               ("mac", {"refusedBy": {"fence": 1, "membership": 0}}), ("phone", {"refusedBy": None})):
            with self.subTest(device=device, change=change):
                process, result = self.changed_reply(device, "writeLoop", change)
                self.assertEqual((process.returncode, result["allChecksOk"]), (1, False))
                self.assertEqual([item["check"] for item in result["checks"] if not item["ok"]],
                                 ["every write loop of the Mac and the iPhone failed no commit"])


class CheckD133ExtraTests(unittest.TestCase):
    """check_d133_extra.py recounts from both device logs; a missing log is a failure, not 0."""

    def check(self, logs):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "output"
            name = "recovery.unacceptedOldEpochReported"
            write_json(out / "s2-measurements.json", {"counters": {name: 0}, "stress": {"counters": {name: 0}}})
            for device, lines in logs.items():
                write_lines(out / "logs" / f"{device}.stdout.jsonl", lines)
            result = Path(directory) / "result.json"
            process = run_script("check_d133_extra.py", out, result)
            self.assertTrue(result.is_file(), process.stderr)
            return process, json.loads(result.read_text())

    @staticmethod
    def ready(device):
        return {"event": "ready", "deviceId": device}

    def test_both_device_logs_with_a_ready_event_and_no_recovery_pass(self):
        process, result = self.check({"mac": [self.ready(MAC)], "phone": [self.ready(PHONE)], "ipad": [self.ready(IPAD)]})
        self.assertEqual((process.returncode, result["allChecksOk"]), (0, True), process.stdout)

    def test_a_missing_or_unready_device_log_fails(self):
        for logs in ({"phone": [self.ready(PHONE)]}, {"mac": [self.ready(MAC)]},
                     {"mac": [self.ready(MAC)], "phone": [{"event": "node", "kind": "paired", "at": 1}]},
                     {"mac": [self.ready(MAC)], "phone": []}):
            with self.subTest(logs=sorted(logs)):
                process, result = self.check(logs)
                self.assertEqual((process.returncode, result["allChecksOk"]), (1, False), process.stdout)

    def test_an_unaccepted_old_epoch_recovery_fails(self):
        event = {"event": "node", "kind": "applicationRecoveryRequired", "detail": "unacceptedOldEpoch", "at": 2}
        process, result = self.check({"mac": [self.ready(MAC), event], "phone": [self.ready(PHONE)]})
        self.assertEqual((process.returncode, result["allChecksOk"]), (1, False))


def load_samples_verifier():
    spec = importlib.util.spec_from_file_location("memoshi_verify_s2_samples", SCRIPTS / "verify_s2_samples.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def samples_output(out):
    """Writes an S2 output directory whose load CSVs reproduce every published load figure."""
    distribution = load_samples_verifier().distribution
    loads, relays = {}, {}
    for profile in ("p1", "p2", "p3", "p4"):
        workers = []
        for index in range(3):
            directory = out / "load-samples" / profile / str(index)
            directory.mkdir(parents=True)
            start, duration_ms = 10_000_000_000 * (index + 1), 4_000
            samples = {"claims": [1_000_000 + index, 2_000_000], "renewals": [3_000_000, 4_000_000, 5_000_000 + index],
                       "moves": [6_000_000]}
            for name, values in samples.items():
                (directory / f"{name}.csv").write_text("duration_ns\n" + "".join(f"{value}\n" for value in values))
            scheduler = [(start + 100_000_000, 1_000), (start + 2_000_000_000, 2_000), (start + 3_900_000_000, 3_000)]
            (directory / "scheduler.csv").write_text(
                "monotonic_ns,lateness_ns\n" + "".join(f"{time},{lateness}\n" for time, lateness in scheduler))
            window = min(duration_ms // 4, 10_000) * 1_000_000
            lateness = [value for _, value in scheduler]
            seconds = 4.0
            operations = len(samples["renewals"]) + 2 * len(samples["moves"])
            report = {
                "errors": 0, "claimFailures": 0, "moveFailures": 0, "loadInducedExpiries": 0, "fencedRenewals": 0,
                "recoveryClaims": 0, "steadyStartMonotonicNs": start, "steadyPhaseSeconds": seconds,
                "options": {"durationMs": duration_ms, "idleRenewMs": 500, "users": 2},
                "renewOperations": len(samples["renewals"]), "renewalsPerSecond": len(samples["renewals"]) / seconds,
                "authorityOperations": operations, "operationsPerSecond": operations / seconds,
                "periodicallyRenewedLeases": 1, "devices": 2, "conversations": 3,
                "lateness": distribution(lateness),
                "latenessFirstWindow": distribution([value for time, value in scheduler if time < start + window]),
                "latenessLastWindow": distribution([value for time, value in scheduler
                                                    if time >= start + duration_ms * 1_000_000 - window]),
                **{name: distribution(values) for name, values in samples.items()},
            }
            write_json(directory / "report.json", report)
            workers.append(report)
        claims, renewals, moves = 6, 9, 3
        relays["load-" + profile] = {
            "statistics": {"authorityMessages": claims + renewals + 2 * moves},
            "counters": {"claimsGranted": claims + moves, "claimsDenied": 0, "renewalsApplied": renewals,
                         "renewalsDenied": 0, "releases": moves, "releasesIgnored": 0, "groupCommitsDenied": 0,
                         "revokedRefusals": 0},
            "cpuSeconds": 1.5, "maximumResidentBytes": 1_000_000}
        loads[profile] = workers
    write_json(out / "s2-measurements.json", {"passed": True, "failures": [], "loads": loads, "relays": relays})


class VerifySamplesTests(unittest.TestCase):
    """verify_s2_samples.py checks with explicit conditions, so python3 -O cannot skip them."""

    def verify(self, change=None, optimize=False):
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "output"
            samples_output(out)
            if change is not None:
                change(out)
            result = Path(directory) / "result.json"
            process = run_script("verify_s2_samples.py", out, result, optimize=optimize)
            return process, json.loads(result.read_text()) if result.is_file() else None

    def test_matching_samples_verify_with_and_without_optimization(self):
        for optimize in (False, True):
            with self.subTest(optimize=optimize):
                process, result = self.verify(optimize=optimize)
                self.assertEqual(process.returncode, 0, process.stderr)
                self.assertEqual((result["verified"], result["workersVerified"], result["rawCSVsVerified"]), (True, 12, 48))

    def test_a_tampered_sample_fails_even_under_python_optimization(self):
        def tamper(out):
            path = out / "load-samples/p2/1/claims.csv"
            path.write_text(path.read_text().replace("2000000", "2000001"))

        def fail_report(out):
            path = out / "load-samples/p3/0/report.json"
            report = json.loads(path.read_text())
            report["errors"] = 1
            path.write_text(json.dumps(report))
            published = json.loads((out / "s2-measurements.json").read_text())
            published["loads"]["p3"][0]["errors"] = 1
            (out / "s2-measurements.json").write_text(json.dumps(published))

        for change in (tamper, fail_report):
            for optimize in (False, True):
                with self.subTest(change=change.__name__, optimize=optimize):
                    process, result = self.verify(change, optimize=optimize)
                    self.assertNotEqual(process.returncode, 0, process.stdout)
                    self.assertIsNone(result, "a failed verification wrote a verified result")


class S2RunnerTests(unittest.TestCase):
    """run-s2-full-v2.py runs from the repository's scripts/ alone; nothing is built."""

    def runner(self, directory, dirty):
        base = Path(directory).resolve()
        scripts = base / "copy/scripts"
        shutil.copytree(SCRIPTS, scripts, ignore=shutil.ignore_patterns("__pycache__", "tests"))
        # The repository the runner builds: a Git repository without the build scripts, so the
        # build step fails at once instead of compiling anything.
        repository = base / "repository"
        repository.mkdir()
        subprocess.run(GIT + ["-C", str(repository), "init", "--quiet"], check=True)
        (repository / "tracked.txt").write_text("tracked\n")
        subprocess.run(GIT + ["-C", str(repository), "add", "tracked.txt"], check=True)
        subprocess.run(GIT + ["-C", str(repository), "commit", "--quiet", "-m", "tracked"], check=True)
        if dirty:
            (repository / "untracked.txt").write_text("untracked\n")
        build_root = base / "build"
        build_root.mkdir(mode=0o700)
        run = base / "run"
        environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        process = subprocess.run([sys.executable, str(scripts / "run-s2-full-v2.py"), str(run), str(repository),
                                  str(build_root), str(base / "work")], capture_output=True, text=True,
                                 cwd=base, env=environment, timeout=120)
        return process, run

    @unittest.skipUnless(sys.platform == "darwin", "the owned process group helper reads macOS libproc")
    def test_the_runner_imports_its_helper_from_scripts_and_records_a_failed_build(self):
        with tempfile.TemporaryDirectory() as directory:
            process, run = self.runner(directory, dirty=False)
            self.assertNotIn("ModuleNotFoundError", process.stderr)
            self.assertEqual(process.returncode, 1, process.stderr)
            receipt = json.loads((run / "run.json").read_text())
            self.assertEqual((receipt["failedStep"], receipt["exitCode"], receipt["treeCleanAtStart"]), ("build", 1, True))
            self.assertEqual((receipt["build"]["completion"], receipt["build"]["groupDrained"]), ("exited", True))

    @unittest.skipUnless(sys.platform == "darwin", "the owned process group helper reads macOS libproc")
    def test_a_refused_tree_leaves_no_run_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            process, run = self.runner(directory, dirty=True)
            self.assertNotEqual(process.returncode, 0)
            self.assertIn("tree has changes besides the allowed untracked file", process.stderr)
            self.assertFalse(run.exists())


if __name__ == "__main__":
    unittest.main()
