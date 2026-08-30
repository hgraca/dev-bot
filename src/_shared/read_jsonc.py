#!/usr/bin/env python3
"""Read a JSONC file, strip comments, output parsed JSON or a specific field.

Usage:
  read_jsonc.py <file>                          # dump entire object as JSON
  read_jsonc.py <file> <field>                  # get a single field's value
  read_jsonc.py <file> <field> <subfield>       # get nested value
"""

import json
import sys


def load_jsonc(path):
    """Read a JSONC file, strip // and /* */ comments (string-aware)."""
    with open(path) as f:
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
            i = j + 2
            continue

        out.append(raw[i])
        i += 1

    return json.loads("".join(out))


def main():
    path = sys.argv[1]
    data = load_jsonc(path)

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
    main()
