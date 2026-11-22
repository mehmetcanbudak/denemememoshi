#!/bin/bash
# Checks the built Mac app's layout (09-platform-macos.md §7.2 and §8.1, D58):
#   - memoshid's app-shaped helper is at Contents/Helpers/memoshid.app with its bundle ID;
#   - the agent plist is in Contents/Library/LaunchAgents, labelled with memoshid's bundle
#     ID, and its BundleProgram resolves to an executable;
#   - the app, helper and optional mobile app include LICENSE and NOTICE unchanged;
#   - the apps carry the native MLS licence inventory, binding notice and provenance;
#   - an app that carries the Python runtime carries, inside it and unchanged, every licence
#     text retained for the runtime's packages (D126, D133);
#   - no Mach-O file is under any Contents/Resources.
# Usage: scripts/check-bundle.sh [path/to/Memoshi.app [path/to/MemoshiMobile.app]]
#
# With --release-composition it checks only that each named Release bundle (the Mac app, the
# iPhone and iPad app, or both) holds Mach-O code and that none of it contains a name that only
# Debug builds compile: the development tools of DevelopmentComposition, DevelopmentPythonTool
# and DevelopmentApprovalProbe (the iPhone and iPad app's and memoshid's approval test tool),
# their types, the launch arguments that enable them and memoshid's flag for the probe. Debug
# products contain these names, so the layout check above, which CI runs on Debug products, does
# not scan for them; the caller states the configuration.
# Usage: scripts/check-bundle.sh --release-composition BUNDLE...
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/build-paths.sh

failures=0
pass() { echo "ok: $*"; }
fail() {
  echo "error: $*" >&2
  failures=$((failures + 1))
}

if [ "${1:-}" = "--release-composition" ]; then
  shift
  if [ "$#" -eq 0 ]; then
    echo "usage: scripts/check-bundle.sh --release-composition BUNDLE..." >&2
    exit 2
  fi
  debug_only=(
    -e python_run -e DevelopmentPythonTool -e MemoshiDevelopmentPythonTool
    -e development_note -e MemoshiDevelopmentApprovalTool -e MemoshiDevelopmentBrowserReview
    -e DevelopmentApprovalProbe -e DevelopmentLaunchArgument -e development-approval-tool
  )
  for bundle in "$@"; do
    if [ ! -d "$bundle" ]; then
      fail "no bundle at $bundle"
      continue
    fi
    earlier=$failures
    binaries=0
    while IFS= read -r -d '' file; do
      [[ "$(file -b "$file")" == *"Mach-O"* ]] || continue
      binaries=$((binaries + 1))
      # Symbol names and string literals alike: the file's bytes, not only its symbol table.
      while IFS= read -r name; do
        fail "${file#"$bundle"/} contains the Debug-only '$name'"
      done < <(LC_ALL=C grep -a -o -F "${debug_only[@]}" "$file" | LC_ALL=C sort -u || true)
    done < <(find "$bundle" -type f -print0)
    if [ "$binaries" -eq 0 ]; then
      fail "$bundle has no Mach-O file"
    elif [ "$failures" -eq "$earlier" ]; then
      pass "no Debug-only development name in $binaries Mach-O file(s) of $bundle"
    fi
  done
  if [ "$failures" -gt 0 ]; then
    echo "error: $failures Release composition problem(s)" >&2
    exit 1
  fi
  exit 0
fi

readonly app="${1:-$memoshi_derived_data/Build/Products/Debug/Memoshi.app}"
readonly mobile_app="${2:-}"
readonly memoshid_id="com.mehmetcanbudak.memoshi.memoshid"
readonly helper="$app/Contents/Helpers/memoshid.app"
readonly agent_plist="$app/Contents/Library/LaunchAgents/$memoshid_id.plist"

if [ ! -d "$app" ]; then
  echo "error: no app at $app; run scripts/build-apps.sh first" >&2
  exit 1
fi

# plist_value <plist> <key>: prints the key's value, or nothing when it is missing.
plist_value() { /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null || true; }

# The outer identity and the helper's agent/version metadata are part of the sealed layout.
app_id=$(plist_value "$app/Contents/Info.plist" CFBundleIdentifier)
if [ "$app_id" = "com.mehmetcanbudak.memoshi.mac" ]; then
  pass "outer app has bundle ID $app_id"
else
  fail "outer app has unexpected bundle ID '$app_id'"
fi
if [ -x "$app/Contents/MacOS/Memoshi" ] &&
  [[ "$(file -b "$app/Contents/MacOS/Memoshi")" == *"Mach-O"*"executable"* ]]; then
  pass "outer app executable is present"
