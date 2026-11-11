#!/usr/bin/env python3
"""Migrate flat workspace keys into the `workspace` block.

A dev-bot config used to carry `commit_memory`, `workflow` and the boolean
`monorepo` at the root (and, before that, `supervisor` and `worktrees`). They
now live in one `workspace` object:

    "workspace": {
      "type": "repo",           // repo | polyrepo
      "commit_memory": false,
      "workflow": "worktrees"
    }

`monorepo: true` (and its predecessor `supervisor: true`) becomes
`type: "polyrepo"` and is dropped otherwise, because the global config
documents `repo` as the default. `worktrees: true` becomes
`workflow: "worktrees"`, `false` becomes `"trunk"`. An explicit `commit_memory`
or `workflow` is carried across byte for byte, as an override.

The file is tokenized rather than matched with a regex: comments and string
contents are skipped, only the top-level properties involved are rewritten, and
every other byte is preserved. The result is parsed before an atomic swap, so a
config is never left unparseable, and a symlinked config is rewritten through to
its target.

A file that already carries the nested key it would write is left untouched and
reported: the migration cannot tell which value the user meant.

Usage:
  migrate_workspace_config.py [--down] <config>...

`--down` reverses the migration: the `workspace` block is flattened back into
the root `monorepo` / `commit_memory` / `workflow` keys.

Output (stdout), one line per file that needed attention:
  MIGRATED: <path>
  NEEDS_ATTENTION: <path> <reason>

Exit codes:
  0 — migrated, or nothing to migrate
  1 — a config could not be read, or needs a manual fix
"""

import json
import os
import pathlib
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from read_jsonc import load_jsonc  # noqa: E402

LEGACY_KEYS = ("commit_memory", "workflow", "worktrees", "monorepo", "supervisor")
NESTED_KEY_FOR = {
    "commit_memory": "commit_memory",
    "workflow": "workflow",
    "worktrees": "workflow",
    "monorepo": "type",
    "supervisor": "type",
}
WORKFLOW_FOR = {"true": "worktrees", "false": "trunk"}


class NeedsAttention(Exception):
    """The file cannot be migrated without guessing or dropping intent."""


class Property:
    """A top-level property: its decoded key and the byte spans around it."""

    def __init__(self, key, key_start, line_start, value_start, value_end, end):
        self.key = key
        self.key_start = key_start
        self.line_start = line_start
        self.value_start = value_start
        self.value_end = value_end
        self.end = end


def _skip_space_and_comments(text, index):
    size = len(text)
    while index < size:
        if text[index] in " \t\r\n":
            index += 1
        elif text.startswith("//", index):
            newline = text.find("\n", index)
            index = size if newline == -1 else newline + 1
        elif text.startswith("/*", index):
            close = text.find("*/", index + 2)
            index = size if close == -1 else close + 2
        else:
            break
    return index


def _string_end(text, index):
    """Index just past the string literal that starts at `index`."""
    size = len(text)
    index += 1
    while index < size:
        if text[index] == "\\":
            index += 2
            continue
        if text[index] == '"':
            return index + 1
        index += 1
    raise ValueError("unterminated string")


def _value_end(text, index):
    """(end of the value token, index of the comma or brace that ends it).

    Two indices, not one: a comment may sit between the value and its
    terminator (`true // note` then a comma), and trimming the raw span back
    from the terminator would walk straight into that comment.
    """
    size = len(text)
    depth = 0
    token_end = index
    while index < size:
        if text.startswith("//", index):
            newline = text.find("\n", index)
            index = size if newline == -1 else newline + 1
        elif text.startswith("/*", index):
            close = text.find("*/", index + 2)
            index = size if close == -1 else close + 2
        elif text[index] == '"':
            index = _string_end(text, index)
            token_end = index
        elif text[index] in "{[":
            depth += 1
            index += 1
            token_end = index
        elif text[index] in "}]":
            if depth == 0:
                return token_end, index
            depth -= 1
            index += 1
            token_end = index
        elif text[index] == "," and depth == 0:
            return token_end, index
        else:
            if not text[index].isspace():
                token_end = index + 1
            index += 1
    return token_end, index


def _first_object(text):
    """Index of the first `{` that is not inside a comment or a string."""
    index = _skip_space_and_comments(text, 0)
    return index if text[index : index + 1] == "{" else -1


def _line_start(text, index):
    newline = text.rfind("\n", 0, index)
    return 0 if newline == -1 else newline + 1


def scan(text, open_brace):
    """Top-level properties of the object opened at `open_brace`, and its close."""
    size = len(text)
    props = []
    index = _skip_space_and_comments(text, open_brace + 1)
    while index < size:
        if text[index] == "}":
            return props, index
        start = _line_start(text, index)
        key_start = index
        key_end = _string_end(text, index)
        key = json.loads(text[index:key_end])
        index = _skip_space_and_comments(text, key_end)
        if index >= size or text[index] != ":":
            raise ValueError(f"expected ':' after key {key!r}")
        value_start = _skip_space_and_comments(text, index + 1)
        value_end, terminator = _value_end(text, value_start)
        end = terminator + 1 if text[terminator : terminator + 1] == "," else terminator
        props.append(Property(key, key_start, start, value_start, value_end, end))
        index = _skip_space_and_comments(text, end)
    raise ValueError("unterminated object")


