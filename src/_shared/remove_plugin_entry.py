#!/usr/bin/env python3
"""Remove a plugin entry from the top-level "plugin" array of an opencode.jsonc.

Registration of module plugins into opencode.jsonc is append-only
(_upsert_opencode_plugin), so a module that becomes disabled — e.g.
codebase-index after a codebase_index_provider flip to codebase-memory — would
leave its plugin string in the array unless something removes it. reset.sh calls
this helper for every disabled module that declares plugin.opencode.json.

Removal is text surgery: only the targeted string entry (plus one adjacent
comma/whitespace) is deleted, so the rest of the file — comments, formatting,
sibling entries — is preserved byte-for-byte. This keeps reinit byte-idempotent
(audit-32 NOTE): a whole-file json.dump rewrite would reorder or reformat the
plugin array and produce a different opencode.jsonc on the second reinit.

Usage:
  remove_plugin_entry.py <config_file> <plugin_name>

Exit codes:
  0 — plugin was removed or was not present (idempotent)
  1 — error (file missing, parse error, etc.)
"""

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


def _find_plugin_array(text):
    """Find (array_start, array_end) of the top-level 'plugin' array value.

    array_start is the position of the '[' and array_end is just past the
    matching ']'. Returns None if the key is absent or its value is not an
    array.

    The key is anchored at brace depth 0: a nested "plugin" key (inside some
    other object) on its own line must not shadow the real top-level one, and
    minified/compact layouts where the key is not at line start are still
    matched (review F2).
    """
    depth = 0
    prev_struct = ''  # last structural char ({ , } : [ ]) before the current pos
    i = 0
    n = len(text)
    while i < n:
        # A string at depth 1 that reads "plugin" is the top-level key — check
        # before generic string-skipping so the key itself is not swallowed.
        if depth == 1 and text.startswith('"plugin"', i) and prev_struct in '{,':
            after = i + len('"plugin"')
            while after < n and text[after] in ' \t\n\r':
                after = _skip_strings_and_comments(text, after)
                if after >= n:
                    break
            if after < n and text[after] == ':':
                # Find the value array.
                j = after + 1
                while j < n:
                    j = _skip_strings_and_comments(text, j)
                    if j >= n:
                        break
                    if text[j] == '[':
                        arr_depth = 0
                        k = j
                        while k < n:
                            nk = _skip_strings_and_comments(text, k)
                            if nk != k:
                                k = nk
                                continue
                            c = text[k]
                            if c == '[':
                                arr_depth += 1
                            elif c == ']':
                                arr_depth -= 1
                                if arr_depth == 0:
                                    return (j, k + 1)
                            k += 1
                        return None
                    if text[j] in ' \t\n\r,':
                        j += 1
                        continue
                    return None  # value is not an array

        # Skip strings and comments wholesale so braces inside them don't
        # perturb the depth count.
        nxt = _skip_strings_and_comments(text, i)
        if nxt != i:
            i = nxt
            continue

        ch = text[i]
        if ch == '{':
            depth += 1
            prev_struct = ch
            i += 1
            continue
        if ch == '}':
            depth -= 1
            prev_struct = ch
            i += 1
            continue
        if ch in ',:[]':
            prev_struct = ch
        i += 1
    return None


def _find_plugin_entry(text, bounds, plugin):
    """Find the byte range of the string entry for `plugin` inside the array.

    Returns (entry_start, entry_end) covering the quoted string (not including
    a trailing comma). Returns None if absent.
    """
    array_start, array_end = bounds
    inner = text[array_start:array_end]
    needle = '"' + plugin.replace('\\', '\\\\').replace('"', '\\"') + '"'
    idx = inner.find(needle)
    if idx == -1:
        return None
    return (array_start + idx, array_start + idx + len(needle))


def _remove_entry_text(text, entry_bounds, array_end):
    """Return text with the array entry removed, cleaning adjacent commas.

    Handles entry-not-last (trailing comma consumed) and entry-last (previous
    entry's trailing comma becomes dangling and is cleaned).
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

    # Entry is the last one: no trailing comma after it. Its own preceding
    # newline/indentation is removed with it; the previous entry's trailing
    # comma becomes dangling and is cleaned below.
    before = start
    while before > 0 and text[before - 1] in ' \t':
        before -= 1
    if before > 0 and text[before - 1] == '\n':
        before -= 1
    removed = end - before
    new_text = text[:before] + text[end:]
    return _fix_dangling_comma_before_close(new_text, array_end - removed)


def _fix_dangling_comma_before_close(text, array_end):
    """Remove a ',' that dangles before the array's closing ']' after removal."""
    close = array_end - 1
    i = close - 1
    while i > 0 and text[i] in ' \t\r\n':
        i -= 1
    if i >= 0 and text[i] == ',':
        return text[:i] + text[i + 1:]
    return text


def main():
    if len(sys.argv) != 3:
        print("Usage: remove_plugin_entry.py <config_file> <plugin_name>", file=sys.stderr)
        sys.exit(1)

    config_file = sys.argv[1]
    plugin = sys.argv[2]

    if not os.path.isfile(config_file):
        # File doesn't exist — nothing to do (idempotent)
        sys.exit(0)

    try:
        with open(config_file, encoding='utf-8') as f:
            text = f.read()
    except OSError as e:
        print(f"Failed to read {config_file}: {e}", file=sys.stderr)
        sys.exit(1)

    bounds = _find_plugin_array(text)
    if bounds is None:
        sys.exit(0)  # no plugin array — nothing to remove

    entry = _find_plugin_entry(text, bounds, plugin)
    if entry is None:
        sys.exit(0)  # plugin not present — idempotent no-op

    new_text = _remove_entry_text(text, entry, bounds[1])

    # Keep the file untouched if the surgery somehow produced no change.
    if new_text == text:
        sys.exit(0)

    with open(config_file, "w", encoding='utf-8') as f:
        f.write(new_text)

    print(f"Removed plugin '{plugin}' from {config_file}", file=sys.stderr)


if __name__ == "__main__":
    main()
