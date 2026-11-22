#!/usr/bin/env python3
"""Package S6's exact offline scientific closure; never downloads at app runtime.

python3 scripts/package-pyodide.py --allow-download
Use --cache DIRECTORY to reuse an existing cache. Existing bytes are checked, never
silently replaced. No pip/node installation, full-distribution download or extraction
of executable host tools. This is packaging, not scientific/device qualification.

The licence files that scripts/pyodide-licenses.json retains for a package (D126) are installed
beside the wheel's own licence files, under Licences/<package>/retained/, so that they travel
with the runtime into the apps (D133). The licence table locks them; the runtime manifest,
whose digest the app pins, does not list them and does not change.
"""

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile
import urllib.request
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts/lib"))
from license_policy import retained_files  # noqa: E402

VERSION = "314.0.7"
REVISION = "b1e4fcc2488962f6360a97f19b9982d6fdb5d16f"
CORE_SHA256 = "2abdcc2e35208af406e07724cffa85bc582ced97e9028383ecf5462541393f95"
CORE_URL = f"https://github.com/pyodide/pyodide/releases/download/{VERSION}/pyodide-core-{VERSION}.tar.bz2"
CDN = f"https://cdn.jsdelivr.net/pyodide/v{VERSION}/full/"
ROOTS = ("numpy", "pandas", "scipy", "matplotlib")
CORE_FILES = ("pyodide.mjs", "pyodide.asm.mjs", "pyodide.asm.wasm", "python_stdlib.zip", "pyodide-lock.json")
MAX_DOWNLOAD = 100_000_000
MAX_TOTAL = 180_000_000
LICENCES = (
    ("pyodide-LICENSE", f"https://raw.githubusercontent.com/pyodide/pyodide/{REVISION}/LICENSE", "1f256ecad192880510e84ad60474eab7589218784b9a50bc7ceee34c2b91f1d5"),
    ("cpython-LICENSE", "https://raw.githubusercontent.com/python/cpython/v3.14.2/LICENSE", "b0e25a78cffb43f4d92de8b61ccfa1f1f98ecbc22330b54b5251e7b6ba010231"),
    ("emscripten-LICENSE", "https://raw.githubusercontent.com/emscripten-core/emscripten/5.0.3/LICENSE", "620a78084fc7ca97c0b5dea9abf891f3ffcadfdbf305276f099c9c4e12fc1d86"),
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_name(name):
    path = PurePosixPath(name)
    if path.is_absolute() or not path.parts or any(p in ("", ".", "..") for p in path.parts) or "\\" in name:
        raise ValueError(f"unsafe archive name: {name}")
    return path


def obtain(cache, name, url, expected, allowed):
    target = cache / name
    if target.exists():
        data = target.read_bytes()
    else:
        if not allowed:
            raise SystemExit(f"missing pinned cache entry: {target}; use --allow-download explicitly")
        request = urllib.request.Request(url, headers={"User-Agent": "Memoshi-S6-packager/1"})
        with urllib.request.urlopen(request, timeout=90) as response:
            if response.geturl().split(":", 1)[0] != "https":
                raise ValueError("insecure download redirect")
            data = response.read(MAX_DOWNLOAD + 1)
        if len(data) > MAX_DOWNLOAD:
            raise ValueError(f"download exceeds {MAX_DOWNLOAD} bytes: {name}")
        if digest(data) != expected:
            raise ValueError(f"download digest mismatch: {name}")
        cache.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as output:
            output.write(data)
    if digest(data) != expected:
        raise ValueError(f"cache digest mismatch (not overwritten): {target}")
    return data


def install_retained_licences(output, root=ROOT):
    """Install every licence file the reviewed table retains into the runtime; return their paths.

    Each file is read from the repository and must have the digest the table records. Nothing
    is written unless all of them do, and an existing different file is never overwritten.
    """
    table = json.loads((Path(root) / "scripts/pyodide-licenses.json").read_text())
    planned = []
    for row in table["packages"]:
        files = retained_files(row)
        if not files:
            continue
        base = Path(row["retained"]["notice"]["path"]).parent
        for item in files:
            source = Path(root) / item["path"]
            if source.is_symlink() or not source.is_file() or digest(source.read_bytes()) != item["sha256"]:
                raise ValueError(f"retained licence file is missing or changed: {item['path']}")
            name = f"Licences/{row['package']}/retained/{Path(item['path']).relative_to(base).as_posix()}"
            planned.append((str(safe_name(name)), source.read_bytes()))
    for name, data in planned:
        path = Path(output) / name
        if path.exists():
            if path.is_symlink() or path.read_bytes() != data:
                raise ValueError(f"existing resource differs (not overwritten): {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("xb") as stream:
                stream.write(data)
    return sorted(name for name, _ in planned)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--allow-download", action="store_true")
    parser.add_argument("--cache", type=Path, default=Path(".build/pyodide-downloads"))
    parser.add_argument("--output", type=Path, default=Path("Packages/MemoshiApp/Sources/PyodideSpike/Resources/Runtime"))
    args = parser.parse_args()
    records = []
    total = 0

    def install(name, data, source):
        nonlocal total
        safe_name(name)
        total += len(data)
        if total > MAX_TOTAL:
            raise ValueError("offline closure exceeds the explicit packaging cap")
        path = args.output / name
        if path.exists():
            if path.is_symlink() or path.read_bytes() != data:
                raise ValueError(f"existing resource differs (not overwritten): {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("xb") as output:
                output.write(data)
        records.append({"path": name, "bytes": len(data), "sha256": digest(data), "source": source})

    core = obtain(args.cache, f"pyodide-core-{VERSION}.tar.bz2", CORE_URL, CORE_SHA256, args.allow_download)
    with tarfile.open(fileobj=io.BytesIO(core), mode="r:bz2") as archive:
        for name in CORE_FILES:
            member = archive.getmember("pyodide/" + name)
            if not member.isfile() or member.size > MAX_DOWNLOAD:
                raise ValueError(f"invalid core member: {name}")
            data = archive.extractfile(member).read()
            install(name, data, CORE_URL + "#pyodide/" + name)
            if name == "pyodide-lock.json":
                lock = json.loads(data)
    selected = set()

    def visit(name):
        name = name.lower().replace("_", "-")
        if name in selected:
            return
        selected.add(name)
        for dependency in lock["packages"][name]["depends"]:
            visit(dependency)

    for name in ROOTS:
        visit(name)
    packages = []
    for name in sorted(selected):
        package = lock["packages"][name]
        filename = package["file_name"]
        if len(safe_name(filename).parts) != 1 or not filename.endswith(".whl"):
            raise ValueError(f"unexpected scientific package format: {filename}")
        data = obtain(args.cache, filename, CDN + filename, package["sha256"], args.allow_download)
        install(filename, data, CDN + filename)
        notices = []
        with zipfile.ZipFile(io.BytesIO(data)) as wheel:
            for entry in wheel.infolist():
                if entry.is_dir():
                    continue
                parts = safe_name(entry.filename).parts
                leaf = parts[-1].lower()
                is_notice = any(term in leaf for term in ("license", "licence", "copying", "notice", "copyright"))
                is_metadata = leaf == "metadata" and any(p.endswith(".dist-info") for p in parts)
                if not (is_notice or is_metadata):
                    continue
                if entry.file_size > 2_000_000:
                    raise ValueError(f"unexpectedly large licence/metadata member: {entry.filename}")
                destination = "Licences/" + name + "/" + entry.filename
                install(destination, wheel.read(entry), CDN + filename + "#" + entry.filename)
                notices.append(destination)
        if not notices:
            raise ValueError(f"package contains no retained licence or metadata: {name}")
        packages.append({"name": name, "version": package["version"], "file": filename, "licences": notices})
        print(f"packaged {name} {package['version']}: {len(data)} bytes", flush=True)
    for name, url, sha256 in LICENCES:
        install("Licences/" + name, obtain(args.cache, name, url, sha256, args.allow_download), url)
    source_notice = (
        f"Memoshi S6 offline Pyodide {VERSION}\n"
        f"Unmodified runtime source: https://github.com/pyodide/pyodide/tree/{REVISION}\n"
        f"Release/core archive: {CORE_URL}\nSHA-256: {CORE_SHA256}\n"
        "Runtime files and scientific wheels are unmodified; only their dependency closure is selected.\n"
        "Pyodide is MPL-2.0; the MPL licence and source link are supplied here.\n"
        "CPython, Emscripten and each scientific wheel retain their own included terms.\n"
        "Wheel metadata and licence/copyright/notice files are retained under Licences/.\n"
        "See manifest.json for exact per-file origin, digest, size, package version and retained notices.\n"
        "This is a private spike payload, not a public redistribution/signing/compatibility clearance.\n"
    ).encode()
    install("SOURCE-NOTICE.txt", source_notice, "Memoshi packaging selection; upstream bytes unchanged")
    manifest = {"schema": 1, "pyodide": VERSION, "revision": REVISION, "python": lock["info"]["python"],
                "coreArchiveSHA256": CORE_SHA256, "packages": packages, "files": sorted(records, key=lambda r: r["path"]),
                "bundledBytes": total, "networkAtRuntime": "none for this scientific closure"}
    manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    manifest_path = args.output / "manifest.json"
    if manifest_path.exists():
        if manifest_path.is_symlink() or manifest_path.read_bytes() != manifest_bytes:
            raise ValueError("existing manifest differs (not overwritten)")
    else:
        with manifest_path.open("xb") as output:
            output.write(manifest_bytes)
    retained = install_retained_licences(args.output)
    print(json.dumps({"pyodide": VERSION, "packages": len(packages), "payloadBytes": total,
                      "manifestSHA256": digest(manifest_bytes), "retainedLicences": len(retained),
                      "output": str(args.output)}, sort_keys=True))


if __name__ == "__main__":
    main()