def _pairs(props, text):
    """(nested key, raw value) pairs the legacy properties map to.

    Two legacy keys can resolve to one nested key (`workflow` and the retired
    `worktrees`); that is ambiguous and must be reported, never guessed.
    """
    pairs = []
    written = set()
    for prop in props:
        if prop.key not in LEGACY_KEYS:
            continue
        raw = text[prop.value_start : prop.value_end].strip()
        if prop.key in ("monorepo", "supervisor"):
            if raw not in ("true", "false"):
                raise NeedsAttention(f'has an unrecognised "{prop.key}" value {raw}')
            # `false` is an explicit repo choice and must survive even when the
            # global default is a polyrepo, so it is written, never dropped.
            _add(pairs, written, "type", '"polyrepo"' if raw == "true" else '"repo"', prop.key)
        elif prop.key == "worktrees":
            workflow = WORKFLOW_FOR.get(raw)
            if not workflow:
                raise NeedsAttention(f'has an unrecognised "worktrees" value {raw}')
            _add(pairs, written, "workflow", f'"{workflow}"', prop.key)
        else:
            _add(pairs, written, NESTED_KEY_FOR[prop.key], raw, prop.key)
    return pairs


def _add(pairs, written, key, raw, legacy):
    if key in written:
        raise NeedsAttention(f'sets both "{legacy}" and another key for `{key}`')
    written.add(key)
    pairs.append((key, raw))


def _line_indent(text, line_start):
    """The whitespace that indents the line beginning at `line_start`."""
    index = line_start
    while index < len(text) and text[index] in " \t":
        index += 1
    return text[line_start:index] or "  "


def _render_block(indent, pairs, trailing_comma):
    inner = indent + "  "
    lines = [indent + '"workspace": {']
    for position, (key, raw) in enumerate(pairs):
        comma = "," if position < len(pairs) - 1 else ""
        lines.append(f'{inner}"{key}": {raw}{comma}')
    lines.append(indent + "}" + ("," if trailing_comma else ""))
    return "\n".join(lines)


def _runs(indices):
    """Group ascending property indices into (first, last) contiguous runs."""
    runs = []
    for index in indices:
        if runs and index == runs[-1][1] + 1:
            runs[-1] = (runs[-1][0], index)
        else:
            runs.append((index, index))
    return runs


def _cut_span(text, props, first, last):
    """The byte span to delete for the contiguous legacy run [first..last].

    A key that opens its own line takes the whole line (and the newline before
    it) with it; one sharing a line with another property is cut from the key,
    because that line's other content must survive.
    """
    prop = props[first]
    start = prop.key_start
    if prop.line_start > 0 and text[prop.line_start : prop.key_start].strip() == "":
        start = prop.line_start
        if text[start - 1 : start] == "\n":
            start -= 1
    return start, props[last].end


def _drop_stray_comma(text):
    """Remove a comma left dangling before the closing brace by a removal."""
    props, _ = scan(text, _first_object(text))
    if props and text[props[-1].end - 1 : props[-1].end] == ",":
        return text[: props[-1].end - 1] + text[props[-1].end :]
    return text


def migrate(path):
    """Rewrite one config in place. Returns (changed, needs_attention_reason)."""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    open_brace = _first_object(text)
    if open_brace == -1:
        return False, "no JSON object"

    props, _ = scan(text, open_brace)
    legacy = [index for index, prop in enumerate(props) if prop.key in LEGACY_KEYS]
    if not legacy:
        return False, ""

    try:
        pairs = _pairs([props[index] for index in legacy], text)
    except NeedsAttention as error:
        return False, str(error)
    order = {"type": 0, "commit_memory": 1, "workflow": 2}
    pairs.sort(key=lambda pair: order.get(pair[0], 99))
    workspace = next((prop for prop in props if prop.key == "workspace"), None)

    existing = ""
    if workspace is not None:
        existing = text[workspace.value_start : workspace.value_end]
        if not existing.lstrip().startswith("{"):
            return False, "`workspace` is not an object"
        # Every legacy key claims its nested counterpart even when it writes
        # nothing (`monorepo: false` is dropped), so a nested value the user set
        # deliberately is a conflict, not something to override silently.
        nested, _ = scan(existing, existing.find("{"))
        nested_keys = {prop.key for prop in nested}
        targets = {NESTED_KEY_FOR[props[index].key] for index in legacy}
        clash = sorted(key for key in targets if key in nested_keys)
        if clash:
            return False, f"sets both a root key and workspace.{clash[0]}"

    runs = _runs(legacy)
    edits = []

    if workspace is not None and pairs:
        indent = _line_indent(text, workspace.line_start)
        inner = indent + "  "
        nested, _ = scan(existing, existing.find("{"))
        lines = [f'{inner}"{key}": {raw}' for key, raw in pairs]
        if nested:
            insert_at = workspace.value_start + nested[-1].end
            separated = existing[nested[-1].end - 1 : nested[-1].end] == ","
            addition = ("" if separated else ",") + "\n" + ",\n".join(lines)
        else:
            insert_at = workspace.value_start + existing.find("{") + 1
            addition = "\n" + ",\n".join(lines) + "\n" + indent
        edits.append((insert_at, insert_at, addition))
    elif workspace is None and pairs:
        indent = _line_indent(text, props[runs[0][0]].line_start)
        block = _render_block(indent, pairs, trailing_comma=True)
        edits.append((_cut_span(text, props, *runs[0])[0],
                      _cut_span(text, props, *runs[0])[1],
                      "\n" + block))

    replaced_first = workspace is None and bool(pairs)
    for index, run in enumerate(runs):
        if replaced_first and index == 0:
            continue
        start, end = _cut_span(text, props, *run)
        edits.append((start, end, ""))

    # Right to left, so every span still refers to the original offsets.
    for start, end, replacement in sorted(edits, key=lambda edit: edit[0], reverse=True):
        text = text[:start] + replacement + text[end:]

    text = _drop_stray_comma(text)

    temp = f"{os.path.realpath(path)}.migrate"
    with open(temp, "w", encoding="utf-8") as handle:
        handle.write(text)
    load_jsonc(temp)
    os.chmod(temp, os.stat(os.path.realpath(path)).st_mode)
    os.replace(temp, os.path.realpath(path))
    return True, ""


def migrate_down(path):
    """Flatten the `workspace` block back into root keys. Returns (changed, reason)."""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    open_brace = _first_object(text)
    if open_brace == -1:
        return False, "no JSON object"

    props, _ = scan(text, open_brace)
    workspaces = [index for index, prop in enumerate(props) if prop.key == "workspace"]
    if not workspaces:
        return False, ""
    if len(workspaces) > 1:
        return False, f"`workspace` appears {len(workspaces)} times"

    prop = props[workspaces[0]]
    clash = sorted({item.key for item in props if item.key in LEGACY_KEYS})
    if clash:
        return False, f'sets both "workspace" and root {", ".join(clash)}'

    try:
        data = load_jsonc(path)
    except Exception as error:  # noqa: BLE001
        return False, f"cannot parse ({error})"
    nested = data.get("workspace")
    if not isinstance(nested, dict):
        return False, "`workspace` is not an object"

    # Never drop a key the down migration does not understand: a later release
    # or a hand-written extension would be lost on rollback.
    supported = {"type", "commit_memory", "workflow"}
    unsupported = sorted(set(nested) - supported)
    if unsupported:
        return False, f"has unsupported workspace keys: {', '.join(unsupported)}"

    pairs = []
    if "type" in nested:
        kind = nested["type"]
        if kind not in ("repo", "polyrepo"):
            return False, f"has an unrecognised workspace.type {kind!r}"
        pairs.append(("monorepo", "true" if kind == "polyrepo" else "false"))
    if "commit_memory" in nested:
        pairs.append(("commit_memory", json.dumps(nested["commit_memory"])))
    if "workflow" in nested:
        pairs.append(("workflow", json.dumps(nested["workflow"])))

    indent = _line_indent(text, prop.line_start)
    trailing = text[prop.end - 1 : prop.end] == ","
    own_line = text[prop.line_start : prop.key_start].strip() == ""
    if pairs:
        lines = []
        for position, (key, raw) in enumerate(pairs):
            comma = "," if position < len(pairs) - 1 or trailing else ""
            # The first line inherits the existing indent when the block starts
            # a line; on a shared line the prefix is already in the text.
            prefix = indent if (own_line or position > 0) else ""
            lines.append(f'{prefix}"{key}": {raw}{comma}')
        replacement = "\n".join(lines)
    else:
        replacement = ""

    start = prop.line_start if own_line else prop.key_start
    end = prop.end
    if not pairs and own_line and start > 0 and text[start - 1 : start] == "\n":
        start -= 1

    text = text[:start] + replacement + text[end:]
    text = _drop_stray_comma(text)

    temp = f"{os.path.realpath(path)}.migrate"
    with open(temp, "w", encoding="utf-8") as handle:
        handle.write(text)
    load_jsonc(temp)
    os.chmod(temp, os.stat(os.path.realpath(path)).st_mode)
    os.replace(temp, os.path.realpath(path))
    return True, ""


def main():
    args = sys.argv[1:]
    down = False
    if args and args[0] == "--down":
        down = True
        args = args[1:]
    if not args:
        print("Usage: migrate_workspace_config.py [--down] <config>...", file=sys.stderr)
        return 1

    failures = 0
    for raw in args:
        if not pathlib.Path(raw).is_file():
            continue
        try:
            changed, reason = (migrate_down if down else migrate)(raw)
        except (ValueError, OSError) as error:
            print(f"NEEDS_ATTENTION: {raw} cannot parse ({error})")
            failures += 1
            continue
        if reason:
            print(f"NEEDS_ATTENTION: {raw} {reason}")
            failures += 1
        elif changed:
            print(f"MIGRATED: {raw}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
