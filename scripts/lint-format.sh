#!/bin/bash
# Lints every Swift source with swift-format and the root .swift-format configuration;
# warnings fail too (--strict). To fix formatting in place:
#   swift format format --in-place --configuration .swift-format <files>
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/swift-sources.sh

files=()
while IFS= read -r -d '' file; do
  case "$file" in
    # Preserve source-pinned vendor and generator bytes. The payload inventory checks them;
    # lint-boundaries still examines every source, including these third-party files.
    ./Packages/MemoshiMLS/Native/vendor/* | \
      ./Packages/MemoshiMLS/Sources/MemoshiMLSNativeBindings/*) continue ;;
  esac
  files+=("$file")
done < <(swift_sources)

if [ "${#files[@]}" -eq 0 ]; then
  echo "error: no Swift sources found" >&2
  exit 1
fi

echo "linting ${#files[@]} Swift files"
swift format lint --strict --parallel --configuration .swift-format "${files[@]}"
