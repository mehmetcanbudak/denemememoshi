#!/bin/bash
# Checks what the rest of ci.sh needs before anything is built, so a missing prerequisite
# fails in seconds with an actionable message instead of after gigabytes of compilation.
#
# 1. Pi_Swift, pinned in scripts/lib/pi-swift-pin.sh. Its commit must be in a sibling Git clone
#    at ../Pi_Swift (README "Build and test"). A runner workspace has no such clone, so
#    MEMOSHI_PI_SWIFT_SOURCE may name a local clone to copy it from. The source is only read
#    and nothing is fetched remotely. Its slice-N tags are copied on every run, because a tag
#    can be created after CI first copied the commit. A tag that the source has since
#    re-pointed is never replaced: an error for a release (MEMOSHI_REQUIRE_RELEASE_DISK=true),
#    a warning for every other run.
#    From ../Pi_Swift this script creates the clean checkout that MemoshiCore's manifest uses
#    by path, if it is absent, and on every run refuses one whose HEAD is not the pinned
#    commit, whose annotated tag does not point at it, or that has any change, untracked or
#    ignored file (SwiftPM compiles every source in a target directory, ignored or not). It
#    also refuses a manifest that builds anything but the pinned checkout and the reviewed
#    dependencies, or a PiDevelopmentSnapshot.revision that disagrees with the pin.
# 2. On GitHub Actions, and for a release archive (MEMOSHI_REQUIRE_RELEASE_DISK=true),
#    the volume must have at least 15 GB free. MEMOSHI_CI_MIN_FREE_GB may raise, never
#    lower, that existing clean-workspace floor. No quota/billing workaround is attempted.
set -euo pipefail
cd "$(dirname "$0")/.."

failures=0
fail() {
  echo "error: $*" >&2
  failures=$((failures + 1))
}

source scripts/lib/pi-swift-pin.sh
revision=$PI_SWIFT_REVISION
tag=$PI_SWIFT_TAG
checkout=$PI_SWIFT_CHECKOUT
sibling=../Pi_Swift
manifest=Packages/MemoshiCore/Package.swift
snapshot=Packages/MemoshiCore/Sources/Runtime/RuntimeConfiguration.swift

has_candidate() {
  git -C "$sibling" cat-file -e "${revision}^{commit}" 2>/dev/null
}

if [ -n "${MEMOSHI_PI_SWIFT_SOURCE:-}" ]; then
  source_clone=$MEMOSHI_PI_SWIFT_SOURCE
  if [ ! -d "$source_clone" ] ||
    ! git -C "$source_clone" rev-parse --git-dir >/dev/null 2>&1 ||
    ! git -C "$source_clone" cat-file -e "${revision}^{commit}" 2>/dev/null; then
    if ! has_candidate; then
      fail "MEMOSHI_PI_SWIFT_SOURCE must be an existing local Git clone containing $revision; remote URLs are not fetched"
    fi
  else
    if has_candidate; then
      :
    elif [ -d "$sibling/.git" ]; then
      git -C "$sibling" fetch --quiet --no-tags "$source_clone" "$revision"
    elif [ ! -e "$sibling" ]; then
      git clone --quiet --no-checkout "$source_clone" "$sibling"
    fi
    # Without a leading +, Git refuses to move a slice tag that the sibling already has.
    if has_candidate && ! git -C "$sibling" fetch --quiet --no-tags "$source_clone" \
      'refs/tags/slice-*:refs/tags/slice-*'; then
      problem="could not copy every slice-* tag from MEMOSHI_PI_SWIFT_SOURCE into $sibling (Git does not move an existing tag); after review, delete the stale tag with: git -C $sibling tag -d <tag>"
      if [ "${MEMOSHI_REQUIRE_RELEASE_DISK:-}" = "true" ]; then
        fail "$problem"
      else
        echo "warning: $problem" >&2
      fi
    fi
  fi
fi

