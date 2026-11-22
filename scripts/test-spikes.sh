#!/bin/bash
# Runs the self-tests that live beside the S3 browser spike and the browser lab's cookie-probe
# registry (D131), so that they cannot rot:
#   - the analyzer of the no-bypass control (run-control.py), on synthetic run directories;
#   - the create-only evidence names of the Simulator driver (run-sim.py), with every
#     subprocess replaced;
#   - the probe registry that the iPhone and iPad app compiles in. That app has no test
#     target, so its source is compiled for this Mac together with the self-test.
# No network, no Simulator, no signing and no app build: nothing is launched except the
# compiled self-test, and no recorded spike result is read or rewritten.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/build-paths.sh

python3 -B -m unittest discover -s spikes/S3-webkit-browser/no-bypass -p 'test_*.py'
python3 -B -m unittest discover -s spikes/S3-webkit-browser/ios-simulator -p 'test_*.py'

temporary=${TMPDIR:-/tmp}
work=$(mktemp -d "${temporary%/}/memoshi-probe-record.XXXXXX")
trap 'rm -rf "$work"' EXIT
xcrun swiftc -D MEMOSHI_PROBE_RECORD_SELFTEST -parse-as-library \
  -o "$work/probe-record-selftest" apps/shared/BrowserReviewProfile.swift \
  apps/shared/MobileBrowserProbeRecord.swift \
  spikes/S3-webkit-browser/probe-record/ProbeRecordSelfTest.swift
"$work/probe-record-selftest"
