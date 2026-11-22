"""D126: one licence rule for every dependency that is not a Swift package.

Swift packages are classified from their licence files by scripts/scan-licenses.sh. The Rust
crates of the MLS library (scripts/memoshi-mls-payload-manifest.py) and the Python packages
shipped with Pyodide (scripts/check-pyodide-licenses.py) declare SPDX expressions, which are
held here to the same accepted list: MIT, Apache-2.0, BSD and ISC. An unknown, unlisted,
missing or malformed licence fails. This is a gate, not a licence clearance.
"""

import hashlib
from pathlib import Path
import re

# BSD is the two- and three-clause licence, as in scan-licenses.sh; BSD-4-Clause is not accepted.
ACCEPTED = frozenset({"MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC"})
# D126's two named exceptions for Rust crates. Each holds for the crates named here and for no
# other: MPL-2.0 for the UniFFI crates (shipped unmodified, D75), and Unicode-3.0 for the one
# crate that needs it. A new crate under either licence fails until it is named here.
CRATE_EXCEPTIONS = {
    "MPL-2.0": frozenset({
        "uniffi", "uniffi_bindgen", "uniffi_core", "uniffi_internal_macros", "uniffi_macros",
        "uniffi_meta", "uniffi_pipeline", "uniffi_udl",
    }),
    "Unicode-3.0": frozenset({"unicode-ident"}),
}
# D126: the Python packages shipped with Pyodide that the user accepted by name, each with the
# licences outside the accepted list that it and the parts it bundles or compiles in are under.
# The reviewed table states the same sets for the reader, but only these decide: a row cannot
# grant itself an exception. LicenseRef names are texts without an SPDX identifier used here.
PYODIDE_EXCEPTIONS = {
    "numpy": frozenset({"0BSD", "Zlib", "CC0-1.0"}),
    "pillow": frozenset({"MIT-CMU"}),
    "scipy": frozenset({"Qhull"}),
    "matplotlib": frozenset({
        "LicenseRef-Matplotlib",    # its own agreement, based on the Python licence
        "Bitstream-Vera",           # DejaVu fonts
        "OFL-1.1",                  # STIX and Humor Sans fonts, AMS font metrics
        "LicenseRef-BaKoMa",        # Computer Modern TrueType fonts
        "LicenseRef-Yorick",        # gist/yorick colormaps
        "CC0-1.0",                  # JSXTools resize observer in mpl.js
        "LicenseRef-AGG-2.4",       # Anti-Grain Geometry, compiled in
        "Qhull",                    # Qhull, compiled in
        "FTL",                      # FreeType, compiled in
        "LicenseRef-Adobe-AFM",     # Adobe's notice for the 14 PDF core font metric files (in the wheel)
        "LicenseRef-Adobe-Utopia",  # Adobe Utopia font-metric files
    }),
}
# D126: 37 font-metric files in the matplotlib wheel for which no permission text was found, and
# which the owner accepted knowing that. The exception is held here, not in the table: it is
# for this package, this wheel build and exactly these files, by path and SHA-256. A 38th
# file, a changed digest, another build or another package does not have it. No licence is
# claimed for these files.
PYODIDE_ACCEPTED_WITHOUT_EVIDENCE = {
    "matplotlib": {
        "wheel": "matplotlib-3.10.8-cp314-cp314-pyemscripten_2026_0_wasm32.whl",
        "wheelSha256": "722857932f8f62eac64f8439af15c94d427f9fb945f9590cd242805c983d2d54",
        "files": {
            "matplotlib/mpl-data/fonts/afm/pagd8a.afm":
                "8e316b8a0c244e960ba9adba729cd9bca40d068f8fb85e1b98356a68ce29316c",
            "matplotlib/mpl-data/fonts/afm/pagdo8a.afm":
                "b2035075e632c7c27e8ad1b0f61df5cbde5a301893091be63523d35f0c12ef18",
            "matplotlib/mpl-data/fonts/afm/pagk8a.afm":
                "654b5f1cf96836a72f18c1ccc5a2834a5b2184e723c21794c75e37470a467485",
            "matplotlib/mpl-data/fonts/afm/pagko8a.afm":
                "623d70060e89b2aab3d4a05f851a09dc0091f82310a25f058ff64ce4d6758039",
            "matplotlib/mpl-data/fonts/afm/pbkd8a.afm":
                "665e68e89fdd8bd6398f61291ed8dec3efec7e0efe5a879598ef4fcce6124d47",
            "matplotlib/mpl-data/fonts/afm/pbkdi8a.afm":
                "2403a7a3ddf4893c9f6482cc7f5d6f5ad89a4e0ac970fa4fe8545346110c303e",
            "matplotlib/mpl-data/fonts/afm/pbkl8a.afm":
                "509a898ce27ac500e00c12d7d79ee62a9a2120915598733e37ac76f83886bf5e",
            "matplotlib/mpl-data/fonts/afm/pbkli8a.afm":
                "0168ac959da10dbb34a31fea396444ba0b1b4bcffc9692f8f0b3cc478d2aa62d",
            "matplotlib/mpl-data/fonts/afm/pcrb8a.afm":
                "ea3d534b651cec359273ef25e364c60dcd6ed0583c26ca5e59fc456b28d4c22f",
            "matplotlib/mpl-data/fonts/afm/pcrbo8a.afm":
                "b268379a397d41a043b5022dd3a928e46bdac4bb0ef50b53bd800db84e617c6d",
            "matplotlib/mpl-data/fonts/afm/pcrr8a.afm":
                "ee7c45af4121cf8139286ff3484e5264e871447f0cc9f9c26f0fbbc79c2eeedc",
            "matplotlib/mpl-data/fonts/afm/pcrro8a.afm":
                "34a133ed7b5d16487d700f0cbd8f92dd4399955d98fc9ded3045851718fb4128",
            "matplotlib/mpl-data/fonts/afm/phvb8a.afm":
                "340c783381e32fbbc034225b73eb64d38564a25f93d28697790dd3da1f9752f3",
            "matplotlib/mpl-data/fonts/afm/phvb8an.afm":
                "f1efe6c83f80424345eeaf5734b6f69bbebf957d9352bddae70a20fcb204d6c9",
            "matplotlib/mpl-data/fonts/afm/phvbo8a.afm":
                "f1f90146627e49663662b060f1f1728c9cab269f1d690e893cee8bbe133cc4f2",
            "matplotlib/mpl-data/fonts/afm/phvbo8an.afm":
                "69e551bd5e2bd79041bf1b91274306f191ee1f61d58ae22209892fb9aa669263",
            "matplotlib/mpl-data/fonts/afm/phvl8a.afm":
                "23231833e6e097e808eab1b412e659d8e2f397125f19e4a1f31aac874b7e7894",
            "matplotlib/mpl-data/fonts/afm/phvlo8a.afm":
                "b35d82f9e3672031c9fd455bba2a6b8f10630a21c86d2dd8f0e4530bea93a6e2",
            "matplotlib/mpl-data/fonts/afm/phvr8a.afm":
                "2adf0a69189db6cf3d10120adbd5f62689835040f1beba1e689cff44d4e2eabe",
            "matplotlib/mpl-data/fonts/afm/phvr8an.afm":
                "94be5f0074d1c0e0e5fac079987ec87ec0f5b679de6b8c9150afbf09ad9b4073",
            "matplotlib/mpl-data/fonts/afm/phvro8a.afm":
                "dcaa8adde7a3891e21205054ca7b925ffe2531d1365764f9f31385f255fe7f07",
            "matplotlib/mpl-data/fonts/afm/phvro8an.afm":
                "571f6b45fdd87dab0c63bb73fa78d2c73ebbc472a4f9f36437bc818b45f620fd",
            "matplotlib/mpl-data/fonts/afm/pncb8a.afm":
                "6a85dea5370342d41afe6b297e530990414a79fcd71e8ca3cfa8a825523460d7",
            "matplotlib/mpl-data/fonts/afm/pncbi8a.afm":
                "a42596d4c620cb4126bf0698b1a60968023f2dfaec2a60c0347bbb3e4d116a25",
            "matplotlib/mpl-data/fonts/afm/pncr8a.afm":
                "d02201d812def6bfbafd697939b4534dff7c50eadece6190f193ae057e642e4b",
            "matplotlib/mpl-data/fonts/afm/pncri8a.afm":
                "e51fa92d93a7687346f298d5e8c3f7022f9dd8e4d0611fdc6026f9cd08737d25",
            "matplotlib/mpl-data/fonts/afm/pplb8a.afm":
                "dc4cd46cd9d7af916de5e14b634d16f685aee7dac73918035d4b8968ea0a379f",
            "matplotlib/mpl-data/fonts/afm/pplbi8a.afm":
                "5fff6d56ca6fadc31eaf7392f2abddc23145aa90176199dec822f634703dd368",
            "matplotlib/mpl-data/fonts/afm/pplr8a.afm":
                "8a331be3dec50c9f6755d54c6f6d45ed6dfe72ef6c6fff67174a2b885a529fc9",
            "matplotlib/mpl-data/fonts/afm/pplri8a.afm":
                "f0a2136daadc514322fe176844b2e6347b65aacd13b4e48aaad3c57eded7e676",
            "matplotlib/mpl-data/fonts/afm/psyr.afm":
                "232b7c6a31380764e6df8a018f6a4ab5cb487fd90f7ead39b2e41e7eaf29dd1a",
            "matplotlib/mpl-data/fonts/afm/ptmb8a.afm":
                "6cbd5f035342e3f9d6d7866b9f1cf89c795725be1dcc42c93efa1da8a9d878c8",
            "matplotlib/mpl-data/fonts/afm/ptmbi8a.afm":
                "fbf522e9794a6854c71279284bffb51ad22be55b466b78054367b32ce607b34f",
            "matplotlib/mpl-data/fonts/afm/ptmr8a.afm":
                "20472c59c9b32728c2c2482cc38a3a848326ce5c975209496adf6cd4f64d9c45",
            "matplotlib/mpl-data/fonts/afm/ptmri8a.afm":
                "e3d7d0320e5f20682e67bae073fdacb7230ae793efe5b3d3b3bc02ceaa5c1a99",
            "matplotlib/mpl-data/fonts/afm/pzcmi8a.afm":
                "c32ba821611939ca17ad2975b4fccb9046a18a4ee41a2f752498feb641511b80",
            "matplotlib/mpl-data/fonts/afm/pzdr.afm":
                "3328cb027cca61175005fa1fd56de4fe17f7d0cbea3a4a8bfff1b6da6439c70c",
        },
    },
}
TOKEN = re.compile(r"\s*(\(|\)|/|[A-Za-z0-9.+-]+)")


