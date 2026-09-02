#!/usr/bin/env python3
"""Insert entries into the 'external_modules' section of a JSONC file while preserving all comments.

Usage:
  merge_modules_jsonc.py <jsonc_file> <entries_file>
    Reads entries from entries_file (a JSON object of module declarations)
    and merges each into the "external_modules" key of jsonc_file.
    Skips entries whose key already exists. Preserves JSONC comments.

Exit codes:
  0 - INSERTED:   one or more entries were inserted
  0 - SKIP_ALL:   all entries already exist (no change)
  0 - NO_MODULES: file has no external_modules section (created one)
  1 - ERROR:      other failure

This is the external_modules-section counterpart of merge_mcp_jsonc.py.
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
        return i

    # Single-line comment //
    if text[pos:pos + 2] == '//':
        n = text.find('\n', pos)
        return n + 1 if n != -1 else len(text)

    # Multi-line comment /* */
    if text[pos:pos + 2] == '/*':
        n = text.find('*/', pos + 2)
        return n + 2 if n != -1 else len(text)

    return pos


def _find_balanced_brace(text, open_pos):
    """Find matching closing brace. Returns position after '}', or -1."""
    assert text[open_pos] == '{'
    depth = 0
    i = open_pos
    while i < len(text):
        n = _skip_strings_and_comments(text, i)
        if n != i:
            i = n
            continue
        ch = text[i]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return -1


def _find_field_value_end(text, field):
    """Find value boundaries for top-level <field> key.
    Returns (value_start, value_end_exclusive) or None.
    """
    m = re.search(r'^\s*"' + re.escape(field) + r'"\s*:', text, re.MULTILINE)
    if not m:
        return None

    i = m.end()
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
        return None


def _entry_exists(section_text, key):
    """Check if key already exists as a top-level key in the JSON object section."""
    return bool(re.search(
        r'^\s*"' + re.escape(key) + r'"\s*:',
        section_text,
        re.MULTILINE
    ))


def _insert_before_close(text, mcp_end, entry_str):
    """Insert entry_str before the closing '}' at mcp_end-1."""
    return text[:mcp_end - 1] + entry_str + text[mcp_end - 1:]


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <jsonc_file> <entries_file>", file=sys.stderr)
        sys.exit(1)

    jsonc_path = sys.argv[1]
    entries_path = sys.argv[2]

    # Read entries to merge
    try:
        with open(entries_path) as f:
            entries = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        print(f"ERROR: cannot read entries file: {e}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(entries, dict) or not entries:
        print("SKIP_EMPTY")
        return 0

    # Read target JSONC file
    try:
        with open(jsonc_path) as f:
            text = f.read()
    except FileNotFoundError:
        print("ERROR: target file not found", file=sys.stderr)
        sys.exit(1)

    bounds = _find_field_value_end(text, "external_modules")
    if bounds is None:
        # No "external_modules" section — create one before the last closing brace.
        closing_pos = text.rfind('}')
        if closing_pos == -1:
            print("ERROR: invalid JSONC (no closing brace)", file=sys.stderr)
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

        # Build the modules entry WITHOUT trailing comma
        modules_content = json.dumps(entries, indent=2)
        modules_content = modules_content.replace('\n', '\n' + indent)
        modules_entry = '\n' + indent + '"external_modules": ' + modules_content + '\n' + closing_indent

        # Check if comma separator is needed between existing fields and new entry
        # pre_close = everything before closing '}', minus trailing whitespace
        pre_close = text[:closing_pos].rstrip()
        needs_comma = (
            pre_close != ''
            and not pre_close.endswith('{')
            and not pre_close.endswith(',')
        )

        if needs_comma:
            new_text = pre_close + ',' + modules_entry + text[closing_pos:]
        else:
            new_text = text[:closing_pos] + modules_entry + text[closing_pos:]

        with open(jsonc_path, 'w') as f:
            f.write(new_text)
        print("INSERTED (created)")
        return 0

    mod_start, mod_end = bounds
    inner_start = mod_start + 1
    inner_text = text[inner_start:mod_end - 1]

    # Determine indentation from the line containing the opening brace
    indent = "  "
    line_start = text.rfind('\n', 0, mod_start)
    if line_start != -1:
        line_prefix = text[line_start + 1:mod_start]
        ws = re.match(r'^(\s*)', line_prefix)
        if ws:
            indent = ws.group(1) + "  "

    inserted_count = 0
    skip_count = 0

    for key, value in entries.items():
        if _entry_exists(inner_text, key):
            skip_count += 1
            continue

        value_json = json.dumps(value, indent=2)

        # Check if modules section is effectively empty
        stripped = inner_text.strip()
        if not stripped or stripped in (',',):
            # Empty: insert first entry without leading comma
            closing_indent = "  "
            eol = text.rfind('\n', 0, mod_end - 1)
            if eol != -1:
                closing_line = text[eol + 1:mod_end - 1]
                ws = re.match(r'^(\s*)', closing_line)
                if ws:
                    closing_indent = ws.group(1)
            entry = f'\n{indent}"{key}": {value_json}\n{closing_indent}'
        else:
            # Non-empty: add comma before entry
            entry = f',\n{indent}"{key}": {value_json}'

        # Insert before closing brace
        text = text[:mod_end - 1] + entry + text[mod_end - 1:]
        # Update inner_text for subsequent key checks
        inner_text = text[inner_start:mod_end - 1 + len(entry)]
        mod_end += len(entry)
        inserted_count += 1

    with open(jsonc_path, 'w') as f:
        f.write(text)

    if inserted_count > 0:
        print(f"INSERTED ({inserted_count} entry/entries)")
    else:
        print(f"SKIP_ALL ({skip_count} already present)")
    return 0


if __name__ == '__main__':
    main()
