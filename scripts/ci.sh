#!/bin/bash
# Runs every check CI runs, in CI's order, and stops at the first failure. The GitHub
# workflow only checks out the repository and runs this script, so a local run and a CI run
# never differ. Each check is its own script under scripts/ and can also run alone.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/build-paths.sh

# XcodeGen comes from Homebrew, and a runner started by launchd may not have Homebrew on
# its PATH. Appending keeps the system's own tools first.
case ":$PATH:" in
  *:/opt/homebrew/bin:*) ;;
  *) PATH="$PATH:/opt/homebrew/bin" ;;
esac
export PATH

# step <name> <command...>: runs one check and stops the whole run if it fails.
step() {
  local name="$1"
  shift
  local started=$SECONDS
  echo ""
  echo "==> $name: $*"
  if "$@"; then
    echo "--> $name passed in $((SECONDS - started)) s"
  else
    local status=$?
    echo "--> $name FAILED with exit status $status" >&2
    exit "$status"
  fi
}

step "Prerequisites" scripts/check-prerequisites.sh
step "Toolchain" scripts/check-toolchain.sh
step "Pinned native MLS payload" scripts/build-memoshi-mls.sh
step "Checked-in native MLS outputs" scripts/check-mls-generated.sh
step "Pinned Pyodide runtime" python3 scripts/package-pyodide.py --allow-download
step "Release tooling contracts" python3 -m unittest discover -s scripts/tests -v
step "Spike self-tests" scripts/test-spikes.sh
step "Design tokens" swift scripts/design-tokens.swift --check
step "Format and lint" scripts/lint-format.sh
step "Module boundaries" scripts/lint-boundaries.sh
step "Package tests" scripts/test-packages.sh
step "Licenses" scripts/scan-licenses.sh
step "Protocol schema drift" scripts/protocol-schema.sh --check
step "Xcode project" scripts/generate-project.sh
step "App builds" scripts/build-apps.sh
step "App tests" scripts/test-apps.sh
step "Sign-in flows" scripts/check-signin-flows.sh
step "Bundle layout" scripts/check-bundle.sh \
  "$memoshi_derived_data/Build/Products/Debug/Memoshi.app" \
  "$memoshi_derived_data/Build/Products/Debug-iphonesimulator/MemoshiMobile.app"

echo ""
echo "All checks passed."
