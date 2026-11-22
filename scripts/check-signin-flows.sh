#!/bin/bash
# Checks Pi_Swift requirement E11 (phase-0.md §2 rule 5; D54, D79; DIST-03 as narrowed by D108 in
# docs/plan/decisions.md). A product build may contain only Sign in with ChatGPT, API keys, and
# OpenRouter's and Radius's sign-ins. The app itself contains no Anthropic sign-in flow; a user's
# own Claude Code install is a separate program. It fails when:
#   - a Memoshi package manifest, the XcodeGen spec, the generated Xcode project, a build or
#     release script or a CI workflow enables a package trait. Pi_Swift compiles its other
#     subscription sign-ins only under its non-default SubscriptionLogins trait;
#   - a built app or its helper contains a restricted subscription client ID;
#   - the Pi_Swift pin (scripts/lib/pi-swift-pin.sh) differs from the revision the client-ID
#     list was taken from.
# The six IDs are the ones Pi_Swift's own E11 artifact check uses at that revision
# (Scripts/auth-profiles.mjs `subscriptions`; Sources/PiAI/Auth/BrowserOAuth.swift and
# DeviceOAuth.swift). When the pin moves, re-derive them from the new revision first.
# Usage: scripts/check-signin-flows.sh [app ...]
#   (default: the Debug Mac app, with its embedded memoshid, and the iPhone/iPad Simulator app)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/build-paths.sh
source scripts/lib/pi-swift-pin.sh

readonly reviewed_pin="56d6fc89ebb039ad1b5e9128c8b12131d92d0cbe"
readonly restricted_ids=(
  "9d1c250a-e61b-44d9-88ed-5944d1962f5e" # Anthropic (Claude Pro/Max)
  "1031625952748946"                     # Meta
  "app_EMoamEEZ73f0CkXaXp7hrann"         # OpenAI Codex CLI
  "Iv1.b507a08c87ecfe98"                 # GitHub Copilot
  "17e5f671-d194-4dfb-9706-5516cb48c098" # Kimi Coding
  "b1a00492-073a-47ea-816f-4c329264a828" # xAI
)
# Sign in with ChatGPT's dynamic client. Every app that links PiAI must show it, which proves
# the byte scan sees PiAI's compiled string literals rather than passing vacuously.
readonly allowed_marker="dynamic_agent_client"

if [ "$#" -gt 0 ]; then
  apps=("$@")
else
  apps=(
    "$memoshi_derived_data/Build/Products/Debug/Memoshi.app"
    "$memoshi_derived_data/Build/Products/Debug-iphonesimulator/MemoshiMobile.app"
  )
fi

failures=0
pass() { echo "ok: $*"; }
fail() {
  echo "error: $*" >&2
  failures=$((failures + 1))
}

# no_matches <what> <extended regex> <file...>: true when no file matches. Each match, or a
# failure to read, is reported; grep's own failure is never read as a clean result.
no_matches() {
  local what="$1" pattern="$2" status=0 output line
  shift 2
  output=$(grep -nE -- "$pattern" "$@") || status=$?
  [ "$status" -eq 1 ] && return 0
  if [ "$status" -eq 0 ]; then
    while IFS= read -r line; do fail "$what: $line"; done <<<"$output"
  else
    fail "could not search $*"
  fi
  return 1
}

# The Pi_Swift pin is exactly the reviewed revision.
if [ "$PI_SWIFT_REVISION" = "$reviewed_pin" ]; then
  pass "the Pi_Swift pin is $reviewed_pin, the revision of the client-ID list"
else
  fail "the Pi_Swift pin $PI_SWIFT_REVISION is not $reviewed_pin; re-derive the restricted client IDs from the new revision"
fi

# No manifest, project or build entry point enables a package trait.
manifests=(Packages/*/Package.swift apps/mac/project.yml)
if [ -f apps/mac/Memoshi.xcodeproj/project.pbxproj ]; then
  manifests+=(apps/mac/Memoshi.xcodeproj/project.pbxproj)
fi
entry_points=()
for file in scripts/*.sh scripts/*.py scripts/lib/* .github/workflows/*; do
  if [ -f "$file" ] && [ "$file" != scripts/check-signin-flows.sh ]; then
    entry_points+=("$file")
  fi
done
if no_matches "package trait enabled" \
  'SubscriptionLogins|\b(enabledTraits|traits)[[:space:]]*[:=]' "${manifests[@]}"; then
  pass "${#manifests[@]} manifests and project files enable no package trait"
fi
if no_matches "package trait enabled" \
  'SubscriptionLogins|--traits|--enable-all-traits' "${entry_points[@]}"; then
  pass "${#entry_points[@]} build scripts and workflows enable no package trait"
fi

# No built app or helper contains a restricted client ID.
patterns=()
for id in "${restricted_ids[@]}"; do patterns+=(-e "$id"); done
for app in "${apps[@]}"; do
  if [ ! -d "$app" ]; then
    fail "no app at $app; run scripts/build-apps.sh first"
    continue
  fi
  executables=$(find "$app" -type f -perm -u+x | wc -l | tr -d ' ')
  if [ "$executables" -eq 0 ]; then
    fail "$app contains no executable to scan"
    continue
  fi
  if [ "$(basename "$app")" = Memoshi.app ] && [ ! -d "$app/Contents/Helpers/memoshid.app" ]; then
    fail "$app has no embedded Contents/Helpers/memoshid.app to scan"
  fi
  if [ -n "$(find "$app" -type d -name Pi_PiAI.bundle -print -quit)" ]; then
    if grep -rqaF -- "$allowed_marker" "$app"; then
      pass "$app links PiAI, and its Sign in with ChatGPT client literal is visible to this scan"
    else
      fail "$app links PiAI but no compiled PiAI literal was found, so the scan would be vacuous"
    fi
  fi
  status=0
  found=$(grep -rHoaF "${patterns[@]}" "$app") || status=$?
  if [ "$status" -eq 1 ]; then
    pass "$app: $executables executables, no restricted subscription client ID"
  elif [ "$status" -eq 0 ]; then
    while IFS= read -r line; do
      fail "restricted subscription client ID ${line##*:} in ${line%:*}"
    done < <(sort -u <<<"$found")
  else
    fail "could not scan $app"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "error: $failures sign-in flow check(s) failed" >&2
  exit 1
fi
echo "Product builds contain only the allowed sign-in flows."
