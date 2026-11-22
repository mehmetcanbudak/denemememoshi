#!/usr/bin/env python3
"""Retain source licenses for the exact Cargo graph, including build-only tooling."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from license_policy import unaccepted_crates  # noqa: E402

parser = argparse.ArgumentParser()
parser.add_argument("--toolchain", default="1.97.0")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
native = root / "Packages/MemoshiMLS/Native"
result = subprocess.run(
    ["rustup", "run", args.toolchain, "cargo", "metadata", "--locked", "--format-version", "1",
     "--manifest-path", str(native / "Cargo.toml")], check=True, stdout=subprocess.PIPE)
metadata = json.loads(result.stdout)
# D126, before anything is retained or installed: a crate under a licence the accepted list
# does not cover stops the build while the package still holds the previous payload.
refused = unaccepted_crates([
    package for package in metadata["packages"]
    if not (package["name"] in {"memoshi-mls-native", "memoshi-mls-bindgen"} and package.get("source") is None)])
if refused:
    raise SystemExit("MLS dependencies under a licence the accepted list (D126) does not cover: " + ", ".join(refused))
output = native / "Licenses"
output.mkdir(parents=True, exist_ok=True)


def retain(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_bytes() != content:
        path.write_bytes(content)


entries = []
missing = []
for package in sorted(metadata["packages"], key=lambda p: (p["name"], p["version"], p["id"])):
    if package["name"] in {"memoshi-mls-native", "memoshi-mls-bindgen"} and package.get("source") is None:
        continue
    crate = Path(package["manifest_path"]).parent
    candidates = []
    if package.get("license_file"):
        candidates.append(crate / package["license_file"])
    # Upstream mls-rs keeps dual licenses in the immutable workspace root.
    for directory in (crate, crate.parent):
        local = [path for path in directory.iterdir() if path.is_file() and (
            path.name.upper().startswith(("LICENSE", "LICENCE", "COPYING", "COPYRIGHT", "NOTICE", "AUTHORS")))]
        if local:
            candidates.extend(sorted(local))
            break
    license_source = "published source license/notice"
    # These published crates omit standalone license files; retain their actual
    # immutable workspace text or exact source declaration, never an invented grant.
    if not candidates and package["name"].startswith("uniffi") and package["version"] == "0.32.2":
        candidates.append(native / "LicenseSources/uniffi-0.32.2/LICENSE")
        license_source = "mozilla/uniffi-rs@7bc621ee9d0d15371d792612707ba5ed4111f950/LICENSE"
    if not candidates and package["name"] == "debug_tree" and package["version"] == "0.4.0":
        candidates.append(crate / "Cargo.toml.orig")
        candidates.extend(sorted((native / "LicenseSources/debug_tree-0.4.0").iterdir()))
        license_source = "MIT declaration in published Cargo.toml.orig; no standalone upstream license file"
    files = []
    seen = set()
    for source in candidates:
        if not source.is_file() or source.resolve() in seen:
            continue
        seen.add(source.resolve())
        name = f"{package['name']}-{package['version']}/{source.name}"
        content = source.read_bytes()
        retain(output / name, content)
        files.append({"path": name, "sha256": hashlib.sha256(content).hexdigest()})
    if not files:
        missing.append(f"{package['name']}@{package['version']}")
    entries.append({"name": package["name"], "version": package["version"],
                    "source": package.get("source"), "license": package.get("license"),
                    "repository": package.get("repository"), "license_source": license_source, "files": files})
if missing:
    raise SystemExit("License source unavailable for: " + ", ".join(missing))
manifest = {"format": 1, "scope": "Cargo.lock complete graph; runtime and build tooling",
            "cargo_lock_sha256": hashlib.sha256((native / "Cargo.lock").read_bytes()).hexdigest(),
            "packages": entries}
retain(output / "manifest.json", (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode())
print(f"Retained source licenses for {len(entries)} pinned Cargo packages")
