#!/bin/bash
# Builds the Mac app, with memoshid embedded, and the iPhone and iPad app for the simulator.
# Derived data stays inside the workspace (build/DerivedData), because the CI Mac also runs
# other repositories' runners. Run scripts/generate-project.sh first: it writes the project
# lock, and -disableAutomaticPackageResolution makes any other dependency version an error.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/build-paths.sh

readonly project="apps/mac/Memoshi.xcodeproj"
readonly derived_data="$memoshi_derived_data"

echo "Memoshi (macOS)"
xcodebuild build -quiet -project "$project" -scheme Memoshi -configuration Debug \
  -disableAutomaticPackageResolution \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived_data" \
  -jobs "${MEMOSHI_BUILD_JOBS:-4}"

echo "MemoshiMobile (iOS Simulator)"
xcodebuild build -quiet -project "$project" -scheme MemoshiMobile -configuration Debug \
  -disableAutomaticPackageResolution \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived_data" \
  -jobs "${MEMOSHI_BUILD_JOBS:-4}"
