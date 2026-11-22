#!/bin/bash
# Optional isolated build volume; unset preserves the repository's existing paths.
# Source from repository-root scripts. No global caches/configuration are changed.
if [ -n "${MEMOSHI_BUILD_ROOT:-}" ]; then
  case "$MEMOSHI_BUILD_ROOT" in
    /*) ;;
    *) echo 'error: MEMOSHI_BUILD_ROOT must be an absolute directory' >&2; return 1 ;;
  esac
  if [ ! -d "$MEMOSHI_BUILD_ROOT" ] || [ -L "$MEMOSHI_BUILD_ROOT" ] ||
    [ "$(stat -f '%u' "$MEMOSHI_BUILD_ROOT")" != "$(id -u)" ] ||
    [ "$(stat -f '%Lp' "$MEMOSHI_BUILD_ROOT")" != 700 ]; then
    echo 'error: MEMOSHI_BUILD_ROOT must be an existing, owned, non-symlink 0700 directory' >&2
    return 1
  fi
  mkdir -p "$MEMOSHI_BUILD_ROOT/tmp" "$MEMOSHI_BUILD_ROOT/cache"
  export TMPDIR="$MEMOSHI_BUILD_ROOT/tmp"
  export CLANG_MODULE_CACHE_PATH="$MEMOSHI_BUILD_ROOT/cache/clang"
  export SWIFTPM_MODULECACHE_OVERRIDE="$MEMOSHI_BUILD_ROOT/cache/swift"
fi

# Sets an argv array and exact workspace path for both build and license-state inspection.
memoshi_package_paths() {
  local package="$1" name
  name="${package##*/}"
  name="${name#Memoshi}"
  swiftpm_args=(--package-path "$package")
  swiftpm_scratch="$package/.build"
  if [ -n "${MEMOSHI_BUILD_ROOT:-}" ]; then
    swiftpm_scratch="$MEMOSHI_BUILD_ROOT/SPM/$name"
    swiftpm_args+=(--scratch-path "$swiftpm_scratch" --cache-path "$MEMOSHI_BUILD_ROOT/cache")
  fi
}

export memoshi_derived_data="${MEMOSHI_BUILD_ROOT:-build}/DerivedData"
