#!/usr/bin/env python3
"""D126: check the reviewed licence table for the Python packages shipped with Pyodide.

Compares scripts/pyodide-licenses.json with the committed manifest of the packaged runtime
(scripts/package-pyodide.py writes and verifies that manifest) and with the licence texts the
table retains under Packages/MemoshiApp/LicenseSources. No network and no runtime download.
scripts/scan-licenses.sh runs it.

With --bundle APP... it checks built apps instead (D133): an app that carries the Python
runtime must carry every retained licence text and piece of outside evidence inside that
runtime, unchanged. scripts/check-bundle.sh runs it.
"""
import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / "scripts/lib"))
from license_policy import accepted_without_evidence, pyodide_table_problems  # noqa: E402

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--bundle", nargs="+", type=Path, metavar="APP", help="built apps to check instead of the table")
args = parser.parse_args()
table = json.loads((root / "scripts/pyodide-licenses.json").read_text())
if args.bundle:
    from release_support import missing_runtime_licences  # The table check needs no release policy.
    failed = False
    for app in args.bundle:
        missing = missing_runtime_licences(app, table, root)
        for path in missing:
            print(f"  error: {app}: the Python runtime does not carry {path} unchanged", file=sys.stderr)
        failed = failed or bool(missing)
    raise SystemExit(1 if failed else 0)
manifest = json.loads((root / "Packages/MemoshiApp/Sources/PyodideSpike/Resources/Runtime/manifest.json").read_text())
problems = pyodide_table_problems(table, manifest, root)
for problem in problems:
    print(f"  error: {problem}", file=sys.stderr)
if problems:
    raise SystemExit(1)
print(f"  ok: {len(manifest['packages'])} Python packages shipped with Pyodide have reviewed, accepted licences")
for line in accepted_without_evidence(table):
    print(f"  note: {line}")
