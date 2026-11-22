#!/usr/bin/env python3
"""Describe the actual generated MLS payload; never asserts a test/audit/device pass."""
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
modes = parser.add_mutually_exclusive_group()
modes.add_argument("--check", action="store_true", help="Verify the existing source/payload inventory without rewriting it")
modes.add_argument("--bundle-notices", type=Path, metavar="DIR", help="Verify copied MLS notices in an app's resource directory; no payload inventory rewrite")
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
package = root / "Packages/MemoshiMLS"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_license_files(base, inventory):
    for entry in inventory["packages"]:
        if not entry.get("license") or not entry.get("files"):
            raise SystemExit("MLS dependency lacks retained license evidence: " + entry["name"])
        for record in entry["files"]:
            relative = Path(record["path"])
            if relative.is_absolute() or ".." in relative.parts:
                raise SystemExit("Unsafe MLS retained-license path")
            retained = base / relative
            if retained.is_symlink() or not retained.is_file() or digest(retained) != record["sha256"]:
                raise SystemExit("MLS license evidence missing or changed: " + str(retained))


def retained_license_inventory():
    inventory = json.loads((package / "Native/Licenses/manifest.json").read_bytes())
    if inventory.get("format") != 1 or inventory.get("cargo_lock_sha256") != digest(package / "Native/Cargo.lock"):
        raise SystemExit("MLS retained-license inventory does not match Cargo.lock")
    verify_license_files(package / "Native/Licenses", inventory)
    return inventory


def verify_license_inventory():
    inventory = retained_license_inventory()
    metadata = json.loads(subprocess.check_output([
        "rustup", "run", args.toolchain, "cargo", "metadata", "--locked", "--offline",
        "--format-version", "1", "--manifest-path", str(package / "Native/Cargo.toml"),
    ]))
    own = {"memoshi-mls-native", "memoshi-mls-bindgen"}
    expected = {
        (item["name"], item["version"], item.get("source"), item.get("license"))
        for item in metadata["packages"]
        if not (item["name"] in own and item.get("source") is None)
    }
    retained = [
        (item["name"], item["version"], item.get("source"), item.get("license"))
        for item in inventory["packages"]
    ]
    if len(retained) != len(set(retained)) or set(retained) != expected:
        raise SystemExit("MLS retained-license inventory must cover the exact offline Cargo graph")
    # D126: every crate is held to the Swift packages' accepted list, with two named exceptions.
    refused = unaccepted_crates(inventory["packages"])
    if refused:
        raise SystemExit("MLS dependencies under a licence the accepted list (D126) does not cover: " + ", ".join(refused))
    path = package / "Native/Licenses/manifest.json"
    return {"path": "../Native/Licenses/manifest.json", "sha256": digest(path)}


def verify_bundle_notices(base):
    if not base.is_dir() or base.is_symlink():
        raise SystemExit("Bundled MLS notice directory is missing or linked")
    if any(path.is_symlink() for path in base.rglob("*")):
        raise SystemExit("Bundled MLS notices must not depend on filesystem links")
    inventory = retained_license_inventory()
    sources = {
        "NOTICE": package / "Sources/MemoshiMLSNativeBindings/NOTICE",
        "PROVENANCE.json": package / "Native/PROVENANCE.json",
        "Licenses/manifest.json": package / "Native/Licenses/manifest.json",
    }
    for relative, source in sources.items():
        bundled = base / relative
        if not bundled.is_file() or bundled.read_bytes() != source.read_bytes():
            raise SystemExit("Bundled MLS notice is missing or changed: " + relative)
    verify_license_files(base / "Licenses", inventory)


if args.bundle_notices:
    verify_bundle_notices(args.bundle_notices)
    print("Verified bundled native MLS notices against the retained source inventory")
    raise SystemExit(0)

inputs = []
for tree in (package / "Native", package / "Sources/MemoshiMLS"):
    for path in sorted(tree.rglob("*")):
        if path.is_file() and (path.suffix in {".rs", ".swift", ".toml", ".h", ".c", ".cc", ".cpp", ".m", ".mm", ".modulemap", ".udl"} or path.name == "Cargo.lock"):
            inputs.append({"path": str(path.relative_to(root)), "sha256": digest(path)})
for path in (package / "Package.swift", package / "Native/PROVENANCE.json",
             root / "scripts/build-memoshi-mls.sh", root / "scripts/retain-memoshi-mls-licenses.py"):
    inputs.append({"path": str(path.relative_to(root)), "sha256": digest(path)})
outputs = []
for tree in (package / "Artifacts/MemoshiMLSNativeFFI.xcframework",
             package / "Sources/MemoshiMLSNativeBindings", package / "Generated/include"):
    if not tree.is_dir():
        raise SystemExit("Required MLS output absent: " + str(tree.relative_to(root)))
    for path in sorted(tree.rglob("*")):
        if path.is_file():
            outputs.append({"path": str(path.relative_to(root)), "sha256": digest(path)})
manifest = {
    "format": 1,
    "mls_revision": "a1436f4a5433214ed62349e77835b57a0accdc42",
    "mls_version": "0.57.0", "cryptokit_provider_version": "0.11.0", "uniffi_version": "0.32.2",
    "cipher_suite": "0x0001", "targets": ["aarch64-apple-darwin", "aarch64-apple-ios", "aarch64-apple-ios-sim"],
    "tools": {
        "rustc": subprocess.check_output(["rustup", "run", args.toolchain, "rustc", "--version"], text=True).strip(),
        "swift": subprocess.check_output(["xcrun", "swiftc", "--version"], text=True).strip(),
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
    },
    "inputs": inputs, "outputs": outputs,
    "licenses": verify_license_inventory(),
    "qualification": "Source build payload only; not a test, audit, signing, physical-device, cloud, or release result",
}
path = package / "Artifacts/payload-manifest.json"
content = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
if args.check:
    if not path.is_file() or path.read_bytes() != content:
        raise SystemExit("MLS payload/source inventory drifted; rebuild the pinned payload before qualification")
    print("Verified MLS payload/source hashes and retained license evidence (not a qualification verdict)")
else:
    if not path.exists() or path.read_bytes() != content:
        path.write_bytes(content)
    print("Recorded immutable MLS source and generated payload digests")
