#!/usr/bin/env python3
"""Insert an MCP server entry into a JSONC file while preserving all comments.

Usage:
  merge_mcp_jsonc.py <file> <key> <value_json>
    Inserts key-value pair into the mcp section of the JSONC file,
    preserving all JSONC comments (// and /* */).

Exit codes:
  0 - INSERTED:   entry was inserted
  0 - SKIP_EXISTS: entry already exists (no change)
  1 - ERROR:      other failure

This exists because read_jsonc.py | jq strips JSONC comments.
"""

import json
import re
import sys


def _skip_strings_and_comments(text, pos):
    """Advance pos past any string literal or comment at current position.
    Returns the new position. If no string/comment starts here, returns pos unchanged.
    """
    if pos >= len(text):
        return pos

    # String literal
    if text[pos] == '"':
        i = pos + 1
        while i < len(text):
            if text[i] == '\\':
                i += 2
                continue
            if text[i] == '"':
                return i + 1
            i += 1
        return i  # unterminated string — return end

    # Single-line comment //
    if text[pos:pos + 2] == '//':
        j = text.find('\n', pos)
        return j + 1 if j != -1 else len(text)

    # Multi-line comment /* */
    if text[pos:pos + 2] == '/*':
        j = text.find('*/', pos + 2)
        return j + 2 if j != -1 else len(text)

    return pos


def _find_balanced_brace(text, open_pos):
    """Find the matching closing brace for the opening brace at open_pos.
    Returns the position of the closing brace + 1, or -1 if unbalanced.
    """
    assert text[open_pos] == '{', "must start at '{'"
    depth = 0
    i = open_pos
    while i < len(text):
        next_i = _skip_strings_and_comments(text, i)
        if next_i != i:
            i = next_i
            continue

        ch = text[i]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return i + 1  # position after closing }
        i += 1

    return -1  # unbalanced


def _find_mcp_value_end(text):
    """Find the boundaries of the value for the top-level 'mcp' key.

    Returns (value_start, value_end_exclusive) where value_start is the
    position of '{' and value_end is the position after the matching '}'.
    Returns None if no top-level 'mcp' key found.
    """
    # Match "mcp" as a top-level key: preceded by { or , or whitespace at line start
    # We use a regex anchored to find "mcp": after non-string content
    mcp_match = re.search(r'^\s*"mcp"\s*:', text, re.MULTILINE)
    if not mcp_match:
        return None

    # Find the opening brace after the colon
    i = mcp_match.end()
    while i < len(text):
        i = _skip_strings_and_comments(text, i)
        if i >= len(text):
            return None
        if text[i] == '{':
            end = _find_balanced_brace(text, i)
            if end == -1:
                return None
            return (i, end)
        if text[i] in ' \t\n\r,':
            i += 1
            continue
        # mcp value is not an object — shouldn't happen
        return None


def _entry_exists(mcp_section, key):
    """Check if the key already exists in the mcp JSON object section."""
    return bool(re.search(
        r'^\s*"' + re.escape(key) + r'"\s*:',
        mcp_section,
        re.MULTILINE
    ))


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <file> <key> <value_json>", file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]
    key = sys.argv[2]
    value_json = sys.argv[3]

    # Validate value_json is parseable
    try:
        _ = json.loads(value_json)
    except json.JSONDecodeError:
        print("ERROR: invalid value_json", end="")
        sys.exit(1)

    with open(filepath) as f:
        text = f.read()

    bounds = _find_mcp_value_end(text)
    if bounds is None:
        # No "mcp" section — create one before the last closing brace.
        closing_pos = text.rfind('}')
        if closing_pos == -1:
            print("ERROR: invalid JSONC (no closing brace)", end="")
            sys.exit(1)

        # Determine indentation from the line containing the closing brace
        closing_indent = ""
        eol = text.rfind('\n', 0, closing_pos)
        if eol != -1:
            closing_line = text[eol + 1:closing_pos]
            ws = re.match(r'^(\s*)', closing_line)
            if ws:
                closing_indent = ws.group(1)

        indent = closing_indent + "  "

        # Build the mcp entry — insert {"<key>": <value_json>}
        mcp_value = json.dumps({key: json.loads(value_json)}, indent=2)
        mcp_value = mcp_value.replace('\n', '\n' + indent)
        mcp_entry = '\n' + indent + '"mcp": ' + mcp_value + '\n' + closing_indent

        # Check if comma separator is needed between existing fields and new entry
        pre_close = text[:closing_pos].rstrip()
        needs_comma = (
            pre_close != ''
            and not pre_close.endswith('{')
            and not pre_close.endswith(',')
        )

        if needs_comma:
            new_text = pre_close + ',' + mcp_entry + text[closing_pos:]
        else:
            new_text = text[:closing_pos] + mcp_entry + text[closing_pos:]

        with open(filepath, 'w') as f:
            f.write(new_text)
        print("INSERTED", end="")
        return 0

    mcp_start, mcp_end = bounds

    # Extract just the text between { and } including braces
    mcp_inner_start = mcp_start + 1
    mcp_content = text[mcp_inner_start:mcp_end - 1]

    # Check if key already exists in the mcp section
    if _entry_exists(mcp_content, key):
        print("SKIP_EXISTS", end="")
        return 0

    # Determine indentation from the first line of the mcp section
    # Look for the line that has '{' to detect indentation
    indent = "  "
    line_start = text.rfind('\n', 0, mcp_start)
    if line_start != -1:
        line_prefix = text[line_start + 1:mcp_start]
        # If the mcp opening brace has indentation, use that + 2 spaces
        ws_match = re.match(r'^(\s+)', line_prefix)
        if ws_match:
            indent = ws_match.group(1) + "  "

    # Check if mcp section is empty (just whitespace between braces)
    stripped = mcp_content.strip()
    if not stripped or stripped in (',',):
        # Empty mcp: insert first entry without leading comma
        entry = f'\n{indent}"{key}": {value_json}\n'
        # Adjust indentation for closing brace by finding its line's whitespace
        closing_indent = "  "
        eol_before_close = text.rfind('\n', 0, mcp_end - 1)
        if eol_before_close != -1:
            closing_line = text[eol_before_close + 1:mcp_end - 1]
            ws_match = re.match(r'^(\s*)', closing_line)
            if ws_match:
                closing_indent = ws_match.group(1)
        entry = f'\n{indent}"{key}": {value_json}\n{closing_indent}'
    else:
        # Non-empty: add comma before the new entry
        entry = f',\n{indent}"{key}": {value_json}'

    # Insert before the closing }
    new_text = text[:mcp_end - 1] + entry + text[mcp_end - 1:]

    with open(filepath, 'w') as f:
        f.write(new_text)

    print("INSERTED", end="")
    return 0


if __name__ == '__main__':
    main()
