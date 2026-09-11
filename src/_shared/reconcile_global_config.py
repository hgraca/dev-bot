#!/usr/bin/env python3
"""Reconcile a JSONC config against a schema template (top-level keys only).

The runtime global config (`.devbot.global.jsonc`) is machine-owned: it is
seeded from `.devbot.global.dist.jsonc` on install and then drifts as the
dist schema evolves. `devbot update` runs this tool to realign the two:

  - add each dist key absent from the runtime file, copying the dist value and
    its trailing comment;
  - remove each runtime key absent from the dist file;
  - leave the value and trailing comment of keys present in both untouched;
  - treat nested objects as opaque — never reconciled.

Edits are text surgery: only the added/removed properties change, so comments
and formatting of everything else are preserved. The result is validated in a
sibling temp file and swapped in atomically, so the runtime file is never left
truncated or unparseable.

Known limitations (accepted — the config is machine-owned and the shipped
dist/runtime use one property per line):
  - single-line / multi-property-per-line JSONC is unsupported (fails safe:
    no change, exit 1);
  - inserting into a comment-only empty object drops that object's comments;
  - removing a property leaves any standalone comment directly above it;
  - input line endings are normalized to LF.

Usage:
  reconcile_global_config.py <dist_file> <runtime_file>

Output (stdout):
  ADDED: <key>    one line per key added
  REMOVED: <key>  one line per key removed
  NOCHANGE        when the key sets already match

Exit codes:
  0 — reconciled, already in sync, or runtime file missing (idempotent)
  1 — error (dist missing/unreadable, runtime unreadable, parse failure,
      surgery or write failure)
"""

import json
import os
import sys

# The comment-aware reader lives beside this file.
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from read_jsonc import load_jsonc  # noqa: E402


def _skip_string(text, i):
    """Return the index just past the string literal starting at i (text[i] == '"')."""
    j = i + 1
    while j < len(text):
        if text[j] == "\\":
            j += 2
            continue
        if text[j] == '"':
            return j + 1
        j += 1
    return j


def _skip_whitespace(text, i):
    while i < len(text) and text[i] in " \t\r\n":
        i += 1
    return i


def _skip_ws_comments(text, i):
    """Skip whitespace and // /* */ comments."""
    while i < len(text):
        if text[i] in " \t\r\n":
            i += 1
        elif text[i : i + 2] == "//":
            n = text.find("\n", i)
            i = len(text) if n == -1 else n + 1
        elif text[i : i + 2] == "/*":
            n = text.find("*/", i)
            i = len(text) if n == -1 else n + 2
        else:
            break
    return i


def _skip_balanced(text, i):
    """Return the index just past the balanced {} or [] starting at i."""
    depth = 0
    while i < len(text):
        if text[i] == '"':
            i = _skip_string(text, i)
            continue
        if text[i : i + 2] == "//":
            n = text.find("\n", i)
            i = len(text) if n == -1 else n + 1
            continue
        if text[i : i + 2] == "/*":
            n = text.find("*/", i)
            i = len(text) if n == -1 else n + 2
            continue
        if text[i] in "{[":
            depth += 1
        elif text[i] in "}]":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def _scan_value(text, i):
    """Return the index just past the value starting at i."""
    ch = text[i]
    if ch == '"':
        return _skip_string(text, i)
    if ch in "{[":
        return _skip_balanced(text, i)
    j = i
    while j < len(text):
        if text[j] in ",}]" or text[j] in " \t\r\n":
            break
        if text[j : j + 2] in ("//", "/*"):
            break
        j += 1
    return j


def _root_close(text):
    """Return the index of the root object's closing brace."""
    start = _skip_ws_comments(text, 0)
    if start >= len(text) or text[start] != "{":
        raise ValueError("no root JSON object")
    return _skip_balanced(text, start) - 1


def _end_of_line(text, offset):
    """Return the index just past the newline ending the line containing offset."""
    nl = text.find("\n", offset)
    return len(text) if nl == -1 else nl + 1


def _top_level_props(text):
    """Return the ordered top-level properties with their byte spans.

    Each entry: {key, line_start, value_start, value_end, content_end, comment}.
    line_start covers the property's leading indentation; content_end is just
    past the value (or its trailing comment).
    """
    close = _root_close(text)
    props = []
    i = _skip_ws_comments(text, 0) + 1
    while True:
        i = _skip_ws_comments(text, i)
        if i >= len(text) or text[i] == "}":
            break
        if text[i] == ",":
            # Separator after the previous property (no trailing comment case).
            i = _skip_ws_comments(text, i + 1)
            continue
        if text[i] != '"':
            raise ValueError("expected a key at offset %d" % i)
        key_start = i
        key_end = _skip_string(text, i)
        key = json.loads(text[key_start:key_end])
        i = _skip_ws_comments(text, key_end)
        if i >= len(text) or text[i] != ":":
            raise ValueError("expected ':' after key %r" % key)
        value_start = _skip_ws_comments(text, i + 1)
        value_end = _scan_value(text, value_start)

        j = _skip_whitespace(text, value_end)
        if j < len(text) and text[j] == ",":
            j = _skip_whitespace(text, j + 1)

        comment = None
        if text[j : j + 2] == "//":
            n = text.find("\n", j)
            comment = text[j : len(text) if n == -1 else n]
            content_end = len(text) if n == -1 else n
        elif text[j : j + 2] == "/*":
            n = text.find("*/", j)
            content_end = len(text) if n == -1 else n + 2
            comment = text[j:content_end]
        else:
            content_end = value_end

        line_start = text.rfind("\n", 0, key_start) + 1
        props.append(
            {
                "key": key,
                "line_start": line_start,
                "value_start": value_start,
                "value_end": value_end,
                "content_end": content_end,
                "comment": comment,
            }
        )
        i = content_end

    # Guard: the last span must not swallow the close brace.
    for p in props:
        if p["content_end"] > close:
            raise ValueError("property %r extends past the root object" % p["key"])
    return props, close


