#!/usr/bin/env python3
"""OpenCode 2.x config edits for the opencode-v2 harness.

The v1 helpers under src/_shared/ write the v1 shapes (`plugin`, `mcp.<name>`,
`permission.<tool>`). V2 renamed all of them, so this module carries its own
edits instead of teaching the shared scripts a second schema.

Every edit is a textual splice, not a load-and-dump: opencode.jsonc is seeded
once and then belongs to the project, and re-serialising it would drop the
comments and reorder the keys a user added. Output is byte-stable, so a reinit
that changes nothing writes nothing.

Usage:
  v2config.py get <config> <dotted.path>
  v2config.py has-legacy <config>
  v2config.py upsert-plugin <config> <spec>
  v2config.py remove-plugin <config> <spec>
  v2config.py merge-mcp <config> <key> <def-json>
  v2config.py remove-mcp <config> <key>
  v2config.py ensure-external-directory <config>
  v2config.py set-default-agent <config> <agent>
"""

import json
import os
import sys

_SHARED = os.environ.get("V2_SHARED_DIR", "")
if _SHARED:
    sys.path.insert(0, _SHARED)


def load(path):
    from read_jsonc import load_jsonc  # type: ignore

    return load_jsonc(path)


def read(path):
    with open(path) as handle:
        return handle.read()


def write(path, text):
    tmp = path + ".devbot-tmp"
    with open(tmp, "w") as handle:
        handle.write(text)
    load(tmp)  # never replace the config with something unparseable
    os.chmod(tmp, os.stat(path).st_mode)
    os.replace(tmp, path)


# ── scanning ──────────────────────────────────────────────────────────────────


def _skip(text, i):
    """Advance past a string literal (honouring escapes) or a JSONC comment."""
    if text[i] == '"':
        i += 1
        while i < len(text):
            if text[i] == "\\":
                i += 2
                continue
            if text[i] == '"':
                return i + 1
            i += 1
        return i
    if text[i:i + 2] == "//":
        j = text.find("\n", i)
        return len(text) if j == -1 else j
    if text[i:i + 2] == "/*":
        j = text.find("*/", i + 2)
        return len(text) if j == -1 else j + 2
    return i


def _container_end(text, i):
    """Index of the closer matching the opener at `i`, or -1."""
    opener = text[i]
    closer = "}" if opener == "{" else "]"
    depth = 0
    while i < len(text):
        ch = text[i]
        if ch == '"' or text[i:i + 2] in ("//", "/*"):
            i = _skip(text, i)
            continue
        if ch == opener:
            depth += 1
        elif ch == closer:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def _value_end(text, i):
    """Exclusive end of the value starting at `i`."""
    if text[i] in "{[":
        end = _container_end(text, i)
        return len(text) if end == -1 else end + 1
    while i < len(text):
        ch = text[i]
        if ch == '"' or text[i:i + 2] in ("//", "/*"):
            i = _skip(text, i)
            continue
        if ch in ",}]\n":
            break
        i += 1
    return i


def _lines(text, open_i, close_i):
    """Yield (key, value_start, value_end) for each direct member of an object."""
    i = open_i + 1
    while i < close_i:
        ch = text[i]
        if ch.isspace() or ch == ",":
            i += 1
            continue
        if ch != '"':
            i = _value_end(text, i)
            continue
        key_end = _skip(text, i)
        j = key_end
        while j < close_i and text[j].isspace():
            j += 1
        if j >= close_i or text[j] != ":":
            i = key_end
            continue
        j += 1
        while j < close_i and text[j].isspace():
            j += 1
        if j >= close_i:
            return
        value_end = _value_end(text, j)
        yield text[i + 1:key_end - 1], j, value_end
        i = value_end


def _root(text):
    open_i = text.find("{")
    if open_i == -1:
        raise SystemExit("ERROR: config has no root object")
    close_i = _container_end(text, open_i)
    if close_i == -1:
        raise SystemExit("ERROR: config root object is unterminated")
    return open_i, close_i


def _member(text, open_i, close_i, key):
    for name, start, end in _lines(text, open_i, close_i):
        if name == key:
            return start, end
    return None


