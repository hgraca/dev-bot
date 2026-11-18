#!/usr/bin/env python3
"""Ensure a JSONC config carries specific guard rules from a dist config.

A guard rule lives in two places that must agree: the shipped dist config (the
template a fresh install copies) and the runtime config (what the guards engine
reads). Seeding a new rule therefore reaches new installs only — an existing
`devbot.global.jsonc` is never overwritten, and the updater reconciles top-level
keys without touching a key both files have. This helper is the other half: a
release migration calls it to append the rule to configs that predate it.

The rule TEXT comes from the dist file, so the message has one source. Only the
rules named with `--only-regex` are considered: a dist gains rules for other
reasons, and a migration must change exactly what its release announces.

Comment-preserving: the guards array is spliced as text, so an operator's
comments, key order and the formatting of the rules already there survive.

Usage:
  ensure_guard_rules.py --from <dist.jsonc> [--only-regex RE]... <config.jsonc>
  ensure_guard_rules.py --remove-regex RE [--remove-regex RE]... <config.jsonc>

Prints one of: added <n> | present | removed <n> | absent
Exit codes: 0 on success (including no-op), 1 when a file cannot be read or has
no top-level object.
"""

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from read_jsonc import load_jsonc  # noqa: E402

KEY = "guards"


def _skip_string(text, i):
    """Index just past the string literal starting at i."""
    n = len(text)
    j = i + 1
    while j < n:
        if text[j] == "\\":
            j += 2
        elif text[j] == '"':
            return j + 1
        else:
            j += 1
    return n


def _skip_comment(text, i):
    """Index just past the comment starting at i, or i when there is none."""
    if text[i : i + 2] == "//":
        j = text.find("\n", i)
        return len(text) if j == -1 else j
    if text[i : i + 2] == "/*":
        j = text.find("*/", i + 2)
        return len(text) if j == -1 else j + 2
    return i


def last_significant(text):
    """Index of the last character outside comments, strings and whitespace."""
    i, n, last = 0, len(text), -1
    while i < n:
        if text[i] == '"':
            j = _skip_string(text, i)
            last = j - 1
            i = j
            continue
        if text[i] == "/" and text[i : i + 2] in ("//", "/*"):
            i = _skip_comment(text, i)
            continue
        if not text[i].isspace():
            last = i
        i += 1
    return last


def find_top_level_object(text):
    """(index of the top-level '{', index of its matching '}') or (-1, -1)."""
    start, depth, i, n = -1, 0, 0, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            i = _skip_string(text, i)
            continue
        if ch == "/" and text[i : i + 2] in ("//", "/*"):
            i = _skip_comment(text, i)
            continue
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start != -1:
                return start, i
        i += 1
    return start, -1


def find_top_level_key(text, key):
    """Index of the top-level "key" token, or -1."""
    start, end = find_top_level_object(text)
    if start == -1:
        return -1
    depth, i, n = 0, start, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            begin = i
            i = _skip_string(text, i)
            if depth == 1 and text[begin:i] == f'"{key}"':
                return begin
            continue
        if ch in "/" and text[i : i + 2] in ("//", "/*"):
            i = _skip_comment(text, i)
            continue
        if ch in "{[":
            depth += 1
        elif ch in "}]":
            depth -= 1
            if depth == 0:
                return -1
        i += 1
    return -1


def find_array_after(text, key_index):
    """(index of '[', index of its matching ']') for the value at key_index."""
    i, n = key_index, len(text)
    i = _skip_string(text, i)
    while i < n and text[i] != ":":
        if text[i] == '"':
            i = _skip_string(text, i)
            continue
        if text[i : i + 2] in ("//", "/*"):
            i = _skip_comment(text, i)
            continue
        i += 1
    while i < n and text[i] != "[":
        if text[i : i + 2] in ("//", "/*"):
            i = _skip_comment(text, i)
            continue
        if text[i] in "}]":
            return -1, -1
        i += 1
    if i >= n:
        return -1, -1
    open_at, depth = i, 0
    while i < n:
        ch = text[i]
        if ch == '"':
            i = _skip_string(text, i)
            continue
        if ch in "/" and text[i : i + 2] in ("//", "/*"):
            i = _skip_comment(text, i)
            continue
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return open_at, i
        i += 1
    return open_at, -1


