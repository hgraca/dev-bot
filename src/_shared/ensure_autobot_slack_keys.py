#!/usr/bin/env python3
"""Add the Slack conversation keys to a project config's `autobot` block.

1.17.0 seeded the block before those keys existed, and `ensure_autobot_block.py` answers `present`
for a block it finds — so a project that ran that migration keeps a block that never mentions the
Slack conversation. This splices the three keys in as comments, the shape a fresh seed has now, so
the options are discoverable without anyone hand-writing them. A project that configures AutoBot
through a global profile (or opts out with `null`) is left alone: its keys belong in the profile.

Comment-preserving: the lines go in before the block's closing brace, so every existing comment and
key keeps its place.

Usage:
  ensure_autobot_slack_keys.py <project-config.jsonc>

Prints one of:
  present   every key is already mentioned, or there is no inline block to extend
  injected  the missing keys were written

Exit codes: 0 on present/injected, 1 when the file cannot be read or written.
"""

import errno
import os
import sys
import tempfile

from ensure_autobot_block import find_top_level_object, inject, last_significant
from read_jsonc import load_jsonc

KEYS = ("poll_slack", "slack_user_email", "slack_bot_token")

HEADER = "// Talk to one person over Slack. Both or neither; both when poll_slack is on."
LINES = {
    "poll_slack": '// "poll_slack": false,',
    "slack_user_email": '// "slack_user_email": "you@example.com",',
    "slack_bot_token": '// "slack_bot_token": "${SLACK_BOT_TOKEN}",',
}


def _skip_string(text, i):
    """Index just past the string literal opening at i."""
    j = i + 1
    while j < len(text):
        if text[j] == "\\":
            j += 2
        elif text[j] == '"':
            return j + 1
        else:
            j += 1
    return j


def _skip_comment(text, i):
    """Index just past the comment opening at i, or len(text) when it never ends."""
    if text[i : i + 2] == "//":
        j = text.find("\n", i)
        return len(text) if j == -1 else j
    j = text.find("*/", i + 2)
    return len(text) if j == -1 else j + 2


def _skip_gap(text, i, limit):
    """Index of the next character that is neither whitespace nor a comment; limit when none."""
    while i < limit:
        if text[i].isspace():
            i += 1
            continue
        if text[i : i + 2] in ("//", "/*"):
            i = _skip_comment(text, i)
            continue
        return i
    return limit


def matching_brace(text, open_index):
    """Index of the `}` closing the `{` at open_index, or -1 when it never closes."""
    depth = 0
    i, n = open_index, len(text)
    while i < n:
        ch = text[i]
        if ch == '"':
            i = _skip_string(text, i)
            continue
        if text[i : i + 2] in ("//", "/*"):
            i = _skip_comment(text, i)
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def find_autobot_object(text):
    """Brace span of the top-level `autobot` object, or (-1, -1) when absent or not an object.

    Only a direct child of the top-level object counts, so a `"autobot"` key inside `modules` (a
    boolean) can never be mistaken for the block.
    """
    start, end = find_top_level_object(text)
    if start == -1 or end == -1:
        return (-1, -1)
    depth = 1
    i, n = start + 1, end
    while i < n:
        ch = text[i]
        if ch == '"':
            close = _skip_string(text, i)
            if depth == 1 and text[i:close] == '"autobot"':
                colon = _skip_gap(text, close, n)
                if colon < n and text[colon] == ":":
                    value = _skip_gap(text, colon + 1, n)
                    if value < n and text[value] == "{":
                        brace = matching_brace(text, value)
                        if brace != -1:
                            return (value, brace)
            i = close
            continue
        if text[i : i + 2] in ("//", "/*"):
            i = _skip_comment(text, i)
            continue
        if ch in "{[":
            depth += 1
        elif ch in "}]":
            depth -= 1
        i += 1
    return (-1, -1)


def closing_indent(text, close_index):
    """The whitespace that indents the line holding the block's closing brace."""
    line_start = text.rfind("\n", 0, close_index) + 1
    line = text[line_start:close_index]
    return line[: len(line) - len(line.lstrip())]


def child_indent(text, open_index, close_index):
    """Indent for a new line inside the block: that of its last existing line."""
    for line in reversed(text[open_index + 1 : close_index].splitlines()):
        if line.strip():
            return line[: len(line) - len(line.lstrip())]
    return closing_indent(text, close_index) + "  "


def _comment_body(text, i):
    """The body of the comment opening at i, and the index just past it."""
    if text[i : i + 2] == "//":
        end = text.find("\n", i)
        if end == -1:
            return text[i + 2 :], len(text)
        return text[i + 2 : end], end
    end = text.find("*/", i + 2)
    if end == -1:
        return text[i + 2 :], len(text)
    return text[i + 2 : end], end + 2


