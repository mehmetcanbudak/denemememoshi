"""Consumer-visible refusal of unaccepted SDKs and independently held releases."""
import copy
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from release_support import ReleaseError, validate_release_gate

REVISION = "a" * 40


def accepted_metadata():
    return {
        "schemaVersion": 1,
        "holds": {"releaseBlocked": False, "broaderQualificationBlocked": False},
        "sdk": {"consumerRevision": REVISION, "qualification": "accepted",
                "qualifyingTag": "slice-1", "acceptedBy": "release-owner",
                "evidenceSHA256": "b" * 64},
    }


class ReleaseAcceptanceTests(unittest.TestCase):
    def test_each_hold_wins_over_an_accepted_sdk(self):
        for hold in ("releaseBlocked", "broaderQualificationBlocked"):
            with self.subTest(hold=hold):
                record = accepted_metadata()
                record["holds"][hold] = True
                with self.assertRaises(ReleaseError):
                    validate_release_gate(record, REVISION)

    def test_development_proof_cannot_be_promoted_by_adding_a_tag(self):
        record = accepted_metadata()
        record["sdk"]["qualification"] = "development-only"
        with self.assertRaises(ReleaseError):
            validate_release_gate(record, REVISION)

    def test_acceptance_for_another_consumer_revision_is_not_portable(self):
        with self.assertRaises(ReleaseError):
            validate_release_gate(accepted_metadata(), "c" * 40)

    def test_unreviewed_or_undigested_acceptance_is_refused(self):
        for field in ("acceptedBy", "evidenceSHA256"):
            with self.subTest(field=field):
                record = accepted_metadata()
                record["sdk"][field] = None
                with self.assertRaises(ReleaseError):
                    validate_release_gate(record, REVISION)

    def test_arbitrary_refs_cannot_substitute_for_a_qualifying_slice(self):
        dotted = copy.deepcopy(accepted_metadata())
        dotted["sdk"]["qualifyingTag"] = "slice-2.2"
        validate_release_gate(dotted, REVISION)
        for reference in ("main", "slice-0", "slice-1^{commit}", "../slice-1", "slice-2."):
            with self.subTest(reference=reference):
                record = copy.deepcopy(accepted_metadata())
                record["sdk"]["qualifyingTag"] = reference
                with self.assertRaises(ReleaseError):
                    validate_release_gate(record, REVISION)
