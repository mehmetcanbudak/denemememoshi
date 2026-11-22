"""Whether MemoshiCore's Package.swift builds the pinned Pi_Swift checkout alone (D134).

The manifest is Swift, so it is read as Swift: comments (`//` and nested `/* */`) are removed
and string literals are kept whole, so the `//` of "https://..." is never taken for a comment.
Every `.package(` call left in the active code must start with one plain `path:` or `url:`
string literal and name either the pinned checkout (exactly once) or a reviewed dependency; a
call that cannot be read that way is refused, never skipped. Packages are matched by location,
so a second Pi_Swift under another name is refused as well.

Used by scripts/check-prerequisites.sh, as `python3 scripts/lib/pi_swift_manifest.py MANIFEST
PINNED_PATH` (exit 1 with the reasons on stderr), and by scripts/release.py through problems().
"""

import re
import sys

# MemoshiCore's reviewed dependencies besides Pi_Swift, by kind and location. Adding a
# dependency to the manifest means adding it here; anything else is refused, whatever its name.
REVIEWED_PACKAGES = frozenset({
    ("path", "../MemoshiProtocol"),
    ("url", "https://github.com/apple/swift-nio"),
    ("url", "https://github.com/apple/swift-nio-ssl"),
})

_STRING_OPEN = re.compile(r'(#*)("""|")')
_PACKAGE = re.compile(r"\.package\s*\(")
_LOCATION = re.compile(r'\.package\s*\(\s*(path|url)\s*:\s*"#(\d+)"')


class ManifestError(ValueError):
    pass


def _literal(text, start, literals):
    """Reads the string literal at `start`; returns its end. Appends its value to `literals`, or
    None for a value that is not plain text (multi-line, escapes or interpolation)."""
    opening = _STRING_OPEN.match(text, start)
    hashes, quote = opening.group(1), opening.group(2)
    multi_line = quote == '"""'
    closing, escape = quote + hashes, "\\" + hashes
    index, plain, characters = opening.end(), not multi_line, []
    while True:
        if index >= len(text) or (not multi_line and text[index] == "\n"):
            raise ManifestError("unterminated string literal")
        if text.startswith(closing, index):
            literals.append("".join(characters) if plain else None)
            return index + len(closing)
        if text.startswith(escape, index):
            index += len(escape)
            if text.startswith("(", index):
                index = _code(text, index + 1, [], interpolation=True)[1]
            else:
                index += 1
            plain = False
            continue
        characters.append(text[index])
        index += 1


def _code(text, index, literals, interpolation=False):
    """The active code from `index`: comments become spaces (newlines kept) and every string
    literal becomes the placeholder "#N", N its index in `literals`. Inside an interpolation it
    stops after the parenthesis that closes it. Returns (code, end)."""
    pieces, depth = [], 0
    while index < len(text):
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = len(text) if end < 0 else end
            pieces.append(" " * (end - index))
            index = end
        elif text.startswith("/*", index):
            end, nesting = index + 2, 1
            while nesting:
                if end >= len(text):
                    raise ManifestError("unterminated block comment")
                if text.startswith("/*", end):
                    nesting, end = nesting + 1, end + 2
                elif text.startswith("*/", end):
                    nesting, end = nesting - 1, end + 2
                else:
                    end += 1
            pieces.append(re.sub(r"[^\n]", " ", text[index:end]))
            index = end
        elif _STRING_OPEN.match(text, index):
            end = _literal(text, index, literals)
            pieces.append(f'"#{len(literals) - 1}"' + "\n" * text.count("\n", index, end))
            index = end
        elif interpolation and text[index] in "()":
            if text[index] == ")" and depth == 0:
                return "".join(pieces), index + 1
            depth += 1 if text[index] == "(" else -1
            pieces.append(text[index])
            index += 1
        else:
            pieces.append(text[index])
            index += 1
    if interpolation:
        raise ManifestError("unterminated string interpolation")
    return "".join(pieces), index


def packages(text):
    """[(line, kind, location)] for every `.package(` call in the active code; kind and location
    are None for a call that does not start with one plain path: or url: string literal."""
    literals = []
    code = _code(text, 0, literals)[0]
    result = []
    for call in _PACKAGE.finditer(code):
        line = code.count("\n", 0, call.start()) + 1
        location = _LOCATION.match(code, call.start())
        value = literals[int(location.group(2))] if location else None
        result.append((line, location.group(1), value) if value is not None else (line, None, None))
    return result


def problems(text, pinned):
    """Why the manifest `text` does not build the checkout at path `pinned` alone; [] if it does."""
    try:
        found = packages(text)
    except ManifestError as error:
        return [f"the manifest cannot be read: {error}"]
    result, pins = [], 0
    for line, kind, location in found:
        if kind is None:
            result.append(f"line {line}: a .package( call that does not start with one plain path: or url: string")
        elif (kind, location) == ("path", pinned):
            pins += 1
        elif (kind, location) not in REVIEWED_PACKAGES:
            result.append(f'line {line}: .package({kind}: "{location}") is neither the pinned Pi_Swift checkout '
                          "nor a reviewed dependency in scripts/lib/pi_swift_manifest.py")
    if pins != 1:
        result.append(f'.package(path: "{pinned}") appears {pins} times in the active code, not once')
    return result


def main(arguments):
    if len(arguments) != 2:
        print("usage: pi_swift_manifest.py MANIFEST PINNED_PATH", file=sys.stderr)
        return 64
    manifest, pinned = arguments
    try:
        with open(manifest, encoding="utf-8") as stream:
            text = stream.read()
    except (OSError, UnicodeError) as error:
        print(f"error: {manifest}: {error}", file=sys.stderr)
        return 1
    found = problems(text, pinned)
    for problem in found:
        print(f"error: {manifest}: {problem}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