else
  fail "Contents/MacOS/Memoshi is not an executable Mach-O"
fi

# memoshid's helper bundle and its identity.
if [ -d "$helper" ]; then
  helper_id=$(plist_value "$helper/Contents/Info.plist" CFBundleIdentifier)
  if [ "$helper_id" = "$memoshid_id" ]; then
    pass "Contents/Helpers/memoshid.app has bundle ID $helper_id"
  else
    fail "Contents/Helpers/memoshid.app has bundle ID '$helper_id', expected $memoshid_id"
  fi
  if [ "$(plist_value "$helper/Contents/Info.plist" LSUIElement)" != "true" ]; then
    fail "memoshid must be an LSUIElement agent app"
  fi
  for version_key in CFBundleVersion CFBundleShortVersionString; do
    app_version=$(plist_value "$app/Contents/Info.plist" "$version_key")
    helper_version=$(plist_value "$helper/Contents/Info.plist" "$version_key")
    if [ -z "$app_version" ] || [ "$app_version" != "$helper_version" ]; then
      fail "app/helper $version_key must match and be nonempty"
    fi
  done
else
  fail "Contents/Helpers/memoshid.app is missing"
fi

# The agent plist and the executable its BundleProgram names, relative to the app bundle.
if [ -f "$agent_plist" ]; then
  if /usr/bin/plutil -lint -s "$agent_plist"; then
    pass "Contents/Library/LaunchAgents/$memoshid_id.plist is a valid plist"
  else
    fail "Contents/Library/LaunchAgents/$memoshid_id.plist is not a valid plist"
  fi
  label=$(plist_value "$agent_plist" Label)
  if [ "$label" = "$memoshid_id" ]; then
    pass "agent Label is $label"
  else
    fail "agent Label is '$label', expected $memoshid_id"
  fi
  program=$(plist_value "$agent_plist" BundleProgram)
  if [ "$program" != "Contents/Helpers/memoshid.app/Contents/MacOS/memoshid" ]; then
    fail "agent BundleProgram must name the embedded app-shaped helper exactly, not '$program'"
  elif [ -f "$app/$program" ] && [ -x "$app/$program" ] &&
    [[ "$(file -b "$app/$program")" == *"Mach-O"*"executable"* ]]; then
    pass "BundleProgram $program is an executable"
  else
    fail "BundleProgram $program does not resolve to an executable in $app"
  fi
else
  fail "Contents/Library/LaunchAgents/$memoshid_id.plist is missing"
fi

# Legal text uses each platform's resource layout and checked-in inputs only.
legal_resources=("$app/Contents/Resources" "$helper/Contents/Resources")
mls_resources=("$app/Contents/Resources/MemoshiMLS")
if [ -n "$mobile_app" ]; then
  legal_resources+=("$mobile_app")
  mls_resources+=("$mobile_app/MemoshiMLS")
fi
for resource_dir in "${legal_resources[@]}"; do
  for notice in LICENSE NOTICE; do
    resource="$resource_dir/$notice"
    if [ ! -f "$resource" ]; then
      fail "$resource is missing"
    elif /usr/bin/cmp -s "$notice" "$resource"; then
      pass "$resource matches $notice"
    else
      fail "$resource does not match $notice"
    fi
  done
done

for resource_dir in "${mls_resources[@]}"; do
  if python3 scripts/memoshi-mls-payload-manifest.py \
    --bundle-notices "$resource_dir"; then
    pass "$resource_dir notices match their retained inventory"
  else
    fail "$resource_dir notices are incomplete or changed"
  fi
done

# The Python runtime's retained licence texts (scripts/pyodide-licenses.json) travel with it.
for bundle in "$app" ${mobile_app:+"$mobile_app"}; do
  if python3 scripts/check-pyodide-licenses.py --bundle "$bundle"; then
    pass "$bundle carries the licence texts retained for its Python runtime, or has no such runtime"
  else
    fail "$bundle carries the Python runtime without every retained licence text"
  fi
done

# No Mach-O under Resources, in the app or in any bundle nested inside it.
resources=0
mach_o=0
while IFS= read -r -d '' file; do
  resources=$((resources + 1))
  if [[ "$(file -b "$file")" == *"Mach-O"* ]]; then
    fail "Mach-O file under Resources: ${file#"$app"/}"
    mach_o=$((mach_o + 1))
  fi
done < <(find "$app" -type f -path '*/Contents/Resources/*' -print0)
if [ "$mach_o" -eq 0 ]; then
  pass "no Mach-O among $resources file(s) under Contents/Resources"
fi

if [ "$failures" -gt 0 ]; then
  echo "error: $failures bundle layout problem(s)" >&2
  exit 1
fi