def split_elements(inner):
    """Top-level array elements as raw text slices (commas excluded)."""
    elements, depth, i, n, start = [], 0, 0, len(inner), 0
    while i < n:
        ch = inner[i]
        if ch == '"':
            i = _skip_string(inner, i)
            continue
        if ch == "/" and inner[i : i + 2] in ("//", "/*"):
            i = _skip_comment(inner, i)
            continue
        if ch in "{[":
            depth += 1
        elif ch in "}]":
            depth -= 1
        elif ch == "," and depth == 0:
            elements.append(inner[start:i])
            start = i + 1
        i += 1
    tail = inner[start:]
    if tail.strip():
        elements.append(tail)
    return elements


def member_indent(inner, elements):
    """Indentation of the array's members, inferred from the first element."""
    for element in elements:
        stripped = element.lstrip()
        lead = element[: len(element) - len(stripped)]
        if "\n" in lead:
            return lead[lead.rfind("\n") + 1 :]
    # No element yet: four spaces is the depth a members indent sits at in the
    # shipped configs (two for the key, two more for the array's members).
    return "    "


def render_rule(rule, indent):
    """The rule as array-member text, indented like its neighbours."""
    body = json.dumps(rule, indent=2, ensure_ascii=False)
    return "\n".join(indent + line if line else line for line in body.split("\n"))


def split_element_value(slice_text):
    """(value text, following decoration) for one element slice.

    The decoration is whatever trails the value — usually whitespace, and for
    the last element the array's closing comment too.
    """
    i, n = 0, len(slice_text)
    while i < n and slice_text[i].isspace():
        i += 1
    start = i
    if i < n and slice_text[i] in "{[":
        depth = 0
        while i < n:
            ch = slice_text[i]
            if ch == '"':
                i = _skip_string(slice_text, i)
                continue
            if ch == "/" and slice_text[i : i + 2] in ("//", "/*"):
                i = _skip_comment(slice_text, i)
                continue
            if ch in "{[":
                depth += 1
            elif ch in "}]":
                depth -= 1
                if depth == 0:
                    i += 1
                    break
            i += 1
    elif i < n and slice_text[i] == '"':
        i = _skip_string(slice_text, i)
    else:
        while i < n and slice_text[i] not in ",]} \t\n\r":
            i += 1
    return slice_text[start:i], slice_text[i:]


def strip_comments(text):
    """The text with comments removed; string literals are left intact."""
    out, i, n = [], 0, len(text)
    while i < n:
        if text[i] == '"':
            j = _skip_string(text, i)
            out.append(text[i:j])
            i = j
            continue
        if text[i] == "/" and text[i : i + 2] in ("//", "/*"):
            i = _skip_comment(text, i)
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def parse_element(text):
    """The element's value, or None when it is not valid JSONC.

    An element slice carries whatever trailed it — a comment after the last
    element lives inside the array, so it is part of that slice.
    """
    raw = strip_comments(text).strip()
    if raw.endswith(","):
        raw = raw[:-1].rstrip()
    try:
        return json.loads(raw)
    except ValueError:
        return None


def add_rules(text, rules):
    key_at = find_top_level_key(text, KEY)
    if key_at == -1:
        # No guards key at all: splice one in before the object's closing brace.
        start, end = find_top_level_object(text)
        if start == -1 or end == -1:
            return None
        base = "  "
        block = f'{base}"{KEY}": [\n'
        block += ",\n".join(render_rule(rule, base + "  ") for rule in rules)
        block += f"\n{base}]"
        body = text[start + 1 : end].rstrip()
        if body and not body.rstrip().endswith(","):
            body += ","
        return text[: start + 1] + body + "\n" + block + "\n" + text[end:]

    open_at, close_at = find_array_after(text, key_at)
    if open_at == -1 or close_at == -1:
        return None
    inner = text[open_at + 1 : close_at]
    elements = split_elements(inner)
    indent = member_indent(inner, elements)
    rendered = ",\n".join(render_rule(rule, indent) for rule in rules)

    # The append point is the last significant character, so a comment trailing
    # the final element cannot swallow the separating comma. That comment (and
    # the closing bracket's indentation) are re-emitted after the new rules.
    sig = last_significant(inner)
    body = inner[: sig + 1] if sig >= 0 else ""
    tail = inner[sig + 1 :] if sig >= 0 else inner
    if body.rstrip().endswith(","):
        body = body.rstrip()[:-1].rstrip()
    comment = tail.strip()
    if "\n" in tail:
        close_indent = tail[tail.rfind("\n") + 1 :]
    else:
        # A one-line array: the closing bracket lines up with the key's line.
        line = text[:open_at].rfind("\n")
        close_indent = text[line + 1 : open_at] if line != -1 else ""
        close_indent = close_indent[: len(close_indent) - len(close_indent.lstrip())]

    new_inner = f"{body},\n{rendered}" if body else f"\n{rendered}"
    if comment:
        new_inner += f"\n{indent}{comment}"
    new_inner += f"\n{close_indent}"
    return text[: open_at + 1] + new_inner + text[close_at:]