# The checkout is created only from a sibling that has the commit and its tag.
if [ ! -e "$checkout" ] && [ ! -L "$checkout" ]; then
  if ! has_candidate; then
    fail "Pi_Swift commit $revision is not in a Git clone at $sibling; clone the repository that contains it there, or set MEMOSHI_PI_SWIFT_SOURCE to a local clone"
  elif [ "$(git -C "$sibling" rev-parse --verify --quiet "refs/tags/${tag}^{commit}" || true)" != "$revision" ]; then
    fail "the tag $tag in $sibling does not point at $revision, so $checkout was not created"
  elif ! git clone --quiet --no-checkout "$sibling" "$checkout" ||
    ! git -C "$checkout" -c advice.detachedHead=false checkout --quiet --detach "$revision"; then
    fail "could not create $checkout from $sibling at $revision"
  else
    echo "ok: created $checkout from $sibling at $revision"
  fi
fi

# Its own clone: a real directory at that path (no symbolic link to another clone) that is the
# top level of its Git repository.
if [ -L "$checkout" ]; then
  fail "$checkout is a symbolic link; move it away so this script can create its own clone"
elif [ -e "$checkout" ]; then
  expected="$(cd .. && pwd -P)/${checkout##*/}"
  if [ ! -d "$checkout" ] || [ "$(cd "$checkout" && pwd -P)" != "$expected" ] ||
    [ "$(git -C "$checkout" rev-parse --show-toplevel 2>/dev/null || true)" != "$expected" ]; then
    fail "$checkout is not its own Git clone; move it away so this script can create it"
  elif [ "$(git -C "$checkout" rev-parse HEAD 2>/dev/null || true)" != "$revision" ]; then
    fail "$checkout is not checked out at $revision ($tag); run: git -C $checkout checkout --detach $revision"
  elif [ "$(git -C "$checkout" rev-parse --verify --quiet "refs/tags/${tag}^{commit}" || true)" != "$revision" ] ||
    [ "$(git -C "$checkout" cat-file -t "refs/tags/${tag}" 2>/dev/null || true)" != "tag" ]; then
    fail "$checkout has no annotated tag $tag that points at $revision"
  elif ! status=$(git -C "$checkout" status --porcelain --ignored --untracked-files=all); then
    fail "could not read the status of $checkout"
  elif [ -n "$status" ]; then
    fail "$checkout has changes, untracked or ignored files; Memoshi builds only the unmodified $tag commit (see: git -C $checkout status --ignored)"
  else
    echo "ok: Pi_Swift $tag ($revision) is checked out cleanly at $checkout"
  fi
fi

# The manifest and the runtime's recorded revision agree with the pin. Only active code counts,
# read as Swift: every .package( call must be the pinned checkout's path, once, or a reviewed
# dependency (scripts/lib/pi_swift_manifest.py, which scripts/release.py shares).
if ! python3 scripts/lib/pi_swift_manifest.py "$manifest" "../../${checkout}"; then
  fail "$manifest does not use Pi_Swift from ../../${checkout} alone, the checkout scripts/lib/pi-swift-pin.sh names"
fi
if ! grep -qE "static let revision = \"${revision}\"" "$snapshot"; then
  fail "PiDevelopmentSnapshot.revision in $snapshot is not $revision, the commit scripts/lib/pi-swift-pin.sh names"
fi

if [ "${GITHUB_ACTIONS:-}" = "true" ] || [ "${MEMOSHI_REQUIRE_RELEASE_DISK:-}" = "true" ]; then
  minimum_gb=${MEMOSHI_CI_MIN_FREE_GB:-15}
  if [[ ! "$minimum_gb" =~ ^[1-9][0-9]{0,5}$ ]] || [ "$minimum_gb" -lt 15 ]; then
    fail "MEMOSHI_CI_MIN_FREE_GB must be an integer of at least 15; clean-workspace disk enforcement cannot be lowered"
  else
    free_kb=$(df -Pk . | awk 'NR == 2 { print $4 }')
    free_gb=$((free_kb / 1024 / 1024))
    if [ "$free_gb" -lt "$minimum_gb" ]; then
      fail "${free_gb} GB free; a clean workspace needs ${minimum_gb} GB (MEMOSHI_CI_MIN_FREE_GB)"
    else
      echo "ok: ${free_gb} GB free (minimum ${minimum_gb} GB)"
    fi
  fi
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi
