#!/usr/bin/env python3
"""Rename legacy CamelCase agent identifiers in a harness config, in place.

Agents register lowercase (`name: scout`), and the harnesses store an agent by
that name — `.claude/settings.json` `agent` and `opencode.jsonc`
`default_agent`/`agent` map keys. A project seeded before the rename keeps the
CamelCase form, which no agent answers to: the default agent stops resolving and
every per-agent model override silently stops applying. The dist template is
seed-once, so only a reconcile can repair an existing config.

Scope is decided structurally, not by line: a small JSONC scanner tracks string
and comment state and brace depth, so compact/inline configs work, and only the
root `default_agent` value, the root `agent` value (claudecode) or the direct
children of the root `agent` object (opencode) are rewritten. A nested key of the
same name — `provider.default_agent`, `hooks.agent`, `custom.Architect` — is
left untouched, as is a same-named string value.

When a config already holds both spellings of one agent (`"architect"` and
`"Architect"`), renaming would emit duplicate object keys and one override would
be silently dropped; the legacy key is left in place and a WARN names it.

Idempotent: a second run changes nothing.

Usage:    reconcile_agent_names.py <config> <opencode|claudecode>
Exit:     0 always (an absent config is a no-op); 2 on bad usage.
Prints:   one `<old> -> <new>` line per renamed identifier, nothing otherwise.
"""

import sys

LEGACY = {
    "DevBot": "devbot",
    "TeamLead": "teamlead",
    "Scout": "scout",
    "Architect": "architect",
    "Critic": "critic",
    "Developer": "developer",
    "PO": "po",
    "Reviewer": "reviewer",
    "Tester": "tester",
    "Security": "security",
    "Designer": "designer",
    "Expert": "expert",
}

MODES = ("opencode", "claudecode")

# Token: (kind, value, start, end, depth). `depth` is the nesting depth of the
# token itself: root-object members sit at 1, their direct children at 2.
STRING, OPEN, CLOSE, PUNCT = "string", "open", "close", "punct"


def _scan(text: str) -> list[tuple[str, str, int, int, int]]:
    """Tokenise enough JSONC to place every string, key and brace by depth."""
    tokens: list[tuple[str, str, int, int, int]] = []
    index, size = 0, len(text)
    depth = 0

    while index < size:
        char = text[index]
        if char in " \t\r\n":
            index += 1
            continue
        if char == "/" and index + 1 < size and text[index + 1] == "/":
            end = text.find("\n", index)
            index = size if end == -1 else end + 1
            continue
        if char == "/" and index + 1 < size and text[index + 1] == "*":
            end = text.find("*/", index + 2)
            index = size if end == -1 else end + 2
            continue
        if char == '"':
            end = index + 1
            while end < size:
                if text[end] == "\\":
                    end += 2
                    continue
                if text[end] == '"':
                    break
                end += 1
            tokens.append((STRING, text[index + 1 : end], index, end + 1, depth))
            index = end + 1
            continue
        if char in "{[":
            depth += 1
            tokens.append((OPEN, char, index, index + 1, depth))
            index += 1
            continue
        if char in "}]":
            depth -= 1
            tokens.append((CLOSE, char, index, index + 1, depth))
            index += 1
            continue
        tokens.append((PUNCT, char, index, index + 1, depth))
        index += 1

    return tokens


def _key_index(tokens, name: str, depth: int) -> int | None:
    """Index of the `name` key at `depth`, or None."""
    for index in range(len(tokens) - 2):
        kind, value, _, _, token_depth = tokens[index]
        if kind != STRING or value != name or token_depth != depth:
            continue
        follows = tokens[index + 1]
        if follows[0] == PUNCT and follows[1] == ":":
            return index
    return None


def _object_close(tokens, open_index: int) -> int | None:
    """Index of the `}` closing the object opened at `open_index`."""
    open_depth = tokens[open_index][4]
    for index in range(open_index + 1, len(tokens)):
        kind, value, _, _, token_depth = tokens[index]
        if kind == CLOSE and value == "}" and token_depth == open_depth - 1:
            return index
    return None


def _string_value(tokens, key_index: int) -> tuple[str, int, int] | None:
    """The (value, start, end) string token that follows a key, if any."""
    if key_index + 2 >= len(tokens):
        return None
    kind, value, start, end, _ = tokens[key_index + 2]
    return (value, start, end) if kind == STRING else None


def _plan(text: str, mode: str, path: str) -> list[tuple[int, int, str, str, str]]:
    """Return (start, end, replacement, old, new) edits, ascending by start."""
    tokens = _scan(text)
    edits: list[tuple[int, int, str, str, str]] = []

    def plan_value(key_name: str) -> None:
        key_index = _key_index(tokens, key_name, 1)
        if key_index is None:
            return
        found = _string_value(tokens, key_index)
        if not found:
            return
        value, start, end = found
        if value in LEGACY:
            edits.append((start, end, f'"{LEGACY[value]}"', value, LEGACY[value]))

    if mode == "claudecode":
        plan_value("agent")
        return edits

    plan_value("default_agent")

    key_index = _key_index(tokens, "agent", 1)
    if key_index is None:
        return edits
    open_index = key_index + 2
    if open_index >= len(tokens):
        return edits
    if tokens[open_index][0] != OPEN or tokens[open_index][1] != "{":
        return edits
    close_index = _object_close(tokens, open_index)
    if close_index is None:
        return edits

    children: list[tuple[str, int, int]] = []
    for index in range(open_index + 1, close_index):
        kind, value, start, end, token_depth = tokens[index]
        if kind != STRING or token_depth != 2:
            continue
        follows = tokens[index + 1]
        if follows[0] == PUNCT and follows[1] == ":":
            children.append((value, start, end))

    existing = {name for name, _, _ in children}
    for name, start, end in children:
        if name not in LEGACY:
            continue
        new = LEGACY[name]
        if new in existing:
            print(
                f"WARN: {path}: leaving legacy key '{name}' — '{new}' is already present",
                file=sys.stderr,
            )
            continue
        edits.append((start, end, f'"{new}"', name, new))

    return edits


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[2] not in MODES:
        print(f"usage: {sys.argv[0]} <config> <{'|'.join(MODES)}>", file=sys.stderr)
        return 2

    path, mode = sys.argv[1], sys.argv[2]
    try:
        with open(path) as fh:
            text = fh.read()
    except OSError:
        return 0

    edits = _plan(text, mode, path)
    if not edits:
        return 0

    for start, end, replacement, _, _ in sorted(edits, key=lambda edit: edit[0], reverse=True):
        text = text[:start] + replacement + text[end:]

    with open(path, "w") as fh:
        fh.write(text)

    for _, _, _, old, new in edits:
        print(f"{old} -> {new}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