def _comment_keys(body):
    """The keys a comment names as `"key": value` — the commented-out lines this helper writes.

    The whole body is scanned, not just its first token, so a multiline block comment (whose lines
    start with `*`) and a single line carrying several entries are both recognised.
    """
    found = set()
    i, n = 0, len(body)
    while i < n:
        if body[i] == '"':
            end = _skip_string(body, i)
            literal = body[i:end]
            if literal.endswith('"') and literal[1:-1] in KEYS:
                if body[end:].lstrip().startswith(":"):
                    found.add(literal[1:-1])
            i = end
            continue
        i += 1
    return found


def mentioned_keys(region):
    """The keys the block already names — as a direct property, or as a commented-out line.

    Matching the bare name would count a value (`"jira_assignees": ["poll_slack"]`) or a sentence in
    a comment, and then the discoverability lines would be withheld from the block they belong to.
    Counting any nested key would do the same: `{"connection": {"poll_slack": true}}` is not
    `autobot.poll_slack`. A key counts only as a direct child of the block, followed by `:`, and a
    commented one only where its comment names it as `"key": value`.

    `region` is the block including its opening brace, so its direct children sit at depth 1.
    """
    found = set()
    i, n = 0, len(region)
    depth = 0
    while i < n:
        ch = region[i]
        if ch == '"':
            end = _skip_string(region, i)
            literal = region[i:end]
            if depth == 1 and literal.endswith('"') and literal[1:-1] in KEYS:
                # A comment may sit between the name and its colon, and JSONC allows it.
                colon = _skip_gap(region, end, n)
                if colon < n and region[colon] == ":":
                    found.add(literal[1:-1])
            i = end
            continue
        if region[i : i + 2] in ("//", "/*"):
            # A nested comment (`autobot.connection`) does not configure this block's key.
            body, end = _comment_body(region, i)
            if depth == 1:
                found |= _comment_keys(body)
            i = end
            continue
        if ch in "{[":
            depth += 1
        elif ch in "}]":
            depth -= 1
        i += 1
    return found


def insertion_lines(region, indent):
    """The commented key lines still missing from the block, header included when poll_slack is new."""
    mentioned = mentioned_keys(region)
    missing = [key for key in KEYS if key not in mentioned]
    if not missing:
        return []
    lines = [f"{indent}{HEADER}"] if "poll_slack" in missing else []
    return lines + [f"{indent}{LINES[key]}" for key in missing]


def splice(text, open_index, close_index, lines, indent):
    """Return the text with `lines` inserted before the block's closing brace."""
    body = text[open_index + 1 : close_index]
    # A key the user uncomments needs a comma in front of it, so close the last pair now. The
    # separator belongs immediately after the last value, before any trailing comment.
    last = last_significant(body)
    if last >= 0 and body[last] != ",":
        body = body[: last + 1] + "," + body[last + 1 :]
    return (
        text[: open_index + 1]
        + body.rstrip()
        + "\n"
        + "\n".join(lines)
        + "\n"
        + indent
        + text[close_index:]
    )


def write_atomic(path, text):
    """Write beside the target and replace, so an interrupted run cannot truncate a project config."""
    # Replacing only needs the directory to be writable, so a read-only config would otherwise be
    # rewritten without complaint. The migration promises to fail on an unwritable config instead.
    try:
        mode = os.stat(path).st_mode & 0o777
    except OSError:
        mode = 0o644
    if (mode & 0o222) == 0 or not os.access(path, os.W_OK):
        raise PermissionError(errno.EACCES, "config is not writable", path)
    handle = tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=os.path.dirname(path), delete=False
    )
    try:
        handle.write(text)
        handle.close()
        # The temp file is created 0600; replacing a 0644 config with it would silently change who
        # can read the project's configuration.
        os.chmod(handle.name, mode)
        os.replace(handle.name, path)
    except OSError:
        os.unlink(handle.name)
        raise


def main(argv):
    if len(argv) != 2:
        print("usage: ensure_autobot_slack_keys.py <project-config.jsonc>", file=sys.stderr)
        return 1
    path = argv[1]
    try:
        config = load_jsonc(path)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except (OSError, ValueError) as error:
        print(f"WARN: cannot read {path}: {error}", file=sys.stderr)
        return 1

    if not isinstance(config, dict):
        print(f"WARN: no top-level object in {path}", file=sys.stderr)
        return 1

    if "autobot" in config and not isinstance(config["autobot"], dict):
        # A profile name or an explicit null: the block is not here, so the keys are not either.
        print("present")
        return 0

    if "autobot" not in config:
        # No block at all: seed the whole thing, which already carries the Slack lines.
        updated = inject(text)
        if updated is None:
            print(f"WARN: no top-level object in {path}", file=sys.stderr)
            return 1
    else:
        open_index, close_index = find_autobot_object(text)
        if open_index == -1:
            print(f"WARN: no inline autobot block in {path}", file=sys.stderr)
            return 1
        lines = insertion_lines(
            text[open_index:close_index], child_indent(text, open_index, close_index)
        )
        if not lines:
            print("present")
            return 0
        updated = splice(
            text, open_index, close_index, lines, closing_indent(text, close_index)
        )

    try:
        write_atomic(path, updated)
    except OSError as error:
        print(f"WARN: cannot write {path}: {error}", file=sys.stderr)
        return 1
    print("injected")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
