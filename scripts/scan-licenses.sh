#!/bin/bash
# License scan (D33, D126; 09-platform-macos.md §7.9). Every SwiftPM dependency that a package
# under Packages/ resolves, including the ones only its tests and tools use, must carry an
# MIT, Apache-2.0, BSD or ISC license, read from the license files at the root of its
# checked-out sources. GPL is accepted only for the dependencies of Packages/ISH, the GPL-3.0
# module that only the iPhone and iPad app links (D69), and no other package may depend on
# Packages/ISH. A dependency without a license file, or with a license this scan does not
# recognize, fails. Other local packages in this repository are covered by its LICENSE.
# The same accepted list holds for the Rust crates of the MLS library, with D126's two named
# exceptions, and for the Python packages shipped with Pyodide, through their reviewed table
# (scripts/lib/license_policy.py, scripts/pyodide-licenses.json).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/build-paths.sh
export LC_ALL=C

repo_root=$(pwd -P)
readonly repo_root
readonly gpl_package="Packages/ISH"

# Prints the license one file carries: MIT, Apache-2.0, BSD, ISC, GPL, the name of a
# license that is never accepted, or "unknown". The four-clause BSD license, with its
# advertising clause, is not accepted.
classify() {
  local text
  text=$(tr -s '[:space:]' ' ' <"$1" | tr '[:upper:]' '[:lower:]')
  case "$text" in
    *"gnu affero general public license"*) echo "AGPL" ;;
    *"gnu lesser general public license"* | *"gnu library general public license"*) echo "LGPL" ;;
    *"gnu general public license"*) echo "GPL" ;;
    *"apache license"*"version 2.0"*) echo "Apache-2.0" ;;
    *"permission is hereby granted, free of charge, to any person obtaining a copy"*) echo "MIT" ;;
    *"redistribution and use in source and binary forms, with or without modification, are permitted"*)
      case "$text" in
        *"all advertising materials mentioning features"*) echo "BSD-4-Clause" ;;
        *) echo "BSD" ;;
      esac
      ;;
    *"permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted"* | \
      *"permission to use, copy, modify, and distribute this software for any purpose with or without fee is hereby granted"*)
      echo "ISC"
      ;;
    *) echo "unknown" ;;
  esac
}

failures=0
checked=0

# fail <message>: reports one problem and counts it.
fail() {
  echo "  error: $*" >&2
  failures=$((failures + 1))
}

# check_licenses <dependency> <path> <gpl allowed: yes or no>: classifies every license file
# at the root of the dependency's sources.
check_licenses() {
  local licenses="" verdict=ok license_file license
  while IFS= read -r license_file; do
    [ -n "$license_file" ] || continue
    license=$(classify "$license_file")
    licenses="$licenses ${license_file##*/}=$license"
    case "$license" in
      MIT | Apache-2.0 | BSD | ISC) ;;
      GPL) [ "$3" = yes ] || verdict=rejected ;;
      *) verdict=rejected ;;
    esac
  done < <(find "$2" -maxdepth 1 -type f \
    \( -iname 'LICENSE*' -o -iname 'LICENCE*' -o -iname 'COPYING*' \) | sort)

  if [ -z "$licenses" ]; then
    fail "$1 has no license file at $2"
  elif [ "$verdict" = ok ]; then
    echo "  ok: $1:$licenses"
  else
    fail "$1 is not under an accepted license:$licenses ($2)"
  fi
}

for manifest in Packages/*/Package.swift; do
  [ -f "$manifest" ] || continue
  package=$(dirname "$manifest")
  gpl_allowed=no
  [ "$package" = "$gpl_package" ] && gpl_allowed=yes
  echo "$package"

  # Resolves and checks out every dependency, from the committed Package.resolved only: a
  # scan run alone must not move a pin. SwiftPM's workspace state then lists each
  # resolved dependency, local ones included, with where its sources are. The package graph
  # from `swift package show-dependencies` is not enough: it leaves out resolved packages
  # that no product uses, such as a dependency's macro implementation.
  memoshi_package_paths "$package"
  swift package "${swiftpm_args[@]}" --disable-automatic-resolution resolve
  resolved="$package/Package.resolved"
  state="$swiftpm_scratch/workspace-state.json"
  if [ ! -f "$state" ]; then
    if [ -f "$resolved" ]; then
      fail "$package pins dependencies, but SwiftPM recorded no checkouts in $state"
    else
      echo "  ok: no dependencies"
    fi
    continue
  fi

  # Every pin in Package.resolved must have been checked out, so that it is scanned below.
  if [ -f "$resolved" ]; then
    missing=$(/usr/bin/jq -r -n --slurpfile state "$state" --slurpfile resolved "$resolved" \
      '[$state[0].object.dependencies[].packageRef.identity] as $checked_out
        | $resolved[0].pins[].identity | select(IN($checked_out[]) | not)')
    for identity in $missing; do
      fail "$identity is pinned in $resolved but not checked out"
    done
  fi

  dependencies=$(/usr/bin/jq -r '.object.dependencies[] | [
      .packageRef.identity,
      .state.name,
      (.state.checkoutState.version // .state.checkoutState.branch
        // .state.checkoutState.revision // "local"),
      .packageRef.location,
      .subpath
    ] | @tsv' "$state")

  while IFS=$'\t' read -r identity kind version location subpath; do
    [ -n "$identity" ] || continue
    case "$kind" in
      sourceControlCheckout)
        path="$swiftpm_scratch/checkouts/$subpath"
        if [ ! -d "$path" ]; then
          fail "$identity $version has no checkout at $path"
          continue
        fi
        ;;
      fileSystem)
        path=$(cd "$location" 2>/dev/null && pwd -P) || path="$location"
        case "$path/" in
          "$repo_root/$gpl_package/")
            fail "$identity is $gpl_package, the GPL-3.0 module that only the iPhone and iPad app links (D69)"
            continue
            ;;
          "$repo_root"/*)
            echo "  ok: $identity is a local package in this repository"
            continue
            ;;
        esac
        ;;
      *)
        fail "$identity is resolved as '$kind', which this scan does not support"
        continue
        ;;
    esac
    checked=$((checked + 1))
    check_licenses "$identity $version" "$path" "$gpl_allowed"
  done <<<"$dependencies"
done

# Source-built MLS is not a SwiftPM checkout. D75's separately retained pinned Cargo/runtime
# provenance must also match, and every crate's declared licence must be on the accepted list
# or be one of D126's named exceptions; beyond that this is not a licence or release verdict.
echo "Packages/MemoshiMLS/Native (Cargo)"
if ! python3 scripts/memoshi-mls-payload-manifest.py \
  --toolchain "${MEMOSHI_MLS_RUST_TOOLCHAIN:-stable}" --check; then
  fail "native MLS payload or retained-license inventory drifted, or a crate's licence is not accepted"
fi

# The Python packages shipped with Pyodide: one reviewed row each, at the packaged version
# and licence-file digests, with a licence on the accepted list or a named exception, and
# with every retained licence text and piece of outside evidence unchanged (D126).
echo "Pyodide runtime (Python packages)"
if ! python3 scripts/check-pyodide-licenses.py; then
  fail "the reviewed table does not clear every Python package shipped with Pyodide"
fi

if [ "$failures" -gt 0 ]; then
  echo "error: $failures dependency license problem(s)" >&2
  exit 1
fi
echo "ok: $checked resolved dependencies carry accepted licenses"
