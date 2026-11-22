#!/bin/bash
# Regenerates protocol/protocol.schema.json from the Swift types in Packages/MemoshiProtocol,
# the protocol's source of truth (D78).
#
#   scripts/protocol-schema.sh           rewrite protocol/protocol.schema.json
#   scripts/protocol-schema.sh --check   fail, printing the diff, when the committed file is stale
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/build-paths.sh

package="Packages/MemoshiProtocol"
schema="protocol/protocol.schema.json"

case "${1:-}" in
  "" | --check) ;;
  *)
    echo "usage: scripts/protocol-schema.sh [--check]" >&2
    exit 2
    ;;
esac

memoshi_package_paths "$package"
# Build from the committed Package.resolved, as the package tests do.
swift build "${swiftpm_args[@]}" --disable-automatic-resolution \
  --jobs "${MEMOSHI_BUILD_JOBS:-4}" --product memoshi-protocol-schema >&2
bin_path="$(swift build "${swiftpm_args[@]}" --disable-automatic-resolution --show-bin-path)"

generated="$(mktemp)"
trap 'rm -f "$generated"' EXIT
"$bin_path/memoshi-protocol-schema" >"$generated"

if [ "${1:-}" = "--check" ]; then
  if [ ! -f "$schema" ]; then
    echo "error: $schema is missing; run scripts/protocol-schema.sh" >&2
    exit 1
  fi
  if ! diff -u --label "$schema (committed)" --label "$schema (generated)" "$schema" "$generated"; then
    echo "error: $schema is stale or was edited by hand; run scripts/protocol-schema.sh" >&2
    exit 1
  fi
  echo "$schema matches the Swift types"
else
  mkdir -p "$(dirname "$schema")"
  cat "$generated" >"$schema"
  echo "wrote $schema"
fi
