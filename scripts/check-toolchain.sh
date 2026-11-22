#!/bin/bash
# Asserts the current qualified baseline (D97): Xcode 27.2, Swift 6.4.2 and
# XcodeGen 2.48.0. Adopt newer stable releases by updating this baseline and qualifying them.
set -euo pipefail

readonly expected_xcode="27.2"
readonly expected_swift="6.4.2"
readonly expected_xcodegen="2.48.0"

failures=0

# check <tool> <expected> <found>
check() {
  if [ "$3" = "$2" ]; then
    echo "ok: $1 $3"
  else
    echo "error: $1 must be $2, found '${3:-nothing}'" >&2
    failures=$((failures + 1))
  fi
}

echo "developer directory: $(xcode-select --print-path 2>/dev/null || echo unknown)"

xcode=$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode //p' || true)
check "Xcode" "$expected_xcode" "$xcode"

swift=$(swift --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p' || true)
check "Swift" "$expected_swift" "$swift"

xcodegen=$(xcodegen --version 2>/dev/null | sed -n 's/^Version: //p' || true)
check "XcodeGen" "$expected_xcodegen" "$xcodegen"

[ "$failures" -eq 0 ]