def remove_rules(text, regexes):
    key_at = find_top_level_key(text, KEY)
    if key_at == -1:
        return None, 0
    open_at, close_at = find_array_after(text, key_at)
    if open_at == -1 or close_at == -1:
        return None, 0
    inner = text[open_at + 1 : close_at]
    elements = split_elements(inner)
    # The last element carries the array's closing whitespace and comment; it
    # is re-emitted separately so dropping that element cannot delete them.
    tail = split_element_value(elements[-1])[1] if elements else ""
    kept, removed = [], 0
    for element in elements:
        value = parse_element(element)
        if isinstance(value, dict) and value.get("regex") in regexes:
            removed += 1
            continue
        kept.append(element)
    if removed == 0:
        return text, 0
    if not kept:
        new_inner = tail
    else:
        new_inner = ",".join(kept)
        # The final decoration lives only in the last raw slice; if that slice
        # was the one removed, it has to be appended back.
        if elements and elements[-1] not in kept and tail:
            new_inner += tail
    return text[: open_at + 1] + new_inner + text[close_at:], removed


def write_atomic(path, text):
    handle = tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=os.path.dirname(path), delete=False)
    try:
        handle.write(text)
        handle.close()
        os.replace(handle.name, path)
    except OSError:
        os.unlink(handle.name)
        raise


def load_guards(path):
    config = load_jsonc(path)
    if not isinstance(config, dict):
        return None
    guards = config.get(KEY)
    return guards if isinstance(guards, list) else []


def main(argv):
    args = argv[1:]
    dist = None
    only, remove = [], []
    paths = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--from" and i + 1 < len(args):
            dist = args[i + 1]
            i += 2
        elif arg == "--only-regex" and i + 1 < len(args):
            only.append(args[i + 1])
            i += 2
        elif arg == "--remove-regex" and i + 1 < len(args):
            remove.append(args[i + 1])
            i += 2
        else:
            paths.append(arg)
            i += 1

    if len(paths) != 1 or (bool(dist) == bool(remove)):
        print(__doc__.split("Usage:")[1].strip(), file=sys.stderr)
        return 1

    path = paths[0]
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        existing = load_guards(path)
    except (OSError, ValueError) as error:
        print(f"WARN: cannot read {path}: {error}", file=sys.stderr)
        return 1
    if existing is None:
        print(f"WARN: no top-level object in {path}", file=sys.stderr)
        return 1

    if remove:
        updated, count = remove_rules(text, set(remove))
        if updated is None:
            print(f"WARN: no guards array in {path}", file=sys.stderr)
            return 1
        if count == 0:
            print("absent")
            return 0
        try:
            write_atomic(path, updated)
        except OSError as error:
            print(f"WARN: cannot write {path}: {error}", file=sys.stderr)
            return 1
        print(f"removed {count}")
        return 0

    try:
        with open(dist, encoding="utf-8") as handle:
            dist_text = handle.read()
        dist_config = load_jsonc(dist)
    except (OSError, ValueError) as error:
        print(f"WARN: cannot read {dist}: {error}", file=sys.stderr)
        return 1
    shippped = [r for r in (dist_config.get(KEY) or []) if isinstance(r, dict)]
    present = {r.get("regex") for r in existing if isinstance(r, dict)}
    missing = [r for r in shippped if (not only or r.get("regex") in only) and r.get("regex") not in present]
    if not missing:
        print("present")
        return 0
    updated = add_rules(text, missing)
    if updated is None:
        print(f"WARN: cannot splice a guards array into {path}", file=sys.stderr)
        return 1
    try:
        write_atomic(path, updated)
    except OSError as error:
        print(f"WARN: cannot write {path}: {error}", file=sys.stderr)
        return 1
    print(f"added {len(missing)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
