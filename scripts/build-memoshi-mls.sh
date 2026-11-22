#!/bin/bash
# Build source-pinned MLS + the upstream CryptoKit provider for Apple arm64.
# No tool installation, account changes, signing, cloud calls, tests, or fallbacks.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/lib/build-paths.sh"
package="$root/Packages/MemoshiMLS"
native="$package/Native"
work="${MEMOSHI_MLS_BUILD_ROOT:-${MEMOSHI_BUILD_ROOT:-$package/.build}/MLS-native}"
# A rustup selector is not a floating compiler pin: validate its exact release before use.
# This host's stable 1.97.0 install already has all Apple targets; its separate numeric
# 1.97.0 installation has only macOS. Neither installation is changed by this script.
toolchain="${MEMOSHI_MLS_RUST_TOOLCHAIN:-stable}"
cargo=(rustup run "$toolchain" cargo)
rustc=(rustup run "$toolchain" rustc)
actual_rust="$("${rustc[@]}" --version)"
case "$actual_rust" in
  "rustc 1.97.0 ("*) ;;
  *) echo "error: MLS requires Rust 1.97.0, but selector $toolchain resolves to $actual_rust" >&2; exit 1 ;;
esac
for target in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim; do
  library_directory="$("${rustc[@]}" --target "$target" --print target-libdir)"
  standard_libraries=("$library_directory"/libstd-*.rlib)
  if [ ! -f "${standard_libraries[0]}" ]; then
    echo "error: Rust 1.97.0 selector $toolchain has no installed $target standard library; select a complete existing install explicitly" >&2
    exit 1
  fi
done
mkdir -p "$work" "$package/Artifacts" "$package/Sources/MemoshiMLSNativeBindings" "$package/Generated/include"
export CARGO_TARGET_DIR="$work/cargo"
export CARGO_INCREMENTAL=0
# Rustup `run` fails if this exact toolchain/target is absent; it does not install one.
for target in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim; do
  case "$target" in
    aarch64-apple-darwin) sdk=macosx ;;
    aarch64-apple-ios) sdk=iphoneos ;;
    aarch64-apple-ios-sim) sdk=iphonesimulator ;;
  esac
  sdkroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  SDKROOT="$sdkroot" MACOSX_DEPLOYMENT_TARGET=27.0 IPHONEOS_DEPLOYMENT_TARGET=27.0 \
    "${cargo[@]}" build --locked --release --manifest-path "$native/Cargo.toml" \
      --package memoshi-mls-native --lib --target "$target"
done

# UniFFI is compiled from the SAME Cargo.lock, not installed or downloaded as a tool.
# Its library-mode parser reads metadata; it does not execute the MLS dylib.
mkdir -p "$work/generated"
"${cargo[@]}" run --locked --release --manifest-path "$native/Cargo.toml" \
  --package memoshi-mls-bindgen -- generate \
  --library "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/libmemoshi_mls_native.dylib" \
  --language swift --crate memoshi_mls_native --config "$native/bindgen.toml" \
  --out-dir "$work/generated" --no-format

# Staging: nothing installed changes until every output is built, verified and staged where its
# install is one rename(2) that cannot cross a volume. The XCFramework is staged in Artifacts,
# and each tracked file as a hidden copy in its own directory. A step that fails before the
# install leaves the old bindings, header and binary together.
artifacts="$package/Artifacts"
staging="$(mktemp -d "$artifacts/.install.XXXXXX")"
beside=()
trap 'rm -rf "$staging" ${beside[@]+"${beside[@]}"}' EXIT
fail() { echo "error: $*" >&2; exit 1; }
mkdir "$staging/include"
cp "$work/generated/MemoshiMLSNativeFFI.h" "$staging/include/MemoshiMLSNativeFFI.h"
cp "$work/generated/MemoshiMLSNativeFFI.modulemap" "$staging/include/module.modulemap"
framework="$staging/MemoshiMLSNativeFFI.xcframework"
xcodebuild -create-xcframework \
  -library "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/libmemoshi_mls_native.a" -headers "$staging/include" \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libmemoshi_mls_native.a" -headers "$staging/include" \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libmemoshi_mls_native.a" -headers "$staging/include" \
  -output "$framework"
python3 "$root/scripts/retain-memoshi-mls-licenses.py" --toolchain "$toolchain"
# Verification: the bindings exist, and every slice of the binary carries exactly the header and
# module map that are installed beside it.
[ -s "$work/generated/MemoshiMLSNativeBindings.swift" ] || fail "UniFFI wrote no Swift bindings"
[ -f "$framework/Info.plist" ] || fail "the staged XCFramework has no Info.plist"
headers=0
while IFS= read -r -d '' directory; do
  diff -r "$directory" "$staging/include" >/dev/null ||
    fail "the staged XCFramework's ${directory#"$framework"/} differ from the generated header and module map"
  headers=$((headers + 1))
done < <(find "$framework" -type d -name Headers -print0)
[ "$headers" -gt 0 ] || fail "the staged XCFramework carries no headers"
sources=("$work/generated/MemoshiMLSNativeBindings.swift" "$staging/include/MemoshiMLSNativeFFI.h"
  "$staging/include/module.modulemap")
destinations=("$package/Sources/MemoshiMLSNativeBindings/MemoshiMLSNativeBindings.swift"
  "$package/Generated/include/MemoshiMLSNativeFFI.h" "$package/Generated/include/module.modulemap")
for index in "${!destinations[@]}"; do
  copy="$(mktemp "$(dirname "${destinations[index]}")/.$(basename "${destinations[index]}").XXXXXX")"
  beside+=("$copy")
  cp "${sources[index]}" "$copy"
  chmod 644 "$copy"
done
# Install, after the build, the bindings, the XCFramework, the licence step (which also refuses
# a crate licence D126 does not accept) and the verification. Only renames remain. The payload
# manifest is the install's commit record: it is removed before the first rename and written
# after the last, so an install that stops in between leaves no manifest, and
# `memoshi-mls-payload-manifest.py --check` (check-bundle.sh, scan-licenses.sh, release.py)
# refuses the mixed payload. Only this script's generated output is replaced.
rm -f "$artifacts/payload-manifest.json"
for index in "${!destinations[@]}"; do
  mv -f "${beside[index]}" "${destinations[index]}"
done
if [ -e "$artifacts/MemoshiMLSNativeFFI.xcframework" ]; then
  mv "$artifacts/MemoshiMLSNativeFFI.xcframework" "$staging/replaced.xcframework"
fi
mv "$framework" "$artifacts/MemoshiMLSNativeFFI.xcframework"
python3 "$root/scripts/memoshi-mls-payload-manifest.py" --toolchain "$toolchain"
printf '%s\n' "MLS payload: $package/Artifacts/MemoshiMLSNativeFFI.xcframework" \
  "Bindings: $package/Sources/MemoshiMLSNativeBindings/MemoshiMLSNativeBindings.swift" \
  'Behavior tests (run after integration): swift test --package-path Packages/MemoshiMLS'
