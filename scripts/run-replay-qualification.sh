#!/bin/bash
# Signed event-replay qualification (P0-07, P0-08, exit criterion 6): 1,000 reconnect cycles
# and owner-EOF helper restarts over the real signed same-FD Unix WebSocket carrier, then a
# seq-0 rebuild and a fresh store fold that must equal the live client and the commit receipts.
# Development evidence on an owned synthetic store, not release or device qualification.
#   scripts/run-replay-qualification.sh OUTPUT_DIR [--cycles N] [--restart-every N] [--seed N]
# Signs two copies of the built helpers with an installed Apple Development identity
# (MEMOSHI_REPLAY_IDENTITY overrides the SHA-1): one as memoshid, one as the Mac app.
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:?usage: run-replay-qualification.sh OUTPUT_DIR [client options]}
shift
[ ! -e "$output" ] || { echo "error: $output already exists" >&2; exit 1; }

identity=${MEMOSHI_REPLAY_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}
[ -n "$identity" ] || { echo "error: no Apple Development signing identity" >&2; exit 1; }

# The same build paths and pins as the package tests: MEMOSHI_BUILD_ROOT is honoured, and no
# dependency is resolved anew.
source scripts/lib/build-paths.sh
memoshi_package_paths Packages/MemoshiDaemon
build=("${swiftpm_args[@]}" --disable-automatic-resolution)
swift build "${build[@]}" --product memoshi-replay-daemon
swift build "${build[@]}" --product memoshi-replay-client
bin=$(swift build "${build[@]}" --show-bin-path)

# A short root under /private/tmp keeps the Unix socket path within the 104-byte limit.
work=$(mktemp -d /private/tmp/memoshi-replay-run.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
# SwiftPM resource bundles (the store's migrations) are found beside the executable.
cp -R "$bin"/*.bundle "$work/bin/"
cat >"$work/empty.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST
sign() { # product identifier
  cp "$bin/$1" "$work/bin/$1"
  codesign --force --sign "$identity" --options runtime --timestamp=none \
    --identifier "$2" --entitlements "$work/empty.entitlements" "$work/bin/$1"
  codesign --verify --strict "$work/bin/$1"
}
sign memoshi-replay-daemon com.mehmetcanbudak.memoshi.memoshid
sign memoshi-replay-client com.mehmetcanbudak.memoshi.mac

mkdir -p "$output"
status=0
"$work/bin/memoshi-replay-client" --daemon "$work/bin/memoshi-replay-daemon" \
  --schema protocol/protocol.schema.json --root "$work/run" --output "$output/replay-report.json" \
  "$@" 2>&1 | tee "$output/client-stdout.txt" || status=$?
for f in "$work"/bin/memoshi-replay-*; do codesign -dvv "$f" 2>&1 | sed "s|^|$(basename "$f"): |"; done >"$output/signing-details.txt"
cp "$work"/run/daemon-*-stderr.log "$output/" 2>/dev/null || true
exit "$status"