def _member_container(text, open_i, close_i, key, opener):
    span = _member(text, open_i, close_i, key)
    if not span:
        return None
    if text[span[0]] != opener:
        return None
    close = _container_end(text, span[0])
    return (span[0], close) if close != -1 else None


def _array_items(text, open_i, close_i):
    i = open_i + 1
    while i < close_i:
        if text[i].isspace() or text[i] == ",":
            i += 1
            continue
        start = i
        end = _value_end(text, i)
        yield start, end
        i = end


def _line_indent(text, index):
    start = text.rfind("\n", 0, index) + 1
    indent = ""
    for ch in text[start:index]:
        if ch in " \t":
            indent += ch
        else:
            break
    return indent


# ── insert / remove ───────────────────────────────────────────────────────────


def _insert(text, span, entry):
    open_i, close_i = span
    close_indent = _line_indent(text, close_i)
    if text[open_i + 1:close_i].strip() == "":
        # Replace the container's inner whitespace wholesale: appending into it
        # would leave a blank line behind, one more on every reinit.
        child = close_indent + "  "
        return (
            text[:open_i + 1]
            + "\n"
            + child
            + entry
            + "\n"
            + close_indent
            + text[close_i:]
        )
    i = close_i - 1
    while i > open_i and text[i].isspace():
        i -= 1
    return text[:i + 1] + ",\n" + close_indent + "  " + entry + text[i + 1:]


def _line_start(text, index):
    """Index just after the newline, when `index` is preceded only by indent."""
    nl = text.rfind("\n", 0, index)
    if nl != -1 and text[nl + 1:index].strip() == "":
        return nl + 1
    return index


def _cut(text, start, end):
    """Remove [start, end) plus one adjoining comma, keeping the file valid."""
    j = end
    while j < len(text) and text[j] in " \t":
        j += 1
    if j < len(text) and text[j] == ",":
        # Member has a successor: drop it together with the following comma and
        # newline, and its own indentation, so the next member keeps its own.
        k = j + 1
        while k < len(text) and text[k] in " \t":
            k += 1
        if k < len(text) and text[k] == "\n":
            k += 1
        return text[:_line_start(text, start)] + text[k:]
    # Last member: drop the preceding comma instead.
    k = start - 1
    while k >= 0 and text[k].isspace():
        k -= 1
    if k >= 0 and text[k] == ",":
        return text[:k] + text[end:]
    # Sole member: drop its line and the newline it leaves behind, or the
    # container keeps a blank line for every removal.
    rest = text[end:]
    if rest.startswith("\n"):
        rest = rest[1:]
    return text[:_line_start(text, start)] + rest


# ── commands ──────────────────────────────────────────────────────────────────


def cmd_get(path, dotted):
    value = load(path)
    for part in dotted.split("."):
        if not isinstance(value, dict) or part not in value:
            return 1
        value = value[part]
    print(json.dumps(value))
    return 0


def cmd_has_legacy(path):
    cfg = load(path)
    legacy = [k for k in ("plugin", "permission", "agent", "provider") if k in cfg]
    mcp = cfg.get("mcp")
    if isinstance(mcp, dict) and mcp and "servers" not in mcp:
        legacy.append("mcp")
    if legacy:
        print(" ".join(legacy))
        return 0
    return 1


def cmd_upsert_plugin(path, spec):
    cfg = load(path)
    for entry in cfg.get("plugins") or []:
        if entry == spec or (isinstance(entry, dict) and entry.get("package") == spec):
            return 0
    text = read(path)
    open_i, close_i = _root(text)
    span = _member_container(text, open_i, close_i, "plugins", "[")
    if not span:
        raise SystemExit("ERROR: no top-level 'plugins' array")
    write(path, _insert(text, span, json.dumps(spec)))
    return 0


def cmd_remove_plugin(path, spec):
    text = read(path)
    open_i, close_i = _root(text)
    span = _member_container(text, open_i, close_i, "plugins", "[")
    if not span:
        return 1
    for start, end in _array_items(text, span[0], span[1]):
        try:
            if json.loads(text[start:end]) == spec:
                write(path, _cut(text, start, end))
                return 0
        except Exception:
            continue
    return 1