def accepted(expression, also=()):
    """True when some reading of the SPDX expression needs only accepted licences.

    `A OR B` (and Cargo's older `A/B`) offers a choice and `A AND B` needs both. `A WITH X` is
    its own, unlisted licence. `also` names licences accepted for this one package. An absent
    or malformed expression raises ValueError: it is never read as accepted.
    """
    if not isinstance(expression, str) or not expression.strip():
        raise ValueError("missing licence expression")
    tokens, position = [], 0
    text = expression.rstrip()
    while position < len(text):
        match = TOKEN.match(text, position)
        if match is None:
            raise ValueError(f"malformed licence expression: {expression}")
        tokens.append("OR" if match[1] == "/" else match[1])
        position = match.end()

    def keyword(word):
        return bool(tokens) and tokens[0].upper() == word

    def identifier():
        if not tokens or tokens[0] in ("(", ")") or tokens[0].upper() in ("AND", "OR", "WITH"):
            raise ValueError(f"malformed licence expression: {expression}")
        return tokens.pop(0)

    def term():
        if tokens and tokens[0] == "(":
            tokens.pop(0)
            listed = alternatives()
            if not tokens or tokens.pop(0) != ")":
                raise ValueError(f"malformed licence expression: {expression}")
            return listed
        licence = identifier()
        if keyword("WITH"):
            tokens.pop(0)
            identifier()
            return False
        return licence in ACCEPTED or licence in also

    def conjunction():
        listed = term()
        while keyword("AND"):
            tokens.pop(0)
            listed = term() and listed
        return listed

    def alternatives():
        listed = conjunction()
        while keyword("OR"):
            tokens.pop(0)
            listed = conjunction() or listed
        return listed

    listed = alternatives()
    if tokens:
        raise ValueError(f"malformed licence expression: {expression}")
    return listed


