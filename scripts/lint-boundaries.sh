#!/bin/bash
# Enforces the module boundaries of phase-0.md §2:
#   rule 1: only Packages/MemoshiCore/Sources/Runtime/ imports Pi_Swift modules (D44), and it
#           never re-exports one: `@_exported import` would hand the module to every importer
#           of the runtime without an import line for this lint to see;
#   rule 3: nothing imports memoshid's executable module, so the apps reach memoshid only
#           through the protocol and memoshid runs headless in tests.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/swift-sources.sh

# Every module that Pi_Swift's Package.swift and its vendored SwiftBashParser declare (49 at
# slice-2): the library products and their C and vendored modules, the PI_CLI-only terminal
# modules, the oracle and fixture support targets, and every executable target, including the
# PI_BENCH ones (Swift spells an executable's `-` as `_`). BoundaryLintTests compares the list
# with the pinned checkout's manifests; update it when the pin moves.
pi_swift_module_list=(
  PiCore PiTelemetry Chord PiAI PiAgent PiCodeMode PiMCP PiEnv PiDurable PiDurableMCP PiAppleHost PiChaosKit
  CChordSQLite CPiZstd CPiQuickJS BashSyntax
  PiTUI PiCodingAgent PiEvals PiTUITestSupport
  AIObserverOracleSupport AgentOracleSupport CatalogOracleSupport CoreOracleSupport
  AgentMCPCodeModeExample MCPConformanceFixture
  pi_env pi_chaos chord_platform_fixture codemode_workload pi_security_budgets
  agent_parity_fixture ai_observer_fixture bot_runtime_consumer catalog_oracle_fixture continued_processing_consumer
  core_oracle_fixture durable_mcp_stdio_fixture durable_recovery_fixture durable_store_lock_fixture
  env_public_consumer guarded_env_daemon_fixture login_shell_escape_fixture pi_durable_file_native_fixture
  pi_telemetry_consumer provider_wire_durable_fixture public_contracts_consumer storage_conformance_fixture
  typed_shell_consumer
)
pi_swift_modules=$(
  IFS='|'
  echo "${pi_swift_module_list[*]}"
)
readonly pi_swift_modules
readonly runtime_dir="./Packages/MemoshiCore/Sources/Runtime/"
readonly memoshid_module="memoshid"

# An import declaration with any attributes (@testable, @_exported, @preconcurrency,
# @_spi(...)), access level and declaration kind (`import struct M.T`), followed by the module
# name and a submodule dot, semicolon, whitespace or the end of the line.
readonly attributes='(@[[:alnum:]_]+(\([^)]*\))?[[:space:]]+)*'
readonly import_keyword='((public|package|internal|fileprivate|private|open)[[:space:]]+)?import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?'
readonly import_prefix="^[[:space:]]*${attributes}${import_keyword}"
readonly import_suffix='([.;[:space:]]|$)'
readonly pi_swift_import="${import_prefix}(${pi_swift_modules})${import_suffix}"
readonly pi_swift_reexport="^[[:space:]]*${attributes}@_exported[[:space:]]+${attributes}${import_keyword}(${pi_swift_modules})${import_suffix}"
readonly memoshid_import="${import_prefix}${memoshid_module}${import_suffix}"

violations=0
unreadable=0
files=0

# report <file> <grep -n matches> <message>
report() {
  local line
  while IFS= read -r line; do
    echo "${1#./}:${line%%:*}: error: $3: ${line#*:}" >&2
    violations=$((violations + 1))
  done <<<"$2"
}

# scan <file> <pattern> <message>: grep's status 0 is a violation and 1 a clean file; any other
# status (an unreadable file) fails the lint, because the file was not checked.
scan() {
  local matches status=0
  matches=$(grep -n -E "$2" "$1") || status=$?
  case "$status" in
    0) report "$1" "$matches" "$3" ;;
    1) ;;
    *)
      echo "${1#./}: error: could not read the file (grep exit $status), so its imports were not checked" >&2
      unreadable=$((unreadable + 1))
      ;;
  esac
}

# The source list is complete or the lint fails: a find error is not an empty list.
sources=$(mktemp)
trap 'rm -f "$sources"' EXIT
if ! swift_sources >"$sources"; then
  echo "error: could not list the Swift sources" >&2
  exit 1
fi

while IFS= read -r -d '' file; do
  files=$((files + 1))
  case "$file" in
    "$runtime_dir"*)
      scan "$file" "$pi_swift_reexport" \
        "Packages/MemoshiCore/Sources/Runtime/ may import Pi_Swift modules but never re-export them (phase-0 §2 rule 1)"
      ;;
    *)
      scan "$file" "$pi_swift_import" \
        "only Packages/MemoshiCore/Sources/Runtime/ may import Pi_Swift modules (phase-0 §2 rule 1)"
      ;;
  esac
  scan "$file" "$memoshid_import" "no target may import memoshid's executable module (phase-0 §2 rule 3)"
done <"$sources"

failed=0
if [ "$files" -eq 0 ]; then
  echo "error: no Swift sources found, so no module boundary was checked" >&2
  failed=1
fi
if [ "$unreadable" -gt 0 ]; then
  echo "error: $unreadable Swift file(s) could not be read" >&2
  failed=1
fi
if [ "$violations" -gt 0 ]; then
  echo "error: $violations module boundary violation(s)" >&2
  failed=1
fi
if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "ok: $files Swift files respect the module boundaries"