def cmd_merge_mcp(path, key, definition):
    cfg = load(path)
    if key in ((cfg.get("mcp") or {}).get("servers") or {}):
        return 0
    text = read(path)
    open_i, close_i = _root(text)
    mcp_span = _member_container(text, open_i, close_i, "mcp", "{")
    if not mcp_span:
        # Older seeds may predate the mcp block entirely — build it.
        body = '"mcp": {\n    "servers": {\n      "%s": %s\n    }\n  }' % (key, definition)
        write(path, _insert(text, (open_i, close_i), body))
        return 0
    servers = _member_container(text, mcp_span[0], mcp_span[1], "servers", "{")
    if not servers:
        body = '"servers": {\n      "%s": %s\n    }' % (key, definition)
        write(path, _insert(text, mcp_span, body))
        return 0
    write(path, _insert(text, servers, '"%s": %s' % (key, definition)))
    return 0


def cmd_remove_mcp(path, key):
    text = read(path)
    open_i, close_i = _root(text)
    mcp_span = _member_container(text, open_i, close_i, "mcp", "{")
    if not mcp_span:
        return 1
    servers = _member_container(text, mcp_span[0], mcp_span[1], "servers", "{")
    if not servers:
        return 1
    for name, start, end in _lines(text, servers[0], servers[1]):
        if name == key:
            # Rewind to the key's opening quote so the comma logic sees it.
            key_at = text.rfind('"%s"' % key, servers[0], start + 1)
            write(path, _cut(text, key_at if key_at != -1 else start, end))
            return 0
    return 1


def cmd_ensure_external_directory(path):
    """Deny-first with /tmp/** allowed — the v2 form of v1's permission block.

    V2 allows external directories by default, so the catch-all deny is what
    restores v1's behaviour. Rules are ordered and the last match wins, so the
    deny has to precede the allow.
    """
    cfg = load(path)
    rules = cfg.get("permissions") or []

    def has(action, resource, effect):
        return any(
            isinstance(r, dict)
            and r.get("action") == action
            and r.get("resource") == resource
            and r.get("effect") == effect
            for r in rules
        )

    missing = []
    if not has("external_directory", "*", "deny"):
        missing.append({"action": "external_directory", "resource": "*", "effect": "deny"})
    if not has("external_directory", "/tmp/**", "allow"):
        missing.append({"action": "external_directory", "resource": "/tmp/**", "effect": "allow"})
    if not missing:
        return 0

    text = read(path)
    open_i, close_i = _root(text)
    span = _member_container(text, open_i, close_i, "permissions", "[")
    if not span:
        raise SystemExit("ERROR: no top-level 'permissions' array")
    # Reverse so each insertion lands in list order.
    for rule in reversed(missing):
        text = _insert(text, span, json.dumps(rule))
        open_i, close_i = _root(text)
        span = _member_container(text, open_i, close_i, "permissions", "[")
    write(path, text)
    print("1")
    return 0


def cmd_set_default_agent(path, agent):
    text = read(path)
    open_i, close_i = _root(text)
    span = _member(text, open_i, close_i, "default_agent")
    if span:
        key_at = text.rfind('"default_agent"', open_i, span[0] + 1)
        if key_at == -1:
            return 1
        write(path, text[:key_at] + '"default_agent": %s' % json.dumps(agent) + text[span[1]:])
        return 0
    write(path, text[:open_i + 1] + '\n  "default_agent": %s,' % json.dumps(agent) + text[open_i + 1:])
    return 0


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, path = argv[1], argv[2]
    rest = argv[3:]
    if cmd == "get":
        return cmd_get(path, rest[0])
    if cmd == "has-legacy":
        return cmd_has_legacy(path)
    if cmd == "upsert-plugin":
        return cmd_upsert_plugin(path, rest[0])
    if cmd == "remove-plugin":
        return cmd_remove_plugin(path, rest[0])
    if cmd == "merge-mcp":
        return cmd_merge_mcp(path, rest[0], rest[1])
    if cmd == "remove-mcp":
        return cmd_remove_mcp(path, rest[0])
    if cmd == "ensure-external-directory":
        return cmd_ensure_external_directory(path)
    if cmd == "set-default-agent":
        return cmd_set_default_agent(path, rest[0])
    print("ERROR: unknown command %s" % cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
