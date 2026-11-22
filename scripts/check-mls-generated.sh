#!/bin/bash
# Checks that the tracked files scripts/build-memoshi-mls.sh regenerates (the UniFFI Swift
# bindings, their header and module map, and the retained Cargo licence inventory) still equal
# the checked-in ones. Run it right after that build. The payload manifest cannot show this:
# it lives in the ignored Artifacts directory and the same build rewrites it. Without this
# check, CI would test regenerated bindings while the commit keeps stale ones.
# The comparison is against the Git index, so staging regenerated files satisfies a local run;
# in a clean CI checkout the index is the commit.
set -euo pipefail
cd "$(dirname "$0")/.."

readonly generated=(
  Packages/MemoshiMLS/Sources/MemoshiMLSNativeBindings
  Packages/MemoshiMLS/Generated
  Packages/MemoshiMLS/Native/Licenses
)

changed=$(git diff --name-only -- "${generated[@]}")
untracked=$(git ls-files --others --exclude-standard -- "${generated[@]}")
if [ -n "$changed$untracked" ]; then
  while IFS= read -r file; do
    [ -z "$file" ] || echo "error: $file differs from the checked-in MLS output" >&2
  done <<<"$changed"$'\n'"$untracked"
  echo "error: the native MLS sources or Cargo.lock changed without their regenerated outputs; add the files scripts/build-memoshi-mls.sh wrote to the same commit" >&2
  exit 1
fi
echo "ok: regenerated native MLS bindings and licence inventory match the checked-in files"
