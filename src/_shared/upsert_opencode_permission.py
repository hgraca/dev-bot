#!/usr/bin/env python3
"""Add "<path>/**": "allow" entries to the permission.external_directory map
in an opencode.jsonc file, preserving comments and formatting. Idempotent.

Used by the devbot-test harness scripts to grant the agent read/write access
to the dev-bot install, the opencode install, and the claudecode state dir.

Usage:
  upsert_opencode_permission.py <opencode.jsonc> <path> [<path>...]

Exit codes:
  0 — success, no-op (already present), or skipped (file/block absent)
  1 — error (unreadable file, unbalanced braces)
"""

import re
import sys


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 1

    path, entries = sys.argv[1], sys.argv[2:]
    try:
        src = open(path, encoding="utf-8").read()
    except FileNotFoundError:
        print(f"skip: {path} not found", file=sys.stderr)
        return 0
    except OSError as e:
        print(f"error: cannot read {path}: {e}", file=sys.stderr)
        return 1

    lines = src.split("\n")

    # Locate the permission.external_directory block (flat key/value map).
    block_open = None
    for i, ln in enumerate(lines):
        if re.search(r'"external_directory"\s*:\s*\{', ln):
            block_open = i
            break
    if block_open is None:
        print(f"skip: no permission.external_directory block in {path}", file=sys.stderr)
        return 0

    # The block holds only flat "key": "value" entries, so the first brace
    # line (allowing the trailing comma: "},") after the opening line closes
    # it — nested blocks like "bash": { … } are never inside external_directory.
    close_i = None
    for i in range(block_open + 1, len(lines)):
        if lines[i].strip() in ("}", "},"):
            close_i = i
            break
    if close_i is None:
        print(f"error: unbalanced braces in {path}", file=sys.stderr)
        return 1

    # Existing keys in the block (idempotency check).
    block_text = "\n".join(lines[block_open:close_i])
    existing = set(re.findall(r'"([^"]+)":\s*"(?:allow|deny|ask)"', block_text))

    indent = lines[close_i][: len(lines[close_i]) - len(lines[close_i].lstrip())]
    new_keys = []
    for key in entries:
        if key not in existing and key not in new_keys:
            new_keys.append(key)

    if new_keys:
        # The previous entry line has no trailing comma (it was last before the
        # closing brace) — add one so the inserted entries separate correctly.
        prev = close_i - 1
        if prev > block_open and not lines[prev].rstrip().endswith(","):
            lines[prev] = lines[prev].rstrip() + ","
        # No trailing comma on the LAST inserted line — read_jsonc.py feeds the
        # result to strict json.loads, which rejects trailing commas.
        new_lines = []
        for i, key in enumerate(new_keys):
            suffix = "," if i < len(new_keys) - 1 else ""
            new_lines.append(f'{indent}  "{key}": "allow"{suffix}')
        lines[close_i:close_i] = new_lines
        try:
            open(path, "w", encoding="utf-8").write("\n".join(lines))
        except OSError as e:
            print(f"error: cannot write {path}: {e}", file=sys.stderr)
            return 1
        print(f"added to external_directory: {', '.join(new_keys)}")
    else:
        print(f"already present: {', '.join(entries)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
