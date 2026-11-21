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
    # A v2 permission entry is an object (`{ … }`), a v1 one a key (`"…"`).
    match = re.search(r'\n([ \t]+)[{"]', inner)
    return match.group(1) if match else "    "


def _bracket_block(text, key):
    """Return (open_idx, close_idx) of the [...] value for "key", skipping
    strings and comments the same way _brace_block does."""
    key_m = re.search(r'"' + re.escape(key) + r'"\s*:\s*\[', text)
    if not key_m:
        return None
    start = key_m.end() - 1
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
        elif ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return start, i
        i += 1
    return None


def _line_comment_index(line):
    """Index of a // comment outside a string in one line, or None."""
    in_str = False
    escaped = False
    i = 0
    while i < len(line) - 1:
        ch = line[i]
        if in_str:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == "/" and line[i + 1] == "/":
            return i
        i += 1
    return None


def _resource_matches(pattern, resource):
    """v2 resource glob: `*` matches anything, `p/**` matches p and below."""
    if pattern == resource or pattern == "*":
        return True
    if pattern.endswith("/**"):
        prefix = pattern[: -len("/**")]
        return resource == prefix or resource.startswith(prefix + "/")
    return False


def _v2_already_allowed(inner, resource):
    """True when the LAST matching external_directory rule allows `resource`."""
    verdict = None
    for match in re.finditer(r"\{[^{}]*\}", inner, re.DOTALL):
        obj = match.group(0)
        action = re.search(r'"action"\s*:\s*"([^"]+)"', obj)
        res = re.search(r'"resource"\s*:\s*"([^"]+)"', obj)
        effect = re.search(r'"effect"\s*:\s*"([^"]+)"', obj)
        if not (action and res and effect):
            continue
        if action.group(1) != "external_directory":
            continue
        if _resource_matches(res.group(1), resource):
            verdict = effect.group(1)
    return verdict == "allow"


def _upsert_v2_array(path, src, entries):
    """Append external_directory allow rules to a v2 `permissions` array.

    v2 replaced the v1 `permission` map with an ordered rule list (last match
    wins), so the v1 path above found no block and skipped — a silent no-op that
    left opencode-v2 sessions unable to read the install (audit-05 FAIL-1).
    """
    block = _bracket_block(src, "permissions")
    if block is None:
        print(f"skip: no permission.external_directory block or permissions array in {path}", file=sys.stderr)
        return 0
    open_idx, close_idx = block
    inner = src[open_idx + 1 : close_idx]

    new_resources = []
    for resource in entries:
        # v2 resolves the LAST matching rule, and a rule is (action, resource).
        # An allow for another action, or one a later rule overrides, is not a
        # grant (review: Copilot F1/F2).
        if _v2_already_allowed(inner, resource) is False and resource not in new_resources:
            new_resources.append(resource)

    if not new_resources:
        print(f"already present: {', '.join(entries)}")
        return 0

    indent = _entry_indent(inner)
    body = inner.rstrip()
    tail = inner[len(body) :]

    # An inline comment on the last rule ("}  // note") would take the
    # separator into the comment text (review W-A): cut it off first and
    # re-emit it after the inserted entries.
    inline = ""
    if body:
        last_nl = body.rfind("\n")
        line = body[last_nl + 1 :]
        cut = _line_comment_index(line)
        if cut is not None:
            inline = line[cut:]
            body = (body[: last_nl + 1] + line[:cut]).rstrip()
    # A comment closing the array must not receive the separator: "// note,"
    # is not valid JSONC (review B4). Hold those lines and re-emit them after
    # the inserted entries.
    trailing = []
    lines = body.split("\n")
    while lines and lines[-1].lstrip().startswith("//"):
        trailing.insert(0, lines.pop())
    body = "\n".join(lines).rstrip()
    if body and not body.endswith(","):
        body += ","

    added = []
    for i, resource in enumerate(new_resources):
        suffix = "," if i < len(new_resources) - 1 else ""
        added.append(
            f'{indent}{{ "action": "external_directory", "resource": "{resource}", '
            f'"effect": "allow" }}{suffix}'
        )
    addition = "\n" + "\n".join(added)
    if trailing:
        addition += "\n" + "\n".join(trailing)
    if inline:
        addition += "\n" + indent + inline

    if "\n" not in tail:
        tail = "\n" + _line_indent(src, open_idx)

    out = src[: open_idx + 1] + body + addition + tail + src[close_idx:]
    try:
        open(path, "w", encoding="utf-8").write(out)
    except OSError as e:
        print(f"error: cannot write {path}: {e}", file=sys.stderr)
        return 1
    print(f"added to permissions: {', '.join(new_resources)}")
    return 0


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
        return _upsert_v2_array(path, src, entries)
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