def unaccepted_crates(packages):
    """The Cargo inventory entries, as `name@version (licence)`, that D126 does not accept."""
    problems = []
    for item in packages:
        also = {licence for licence, crates in CRATE_EXCEPTIONS.items() if item["name"] in crates}
        try:
            if not accepted(item.get("license"), also):
                problems.append(f"{item['name']}@{item['version']} ({item['license']})")
        except ValueError:
            problems.append(f"{item['name']}@{item['version']} (no readable licence expression)")
    return problems


def retained_files(row):
    """Every file in the repository that a table row pins by digest.

    These are the licence texts copied from the package's source release, the notice that
    records where they came from, and the outside evidence for parts that ship without a text.
    """
    retained = row.get("retained", {})
    files = list(retained.get("texts", []))
    if "notice" in retained:
        files.append(retained["notice"])
    for part in row.get("withoutLicenceText", []):
        files.extend(part.get("evidence", []))
    return files


def pyodide_table_problems(table, manifest, root):
    """Why the reviewed table (scripts/pyodide-licenses.json) does not clear the packaged runtime.

    `manifest` is the runtime's committed manifest.json and `root` the repository. Every package
    the runtime ships needs exactly one row, reviewed at the packaged version, whose evidence
    covers every licence file of that package at the packaged digest, and whose verdict is
    `accepted`. Its licence must be on the accepted list, or be covered by the exception that
    PYODIDE_EXCEPTIONS names for that package alone. A `not-accepted` or `review` row is an
    open decision and fails. Every file a row retains in the repository must be there
    unchanged. A part that the package ships without a licence text (`withoutLicenceText`)
    passes only when it is marked accepted and names retained outside evidence, or when its
    files are exactly the ones PYODIDE_ACCEPTED_WITHOUT_EVIDENCE holds for that package.
    """
    problems = []
    digests = {item["path"]: item["sha256"] for item in manifest["files"]}
    packaged = {item["name"]: item for item in manifest["packages"]}
    rows = {}
    for row in table["packages"]:
        if row["package"] in rows:
            problems.append(f"{row['package']}: more than one row")
        rows[row["package"]] = row
    for name in sorted(rows.keys() - packaged.keys()):
        problems.append(f"{name}: row for a package the runtime does not ship")
    for name, package in sorted(packaged.items()):
        row = rows.get(name)
        if row is None:
            problems.append(f"{name} {package['version']}: no reviewed licence row")
            continue
        if row["version"] != package["version"]:
            problems.append(f"{name}: reviewed at {row['version']}, packaged at {package['version']}")
            continue
        evidence = {item["path"]: item["sha256"] for item in row["evidence"]}
        for path in sorted(set(package["licences"]) - evidence.keys()):
            problems.append(f"{name}: {path} was not reviewed")
        for path, digest in sorted(evidence.items()):
            if digests.get(path) != digest:
                problems.append(f"{name}: {path} is not the file that was reviewed")
        for item in retained_files(row):
            relative = Path(item["path"])
            retained = root / relative
            if relative.is_absolute() or ".." in relative.parts or retained.is_symlink() or not retained.is_file() \
                    or hashlib.sha256(retained.read_bytes()).hexdigest() != item["sha256"]:
                problems.append(f"{name}: {item['path']} is missing or changed")
        unevidenced = [part for part in row.get("withoutLicenceText", []) if part.get("verdict") == "accepted-without-evidence"]
        for part in row.get("withoutLicenceText", []):
            if part not in unevidenced and (part.get("verdict") != "accepted" or not part.get("evidence")):
                problems.append(f"{name}: {part['part']}: no accepted permission evidence")
        held = PYODIDE_ACCEPTED_WITHOUT_EVIDENCE.get(name)
        if unevidenced or held is not None:
            claimed = [(item["path"], item["sha256"]) for part in unevidenced for item in part.get("files", [])]
            if held is None or digests.get(held["wheel"]) != held["wheelSha256"] or sorted(claimed) != sorted(held["files"].items()) \
                    or not all(part.get("files") for part in unevidenced):
                problems.append(f"{name}: the files accepted without permission evidence are not exactly the ones "
                                "the owner's decision (D126) names")
        named = PYODIDE_EXCEPTIONS.get(name, frozenset())
        declared = row.get("exceptions", {}).get("licences", [])
        if not isinstance(declared, list) or set(declared) != named:
            problems.append(f"{name}: the row's exceptions are not the ones D126 names for this package")
        licence, verdict = row["license"], row["verdict"]
        try:
            listed = accepted(licence, named)
        except ValueError:
            problems.append(f"{name}: no readable licence expression")
            continue
        if verdict not in ("accepted", "not-accepted", "review"):
            problems.append(f"{name}: unknown verdict {verdict}")
        elif verdict == "accepted" and not listed:
            problems.append(f"{name}: marked accepted, but {licence} is not on the accepted list")
        elif verdict == "not-accepted" and listed:
            problems.append(f"{name}: marked not-accepted, but {licence} is on the accepted list")
        elif verdict != "accepted":
            problems.append(f"{name} {row['version']}: verdict {verdict} ({licence})")
    return problems


def accepted_without_evidence(table):
    """What the scan must say in plain words: per package, how many files the owner accepted (D126)."""
    lines = []
    for row in table["packages"]:
        count = sum(len(part.get("files", [])) for part in row.get("withoutLicenceText", [])
                    if part.get("verdict") == "accepted-without-evidence")
        if count:
            lines.append(f"{row['package']}: {count} files accepted without permission evidence by the owner's decision (D126)")
    return lines
