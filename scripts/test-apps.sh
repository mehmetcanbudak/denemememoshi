#!/bin/bash
# Runs the unit tests of the app sources: MemoshiTests (apps/mac/MemoshiTests) on this Mac and
# MemoshiMobileTests (apps/ios/MemoshiMobileTests) in an iOS Simulator. Neither test bundle is
# hosted, so no app, memoshid or engine is launched. The iOS tests run on a new simulator device
# that this script creates and deletes again; no existing device is used. Run
# scripts/generate-project.sh first; scripts/build-apps.sh first makes this run incremental.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/build-paths.sh

readonly project="apps/mac/Memoshi.xcodeproj"
readonly derived_data="$memoshi_derived_data"

echo "MemoshiTests (macOS)"
xcodebuild test -quiet -project "$project" -scheme MemoshiTests -configuration Debug \
  -disableAutomaticPackageResolution \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived_data" \
  -jobs "${MEMOSHI_BUILD_JOBS:-4}"

# The newest available iOS runtime and the first iPhone it supports.
read -r runtime device_type < <(
  xcrun simctl list runtimes --json | /usr/bin/jq -r '
    [.runtimes[] | select(.platform == "iOS" and .isAvailable)] | last
    | [.identifier, (.supportedDeviceTypes | map(select(.productFamily == "iPhone")) | first
      | .identifier)] | @tsv'
)
if [ -z "${runtime:-}" ] || [ "$runtime" = null ] || [ -z "${device_type:-}" ] ||
  [ "$device_type" = null ]; then
  echo "error: no available iOS Simulator runtime with an iPhone device type" >&2
  exit 1
fi
device=$(xcrun simctl create "Memoshi app tests $$" "$device_type" "$runtime")
remove_device() {
  xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
  xcrun simctl delete "$device" >/dev/null 2>&1 || true
}
trap remove_device EXIT

echo "MemoshiMobileTests (iOS Simulator, $runtime)"
xcodebuild test -quiet -project "$project" -scheme MemoshiMobileTests -configuration Debug \
  -disableAutomaticPackageResolution \
  -destination "id=$device" -derivedDataPath "$derived_data" \
  -jobs "${MEMOSHI_BUILD_JOBS:-4}"
