#!/bin/bash
# Runs `swift test` for every local SwiftPM package under Packages/. The packages build and
# test without Xcode (phase-0.md §2).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/build-paths.sh

# Unrelated WasmKit startups/process-kill cases must not consume another case's wall-clock
# budget. Concurrency inside each scenario remains exercised; no assertion/deadline is relaxed.
# Resolve only the reviewed lock files, never a newer dependency during a qualifying run.
tested=0
for manifest in Packages/*/Package.swift; do
  [ -f "$manifest" ] || continue
  package=$(dirname "$manifest")
  memoshi_package_paths "$package"
  echo "swift test ${swiftpm_args[*]} --disable-automatic-resolution --no-parallel --jobs ${MEMOSHI_BUILD_JOBS:-4}"
  swift test "${swiftpm_args[@]}" --disable-automatic-resolution --no-parallel --jobs "${MEMOSHI_BUILD_JOBS:-4}"
  tested=$((tested + 1))
done

if [ "$tested" -eq 0 ]; then
  echo "error: no packages under Packages/" >&2
  exit 1
fi
