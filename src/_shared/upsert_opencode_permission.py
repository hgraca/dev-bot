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


def _brace_block(text, key):
    """Return (open_idx, close_idx) of the {...} value for "key", scanning
    string- and comment-aware brace depth.

    The former close-finder assumed the closing brace sat alone on its own line;
    a compact/glued block (audit-65 FAIL-1) made it land on the *next* block's
    close, so the entry was judged "already present" and silently skipped. A
    plain brace count is not enough either: a `}` inside a `//` or `/* */`
    comment would end the block early, so comments are skipped too.
    """
    key_m = re.search(r'"' + re.escape(key) + r'"\s*:\s*\{', text)
    if not key_m:
        return None
    start = key_m.end() - 1  # index of the opening '{'
    depth = 0
    in_str = False
    escaped = False
    in_line_comment = False
    in_block_comment = False
    i = start
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
        elif in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 1
        elif in_str:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_str = False
        elif ch == "/" and nxt == "/":
            in_line_comment = True
            i += 1
        elif ch == "/" and nxt == "*":
            in_block_comment = True
            i += 1
        elif ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return start, i
        i += 1
    return None


def _line_indent(text, index):
    """Leading whitespace of the line containing `index`."""
    line_start = text.rfind("\n", 0, index) + 1
    prefix = text[line_start:index]
    return prefix[: len(prefix) - len(prefix.lstrip())]


def _entry_indent(inner):
    """Indent of the block's first entry line, or 4 spaces for a one-liner."""
    match = re.search(r'\n([ \t]+)"', inner)
    return match.group(1) if match else "    "


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

    block = _brace_block(src, "external_directory")
    if block is None:
        print(f"skip: no permission.external_directory block in {path}", file=sys.stderr)
        return 0
    open_idx, close_idx = block

    inner = src[open_idx + 1 : close_idx]
    existing = set(re.findall(r'"([^"]+)":\s*"(?:allow|deny|ask)"', inner))

    new_keys = []
    for key in entries:
        if key not in existing and key not in new_keys:
            new_keys.append(key)

    if not new_keys:
        print(f"already present: {', '.join(entries)}")
        return 0

    indent = _entry_indent(inner)
    # Capture the block's trailing whitespace before touching body's length.
    body = inner.rstrip()
    tail = inner[len(body) :]
    # The previous entry line has no trailing comma (it was last before the
    # closing brace) — add one so the inserted entries separate correctly. A
    # block that already ends with a comma (e.g. a compact one-liner) needs none.
    if body and not body.endswith(","):
        body += ","

    added_lines = []
    for i, key in enumerate(new_keys):
        # No trailing comma on the LAST inserted line — read_jsonc.py feeds the
        # result to strict json.loads, which rejects trailing commas.
        suffix = "," if i < len(new_keys) - 1 else ""
        added_lines.append(f'{indent}"{key}": "allow"{suffix}')
    addition = "\n" + "\n".join(added_lines)

    if "\n" not in tail:
        # A glued close ("…allow"}") has no line of its own — give the brace one
        # so the file stays well-formed and re-readable.
        tail = "\n" + _line_indent(src, open_idx)

    out = src[: open_idx + 1] + body + addition + tail + src[close_idx :]
    try:
        open(path, "w", encoding="utf-8").write(out)
    except OSError as e:
        print(f"error: cannot write {path}: {e}", file=sys.stderr)
        return 1
    print(f"added to external_directory: {', '.join(new_keys)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