def _remove_props(text, lines):
    """Delete the given (line_start, line_end) spans and drop any dangling comma."""
    for line_start, line_end in sorted(lines, reverse=True):
        text = text[:line_start] + text[line_end:]

    # The property that preceded a removed one may now trail a comma before the
    # close brace. Locate the last remaining property and drop that comma.
    # (The value can be followed by a `// comment`, so scanning backwards from
    # the close brace is not enough — anchor on the parsed property instead.)
    props, _ = _top_level_props(text)
    if not props:
        return text
    after = _skip_whitespace(text, props[-1]["value_end"])
    if after < len(text) and text[after] == ",":
        text = text[:after] + text[after + 1 :]
    return text


def _insert_props(text, additions):
    """Insert `additions` (key, value_text, comment) before the root close brace."""
    lines = []
    for idx, (key, value_text, comment) in enumerate(additions):
        needs_comma = idx < len(additions) - 1
        line = "  %s: %s" % (json.dumps(key), value_text)
        if needs_comma:
            line += ","
        if comment:
            line += " " + comment
        lines.append(line)

    props, close = _top_level_props(text)
    if not props:
        brace = _skip_ws_comments(text, 0)
        return text[: brace + 1] + "\n" + "\n".join(lines) + "\n" + text[close:]

    # Insert the block on the line after the last property, and the separator
    # comma right after its value — before any trailing `// comment`.
    last = props[-1]
    line_end = text.find("\n", last["content_end"])
    line_end = len(text) if line_end == -1 else line_end + 1
    prefix = text[:line_end]

    after = _skip_whitespace(text, last["value_end"])
    if not (after < len(text) and text[after] == ","):
        prefix = prefix[: last["value_end"]] + "," + prefix[last["value_end"] :]

    return prefix + "\n".join(lines) + "\n" + text[line_end:]


def main():
    if len(sys.argv) != 3:
        print("Usage: reconcile_global_config.py <dist_file> <runtime_file>", file=sys.stderr)
        return 1

    dist_file, runtime_file = sys.argv[1], sys.argv[2]

    try:
        runtime_text = open(runtime_file, encoding="utf-8").read()
    except FileNotFoundError:
        return 0  # no runtime config — nothing to reconcile (idempotent)
    except OSError as e:
        print("ERROR: cannot read runtime config %s: %s" % (runtime_file, e), file=sys.stderr)
        return 1
    try:
        dist_text = open(dist_file, encoding="utf-8").read()
    except FileNotFoundError:
        print("ERROR: dist config not found: %s" % dist_file, file=sys.stderr)
        return 1
    except OSError as e:
        print("ERROR: cannot read dist config %s: %s" % (dist_file, e), file=sys.stderr)
        return 1

    try:
        dist_data = load_jsonc(dist_file)
        runtime_data = load_jsonc(runtime_file)
        dist_props, _ = _top_level_props(dist_text)
        runtime_props, _ = _top_level_props(runtime_text)
    except Exception as e:  # parse / structure failure — never touch the runtime
        print("ERROR: cannot reconcile global config: %s" % e, file=sys.stderr)
        return 1

    dist_keys = list(dist_data.keys())
    runtime_keys = list(runtime_data.keys())
    added = [k for k in dist_keys if k not in runtime_data]
    removed = [k for k in runtime_keys if k not in dist_data]

    if not added and not removed:
        print("NOCHANGE")
        return 0

    try:
        prop_by_key = {p["key"]: p for p in dist_props}
        additions = [
            (k, dist_text[prop_by_key[k]["value_start"] : prop_by_key[k]["value_end"]], prop_by_key[k]["comment"])
            for k in added
        ]

        new_text = runtime_text
        removal_lines = [
            (p["line_start"], _end_of_line(runtime_text, p["content_end"]))
            for p in runtime_props
            if p["key"] in removed
        ]
        if removal_lines:
            new_text = _remove_props(new_text, removal_lines)
        if additions:
            new_text = _insert_props(new_text, additions)
    except Exception as e:  # surgery failure — the runtime file is untouched
        print("ERROR: cannot reconcile global config: %s" % e, file=sys.stderr)
        return 1

    # Validate in a sibling temp file and swap it in atomically, so a write
    # failure can never truncate the live config.
    tmp = runtime_file + ".reconcile.tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(new_text)
        result = load_jsonc(tmp)
        if set(result.keys()) != set(dist_keys):
            raise ValueError("reconciled key set does not match the dist schema")
        os.replace(tmp, runtime_file)
    except Exception as e:
        try:
            os.remove(tmp)
        except OSError:
            pass
        print("ERROR: reconcile produced an invalid config: %s" % e, file=sys.stderr)
        return 1

    for k in added:
        print("ADDED: %s" % k)
    for k in removed:
        print("REMOVED: %s" % k)
    return 0


if __name__ == "__main__":
    sys.exit(main())
