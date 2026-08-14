#!/usr/bin/env python3
"""Set a top-level key in a JSONC file while preserving comments.

Usage:
  set_jsonc_key.py <file> <key> <value_json>
    Sets (or replaces) the top-level "<key>" to <value_json>,
    preserving // and /* */ comments and existing formatting.

Exit codes:
  0 - SET:       key written (new or replaced)
  0 - UNCHANGED: existing value already equals new value (no change)
  1 - ERROR:     invalid usage/input

This exists because read_jsonc.py + json.dump strips JSONC comments.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from read_jsonc import load_jsonc  # noqa: E402


def _skip_strings_and_comments(text, pos):
    """Advance pos past any string literal or comment at current position."""
    if pos >= len(text):
        return pos

    if text[pos] == '"':
        i = pos + 1
        while i < len(text):
            if text[i] == '\\':
                i += 2
                continue
            if text[i] == '"':
                return i + 1
            i += 1
        return i

    if text[pos:pos + 2] == '//':
        j = text.find('\n', pos)
        return j + 1 if j != -1 else len(text)

    if text[pos:pos + 2] == '/*':
        j = text.find('*/', pos + 2)
        return j + 2 if j != -1 else len(text)

    return pos


def _skip_ws_and_comments(text, pos):
    """Advance pos past whitespace and comments, but NOT string literals.

    Used to locate the start of a value after a key's colon — the value may
    itself begin with a quote, which we must not skip.
    """
    while pos < len(text):
        ch = text[pos]
        if ch in ' \t\n\r':
            pos += 1
            continue
        if text[pos:pos + 2] == '//':
            j = text.find('\n', pos)
            pos = j + 1 if j != -1 else len(text)
            continue
        if text[pos:pos + 2] == '/*':
            j = text.find('*/', pos + 2)
            pos = j + 2 if j != -1 else len(text)
            continue
        break
    return pos


def _find_balanced(text, open_pos):
    """Find the matching close for '{' or '[' at open_pos.

    Returns the position after the closing char, or -1 if unbalanced.
    """
    open_ch = text[open_pos]
    close_ch = '}' if open_ch == '{' else ']'
    depth = 0
    i = open_pos
    while i < len(text):
        next_i = _skip_strings_and_comments(text, i)
        if next_i != i:
            i = next_i
            continue
        ch = text[i]
        if ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return -1


def _find_value_end(text, start):
    """start points at the first non-whitespace char of a value.

    Returns the position after the value, or -1 if unparseable.
    """
    ch = text[start]
    if ch == '"':
        i = start + 1
        while i < len(text):
            if text[i] == '\\':
                i += 2
                continue
            if text[i] == '"':
                return i + 1
            i += 1
        return len(text)
    if ch in '{[':
        return _find_balanced(text, start)
    # scalar (number, bool, null): scan to next top-level ',' or '}'
    i = start
    while i < len(text):
        ni = _skip_strings_and_comments(text, i)
        if ni != i:
            i = ni
            continue
        if text[i] in ',}':
            return i
        i += 1
    return len(text)


def _find_top_level_key(text, key):
    """Return (value_start, value_end) for a top-level '"key":' entry, or None."""
    m = re.search(r'^\s*"' + re.escape(key) + r'"\s*:', text, re.MULTILINE)
    if not m:
        return None
    i = _skip_ws_and_comments(text, m.end())
    if i >= len(text):
        return None
    end = _find_value_end(text, i)
    if end == -1:
        return None
    return (i, end)


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <file> <key> <value_json>", file=sys.stderr)
        sys.exit(1)

    filepath, key, value_json = sys.argv[1], sys.argv[2], sys.argv[3]

    try:
        new_value = json.loads(value_json)
    except json.JSONDecodeError:
        print("ERROR: invalid value_json", end="")
        sys.exit(1)

    with open(filepath) as f:
        text = f.read()

    existing = load_jsonc(filepath)
    if key in existing and existing[key] == new_value:
        print("UNCHANGED", end="")
        return 0

    new_json = json.dumps(new_value, ensure_ascii=False)
    bounds = _find_top_level_key(text, key)

    if bounds is None:
        # No existing key — insert before the final closing brace.
        closing_pos = text.rfind('}')
        if closing_pos == -1:
            print("ERROR: invalid JSONC (no closing brace)", end="")
            sys.exit(1)

        closing_indent = ""
        eol = text.rfind('\n', 0, closing_pos)
        if eol != -1:
            ws = re.match(r'^(\s*)', text[eol + 1:closing_pos])
            if ws:
                closing_indent = ws.group(1)
        indent = closing_indent + "  "

        entry = f'\n{indent}"{key}": {new_json}'
        pre_close = text[:closing_pos].rstrip()
        needs_comma = (
            pre_close != ''
            and not pre_close.endswith('{')
            and not pre_close.endswith(',')
        )
        if needs_comma:
            new_text = pre_close + ',' + entry + '\n' + closing_indent + text[closing_pos:]
        else:
            new_text = text[:closing_pos] + entry + '\n' + closing_indent + text[closing_pos:]

        with open(filepath, 'w') as f:
            f.write(new_text)
        print("SET", end="")
        return 0

    value_start, value_end = bounds
    new_text = text[:value_start] + new_json + text[value_end:]
    with open(filepath, 'w') as f:
        f.write(new_text)
    print("SET", end="")
    return 0


if __name__ == '__main__':
    main()
