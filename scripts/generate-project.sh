#!/bin/bash
# Generates apps/mac/Memoshi.xcodeproj from apps/mac/project.yml. The project is generated,
# never committed (phase-0.md §2.1); run this after every pull that touches project.yml.
#
# Xcode never reads a local package's Package.resolved: it resolves the whole project from one
# workspace-level lock inside the generated project, which a clean checkout does not have. This
# script writes that lock from the committed Packages/*/Package.resolved pins, and the builds
# pass -disableAutomaticPackageResolution (scripts/build-apps.sh, scripts/release.py), so the
# apps compile exactly the dependency revisions that `swift test` and the licence scan use.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --spec apps/mac/project.yml

readonly lock="apps/mac/Memoshi.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
# The lock holds each committed pin as it is, once per package identity; packages that disagree on
# a pin stop the generation. Pi_Swift is a path dependency (scripts/lib/pi-swift-pin.sh) and has
# no pin. A lock from an earlier run never survives a failed generation.
mkdir -p "$(dirname "$lock")"
rm -f "$lock"
if ! /usr/bin/jq -n '
  [inputs.pins[]] | group_by(.identity)
  | map(if (map({kind, state}) | unique | length) == 1 then .[0]
        else error("Packages/*/Package.resolved disagree on the pin for \(.[0].identity)") end)
  | {pins: ., version: 3}' Packages/*/Package.resolved >"$lock.tmp"; then
  rm -f "$lock.tmp"
  echo "error: could not write the project lock from the committed package pins" >&2
  exit 1
fi
mv "$lock.tmp" "$lock"
