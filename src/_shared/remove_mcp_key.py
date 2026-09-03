#!/usr/bin/env python3
"""Remove an MCP server key from a JSONC config file.

Handles both config shapes:
  - opencode.jsonc:   top-level "mcp" map        { "mcp": { "qmd": {...} } }
  - .mcp.json (Claude Code): top-level "mcpServers" map

Removal is text surgery: only the targeted key's entry (plus one adjacent
comma/whitespace) is deleted, so the rest of the file — comments, formatting,
object layout — is preserved byte-for-byte. This keeps reinit byte-idempotent
(audit-32 NOTE): a whole-file json.dump rewrite expanded compact objects and
dropped comments, so a second reinit produced a different opencode.jsonc than
the first.

Usage:
  remove_mcp_key.py <config_file> <mcp_key>

Exit codes:
  0 — key was removed or was not present (idempotent)
  1 — error (file missing, parse error, etc.)
"""

import re
import sys
import os


def _skip_strings_and_comments(text, pos):
    """Advance pos past any string literal or comment at current position."""
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


def _find_top_level_map(text, key):
    """Find (start, end) of the value object for top-level key 'mcp'/'mcpServers'.

    Returns (map_start, map_end_exclusive) where map_start is the position of
    the '{' and map_end is just past the matching '}'. Returns None if the key
    is absent or its value is not an object.
    """
    match = re.search(r'^\s*"' + re.escape(key) + r'"\s*:', text, re.MULTILINE)
    if not match:
        return None

    i = match.end()
    while i < len(text):
        i = _skip_strings_and_comments(text, i)
        if i >= len(text):
            return None
        if text[i] == '{':
            depth = 0
            j = i
            while j < len(text):
                nxt = _skip_strings_and_comments(text, j)
                if nxt != j:
                    j = nxt
                    continue
                ch = text[j]
                if ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                    if depth == 0:
                        return (i, j + 1)
                j += 1
            return None
        if text[i] in ' \t\n\r,':
            i += 1
            continue
        return None  # value is not an object


def _find_entry(text, map_bounds, key):
    """Find the byte range of the entry for `key` inside the map.

    Returns (entry_start, entry_end) covering the key through the end of its
    value (not including a trailing comma). Returns None if absent.
    """
    map_start, map_end = map_bounds
    inner = text[map_start:map_end]
    match = re.search(r'^\s*"' + re.escape(key) + r'"\s*:', inner, re.MULTILINE)
    if not match:
        return None

    value_start = map_start + match.end()
    # Skip to the value token.
    i = value_start
    while i < map_end:
        i = _skip_strings_and_comments(text, i)
        if i >= map_end:
            return None
        ch = text[i]
        if ch in ' \t\n\r':
            i += 1
            continue
        break
    if i >= map_end:
        return None

    # Value start token.
    if text[i] == '{' or text[i] == '[':
        depth = 0
        j = i
        quote = None
        while j < map_end:
            nxt = _skip_strings_and_comments(text, j)
            if nxt != j:
                j = nxt
                continue
            ch = text[j]
            if ch == '{' or ch == '[':
                depth += 1
            elif ch == '}' or ch == ']':
                depth -= 1
                if depth == 0:
                    return (map_start + match.start(), j + 1)
            j += 1
        return None
    # Scalar value: extend to the comma / closing brace / newline.
    j = i
    while j < map_end and text[j] not in ',}\n':
        j = _skip_strings_and_comments(text, j)
        if j >= map_end:
            break
        if text[j] in ',}\n':
            break
        j += 1
    return (map_start + match.start(), j)


def _remove_entry_text(text, entry_bounds, map_end):
    """Return text with the entry removed, cleaning adjacent commas/lines.

    Handles entry-not-last ("key": value,\n), entry-last (previous entry keeps
    its trailing comma → dangling before the map close), and single-entry maps.
    """
    start, end = entry_bounds

    # Consume a trailing comma (entry is not the last one).
    after = end
    while after < len(text) and text[after] in ' \t':
        after += 1
    if after < len(text) and text[after] == ',':
        after += 1
        # Swallow whitespace up to (and including) one newline so the removed
        # entry leaves no blank line behind.
        while after < len(text) and text[after] in ' \t':
            after += 1
        if after < len(text) and text[after] == '\n':
            after += 1
        return text[:start] + text[after:]

    # Entry is the last one: no trailing comma. Its own preceding newline is
    # removed with it; the previous entry's trailing comma becomes dangling and
    # is cleaned by _fix_dangling_comma_before_close.
    # Swallow the entry's leading indentation + preceding newline.
    before = start
    while before > 0 and text[before - 1] in ' \t':
        before -= 1
    if before > 0 and text[before - 1] == '\n':
        before -= 1
    removed = end - before
    new_text = text[:before] + text[end:]
    return _fix_dangling_comma_before_close(new_text, map_end - removed)


def _fix_dangling_comma_before_close(text, map_end):
    """Remove a ',' that dangles before the map's closing '}' after a removal.

    map_end is the position just past the '}' of the map that lost an entry.
    Only touches whitespace between the comma and the close — nothing else.
    """
    close = map_end - 1
    # Find the last non-whitespace char before the close (which is now the
    # previous entry's trailing comma when the removed entry was last).
    i = close - 1
    while i > 0 and text[i] in ' \t\r\n':
        i -= 1
    if i >= 0 and text[i] == ',':
        # Drop the comma and any whitespace between it and the close, keeping
        # the close's own indentation line intact.
        return text[:i] + text[i + 1:]
    return text


def main():
    if len(sys.argv) != 3:
        print("Usage: remove_mcp_key.py <config_file> <mcp_key>", file=sys.stderr)
        sys.exit(1)

    config_file = sys.argv[1]
    mcp_key = sys.argv[2]

    if not os.path.isfile(config_file):
        # File doesn't exist — nothing to do (idempotent)
        sys.exit(0)

    try:
        with open(config_file, encoding='utf-8') as f:
            text = f.read()
    except OSError as e:
        print(f"Failed to read {config_file}: {e}", file=sys.stderr)
        sys.exit(1)

    # Locate whichever map shape holds the key.
    bounds = _find_top_level_map(text, "mcp") or _find_top_level_map(text, "mcpServers")
    if bounds is None:
        sys.exit(0)  # no mcp section — nothing to remove

    entry = _find_entry(text, bounds, mcp_key)
    if entry is None:
        sys.exit(0)  # key not present — idempotent no-op

    new_text = _remove_entry_text(text, entry, bounds[1])

    # Keep the file untouched if the surgery somehow produced no change (e.g.
    # a parse anomaly) — never rewrite to identical content.
    if new_text == text:
        sys.exit(0)

    with open(config_file, "w", encoding='utf-8') as f:
        f.write(new_text)

    print(f"Removed MCP key '{mcp_key}' from {config_file}", file=sys.stderr)


if __name__ == "__main__":
    main()
