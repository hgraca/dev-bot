#!/usr/bin/env python3
"""Read a JSONC file, strip comments and trailing commas, output parsed JSON or a field.

Usage:
  read_jsonc.py <file>                          # dump entire object as JSON
  read_jsonc.py <file> <field>                  # get a single field's value
  read_jsonc.py <file> <field> <subfield>       # get nested value
"""

import json
import sys


def load_jsonc(path):
    """Read a JSONC file, strip comments and trailing commas (string-aware).

    A decode failure is re-raised as JSONDecodeError (same type, so callers
    that catch ValueError keep working) with the file path folded into the
    message: a bare "Expecting value: line 1 column 1" cannot tell a caller
    which of several candidate configs is malformed, and a BOM looks identical
    to an empty file. Opened as utf-8-sig so a BOM is not one of those causes.
    """
    with open(path, encoding="utf-8-sig") as f:
        raw = f.read()

    out = []
    i = 0
    while i < len(raw):
        # String literal — copy verbatim until unescaped quote
        if raw[i] == '"':
            j = i + 1
            while j < len(raw):
                if raw[j] == "\\":
                    j += 2  # skip escaped char
                elif raw[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            out.append(raw[i:j])
            i = j
            continue

        # Single-line comment //
        if raw[i : i + 2] == "//":
            j = raw.find("\n", i)
            if j == -1:
                break  # rest of file is comment
            i = j
            continue

        # Multi-line comment /* */
        if raw[i : i + 2] == "/*":
            j = raw.find("*/", i + 2)
            if j == -1:
                break  # unterminated comment
            # Blank the comment in place — same length, newlines kept — so
            # every later offset still maps to the source. Dropping it shifts
            # both the line and the column, and the decode error reports
            # against this text: a location that points elsewhere is worse
            # than none.
            comment = raw[i : j + 2]
            out.append("".join("\n" if ch == "\n" else " " for ch in comment))
            i = j + 2
            continue

        out.append(raw[i])
        i += 1

    text = "".join(_drop_trailing_commas(out))
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        raise json.JSONDecodeError(f"{path}: {exc.msg}", exc.doc, exc.pos) from None


def _drop_trailing_commas(tokens):
    """Remove a comma before a closing bracket, but only after a member."""
    cleaned = []
    for token in tokens:
        if token in ("]", "}"):
            previous = _previous_significant(cleaned, len(cleaned) - 1)
            if previous >= 0 and cleaned[previous] == ",":
                member = _previous_significant(cleaned, previous - 1)
                if member >= 0 and cleaned[member] not in (",", "[", "{"):
                    del cleaned[previous]
        cleaned.append(token)
    return cleaned


def _previous_significant(tokens, index):
    # `strip()` rather than `isspace()`: a token can be the empty string when a
    # stripped construct produced nothing, and `"".isspace()` is False — an
    # empty token would then be read as significant and hide a trailing comma.
    while index >= 0 and not tokens[index].strip():
        index -= 1
    return index


def main():
    if len(sys.argv) < 2:
        print("ERROR: usage: read_jsonc.py <file> [field ...]", file=sys.stderr)
        return 2
    path = sys.argv[1]
    try:
        data = load_jsonc(path)
    except json.JSONDecodeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    except UnicodeDecodeError as exc:
        # Raised by `open(encoding="utf-8-sig")` — neither a JSON nor an OS
        # error, so without this a non-UTF-8 config still dumps a traceback.
        print(
            f"ERROR: {path}: not valid UTF-8 (byte {exc.start}: {exc.reason})",
            file=sys.stderr,
        )
        return 2
    except OSError as exc:
        print(f"ERROR: {path}: {exc.strerror or exc}", file=sys.stderr)
        return 2

    if len(sys.argv) == 2:
        print(json.dumps(data))
        return

    val = data
    for key in sys.argv[2:]:
        if isinstance(val, dict):
            val = val.get(key, "")
        else:
            val = ""
    if isinstance(val, bool):
        print("true" if val else "false")
    elif isinstance(val, (dict, list)):
        print(json.dumps(val))
    else:
        print(val)


if __name__ == "__main__":
    raise SystemExit(main())
