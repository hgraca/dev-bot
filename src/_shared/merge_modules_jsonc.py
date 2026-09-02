#!/usr/bin/env python3
"""Edit the 'external_modules' section of a JSONC file while preserving comments.

Usage:
  merge_modules_jsonc.py <jsonc_file> <entries_file>          # insert missing entries
  merge_modules_jsonc.py <jsonc_file> --remove <key>          # remove one entry
  merge_modules_jsonc.py <jsonc_file> --update <entries_file> # update declared entries

Insert mode:
  Reads entries from entries_file (a JSON object of module declarations)
  and merges each into the "external_modules" key of jsonc_file.
  Skips entries whose key already exists. Preserves JSONC comments.

Remove mode:
  Removes the entry with the given key. Prints REMOVED or NOT_FOUND.

Update mode:
  For each key in entries_file that already exists, replaces the entry with
  the declaration merged over the existing value: keys present in the
  declaration (url, paths) win, any other existing keys (e.g. a user-added
  local `path`) are preserved. Entries not present are left untouched (use
  insert mode to add them). Prints UPDATED (n) or SKIP_ALL.

Exit codes:
  0 - success (INSERTED / SKIP_ALL / REMOVED / NOT_FOUND / UPDATED / NO_MODULES)
  1 - ERROR: other failure

Comment preservation: comments OUTSIDE the external_modules section are always
kept. Insert mode also keeps comments inside the section (it only appends new
entries). Remove/update modes rewrite the section's contents canonically from
the parsed object, so comments *inside* the external_modules section are not
preserved — entries there are machine-generated in practice.

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


def _strip_comments(text):
    """Remove // and /* */ comments, keeping string literals intact."""
    out = []
    i = 0
    while i < len(text):
        n = _skip_strings_and_comments(text, i)
        if n != i:
            if text[i] == '"':
                out.append(text[i:n])
            i = n
            continue
        out.append(text[i])
        i += 1
    return ''.join(out)


def _drop_orphan_commas(s):
    """Remove commas that are immediately preceded or followed (ignoring
    whitespace) by '{', '}' or another comma. Tolerates the leading/trailing
    comma artifacts left by textual insert merges."""
    out = []
    i = 0
    n = len(s)
    while i < n:
        if s[i] == ',':
            j = len(out) - 1
            while j >= 0 and out[j] in ' \t\n\r':
                j -= 1
            prev = out[j] if j >= 0 else '{'
            k = i + 1
            while k < n and s[k] in ' \t\n\r':
                k += 1
            nxt = s[k] if k < n else '}'
            if prev in '{,' or nxt in '},':
                i += 1
                continue
        out.append(s[i])
        i += 1
    return ''.join(out)


def _parse_section_dict(inner_text):
    """Parse the text between the external_modules braces into a dict,
    tolerating comments and orphan commas."""
    clean = _drop_orphan_commas(_strip_comments(inner_text))
    return json.loads('{' + clean + '}')


def _serialize_section_dict(section_dict):
    """Serialize a dict as the inner content of the external_modules section."""
    body = json.dumps(section_dict, indent=2)
    return body[1:-1]


def _load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        print("ERROR: target file not found", file=sys.stderr)
        sys.exit(1)


def _load_entries(path):
    try:
        with open(path) as f:
            entries = json.load(f)
    except (json.JSONDecodeError, FileNotFoundError) as e:
        print(f"ERROR: cannot read entries file: {e}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(entries, dict) or not entries:
        print("SKIP_EMPTY")
        return None
    return entries


def _cmd_insert(jsonc_path, entries_path):
    entries = _load_entries(entries_path)
    if entries is None:
        return 0

    text = _load_text(jsonc_path)
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


def _cmd_remove(jsonc_path, key):
    text = _load_text(jsonc_path)
    bounds = _find_field_value_end(text, "external_modules")
    if bounds is None:
        print("NOT_FOUND")
        return 0

    mod_start, mod_end = bounds
    try:
        section = _parse_section_dict(text[mod_start + 1:mod_end - 1])
    except (json.JSONDecodeError, ValueError):
        print("ERROR: cannot parse external_modules section", file=sys.stderr)
        sys.exit(1)

    if key not in section:
        print("NOT_FOUND")
        return 0

    del section[key]
    text = text[:mod_start] + '{' + _serialize_section_dict(section) + '}' + text[mod_end:]
    with open(jsonc_path, 'w') as f:
        f.write(text)
    print("REMOVED")
    return 0


def _cmd_update(jsonc_path, entries_path):
    entries = _load_entries(entries_path)
    if entries is None:
        return 0

    text = _load_text(jsonc_path)
    bounds = _find_field_value_end(text, "external_modules")
    if bounds is None:
        print("SKIP_ALL (no external_modules section)")
        return 0

    mod_start, mod_end = bounds
    try:
        section = _parse_section_dict(text[mod_start + 1:mod_end - 1])
    except (json.JSONDecodeError, ValueError):
        print("ERROR: cannot parse external_modules section", file=sys.stderr)
        sys.exit(1)

    updated = 0
    not_present = 0
    for key, decl in entries.items():
        if not isinstance(decl, dict) or key not in section:
            not_present += 1
            continue
        existing = section[key]
        if not isinstance(existing, dict):
            existing = {}
        # Declaration wins for url/paths; any other existing keys (e.g. a
        # user-added local `path`) are preserved.
        merged = dict(existing)
        for field in ('url', 'paths'):
            if field in decl:
                merged[field] = decl[field]
        section[key] = merged
        updated += 1

    if updated == 0:
        print(f"SKIP_ALL ({not_present} not present)")
        return 0

    text = text[:mod_start] + '{' + _serialize_section_dict(section) + '}' + text[mod_end:]
    with open(jsonc_path, 'w') as f:
        f.write(text)
    print(f"UPDATED ({updated} entry/entries)")
    return 0


def main():
    argv = sys.argv[1:]
    if len(argv) == 2:
        _cmd_insert(argv[0], argv[1])
    elif len(argv) == 3 and argv[1] == '--remove':
        _cmd_remove(argv[0], argv[2])
    elif len(argv) == 3 and argv[1] == '--update':
        _cmd_update(argv[0], argv[2])
    else:
        print(
            "Usage: merge_modules_jsonc.py <jsonc_file> <entries_file>"
            " | <jsonc_file> --remove <key>"
            " | <jsonc_file> --update <entries_file>",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == '__main__':
    main()
