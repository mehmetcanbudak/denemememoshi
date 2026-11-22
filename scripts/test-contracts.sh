#!/bin/bash
# S1.17: the contract suite (Memoshi's Core suites plus Pi_Swift's PiDurable and PiEnv
# conformance suites) in three concurrent shards, so its wall time is the slowest shard's and
# not the sum. Tests are built once first; the build is not part of the measured time.
#   shard 1: MemoshiRuntimeTests      shard 2: MemoshiStoreTests + MemoshiEgressTests
#   shard 3: PiDurableTests + PiEnvTests from the pinned Pi_Swift checkout
# Needs MEMOSHI_BUILD_ROOT (Pi_Swift's build must not land in its clean checkout). Each shard
# keeps the canonical flags (--no-parallel, no automatic resolution); the shards only overlap
# in time. SwiftPM holds a lock on a scratch directory for a whole `swift test`, so two shards
# of one package in one scratch path run one after the other: shard 2 runs from an APFS clone
# (`cp -c`) of the Core scratch made after the build, removed at the end. A log that shows
# SwiftPM waiting for another instance makes the run invalid as a measurement (exit 3). Exit
# status is 0 only when every shard passed. Pi_Swift's own known failures count (S1 report 3a):
# they are Pi_Swift's to fix, not hidden here.
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/build-paths.sh
source scripts/lib/pi-swift-pin.sh
[ -n "${MEMOSHI_BUILD_ROOT:-}" ] || { echo "error: set MEMOSHI_BUILD_ROOT" >&2; exit 2; }
scripts/check-prerequisites.sh || exit 2

jobs=${MEMOSHI_BUILD_JOBS:-4}
memoshi_package_paths Packages/MemoshiCore
core=("${swiftpm_args[@]}")
pi=(--package-path "$PI_SWIFT_CHECKOUT" --scratch-path "$MEMOSHI_BUILD_ROOT/SPM/PiSwiftContracts"
  --cache-path "$MEMOSHI_BUILD_ROOT/cache")
common=(--disable-automatic-resolution)

swift build --build-tests "${core[@]}" "${common[@]}" --jobs "$jobs" || exit 2
swift build --build-tests "${pi[@]}" "${common[@]}" --jobs "$jobs" || exit 2

logs=$(mktemp -d "$TMPDIR/contracts.XXXXXX")
# The clone shares the built blocks; only what shard 2 writes takes new space.
clone="$MEMOSHI_BUILD_ROOT/SPM/Core-contracts-shard"
rm -rf "$clone"
cp -cR "$swiftpm_scratch" "$clone" || exit 2
trap 'rm -rf "$clone"' EXIT
store_core=("${core[@]}")
for index in "${!store_core[@]}"; do
  [ "${store_core[$index]}" = "$swiftpm_scratch" ] && store_core[$index]=$clone
done
run() { # name logfile swift-test-args...
  local name=$1 log=$2
  shift 2
  local started=$SECONDS
  swift test --skip-build --no-parallel "${common[@]}" "$@" >"$log" 2>&1
  local status=$?
  echo "$name $status $((SECONDS - started))" >"$log.result"
}
started=$SECONDS
run runtime "$logs/runtime.log" "${core[@]}" --filter MemoshiRuntimeTests &
run store-egress "$logs/store-egress.log" "${store_core[@]}" --filter MemoshiStoreTests --filter MemoshiEgressTests &
run pi-upstream "$logs/pi-upstream.log" "${pi[@]}" --filter PiDurableTests --filter PiEnvTests &
wait
wall=$((SECONDS - started))

status=0
printf '%-14s %-8s %s\n' shard exit seconds
for name in runtime store-egress pi-upstream; do
  read -r _ code seconds <"$logs/$name.log.result"
  printf '%-14s %-8s %s\n' "$name" "$code" "$seconds"
  [ "$code" -eq 0 ] || status=1
done
echo "wall: ${wall} s (bar: 300 s); logs: $logs"
if grep -l "Another instance of SwiftPM" "$logs"/*.log >/dev/null 2>&1; then
  echo "invalid: a shard waited for another SwiftPM instance, so the shards did not overlap" >&2
  exit 3
fi
exit "$status"
