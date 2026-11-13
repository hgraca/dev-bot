#!/usr/bin/env python3
"""Ensure a project config carries the default `autobot` block.

Comment-preserving: the block is spliced in as text before the top-level closing brace, so an
operator's comments and key ordering survive untouched. A file that already has the key — including
an explicit `null` — is left alone.

Usage:
  ensure_autobot_block.py <project-config.jsonc>

Prints one of:
  present   the key already exists, nothing changed
  injected  the default block was added

Exit codes: 0 on present/injected, 1 when the file cannot be read or has no top-level object.
"""

import os
import sys
import tempfile

from read_jsonc import load_jsonc

BLOCK = """  // AutoBot: scheduled agent work for this project. Everything is off by default.
  "autobot": {
    "poll_jira": false,
    "poll_github": false,
    // The Jira connection is per project, and ${VAR} is resolved at tick time from the
    // environment the cron entry sources (~/.config/devbot/autobot.env).
    // "jira_base_url": "https://getinfo.atlassian.net",
    // "jira_email": "you@example.com",
    // this is needed in the cron job: set JIRA_API_TOKEN in ~/.config/devbot/autobot.env
    // (export JIRA_API_TOKEN=paste-the-token-here) or put the token directly here
    // "jira_api_token": "${JIRA_API_TOKEN}",
    "prompts": []
  }"""


def find_top_level_object(text):
    """Return (index of the top-level '{', index of its matching '}') or (-1, -1).

    Skips strings and both comment forms, so braces inside either are ignored.
    """
    i, n = 0, len(text)
    start = -1
    depth = 0
    while i < n:
        ch = text[i]
        if ch == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                elif text[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            i = j
            continue
        if text[i : i + 2] == "//":
            j = text.find("\n", i)
            if j == -1:
                break
            i = j
            continue
        if text[i : i + 2] == "/*":
            j = text.find("*/", i + 2)
            if j == -1:
                break
            i = j + 2
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


def last_significant(text):
    """Index of the last character outside strings, comments and whitespace; -1 when none."""
    i, n, last = 0, len(text), -1
    while i < n:
        if text[i] == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                elif text[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            last = j - 1
            i = j
            continue
        if text[i : i + 2] == "//":
            j = text.find("\n", i)
            if j == -1:
                break
            i = j
            continue
        if text[i : i + 2] == "/*":
            j = text.find("*/", i + 2)
            if j == -1:
                break
            i = j + 2
            continue
        if not text[i].isspace():
            last = i
        i += 1
    return last


def inject(text):
    """Return the text with the default block added, or None when it cannot be spliced."""
    start, end = find_top_level_object(text)
    if start == -1 or end == -1:
        return None
    body = text[start + 1 : end].rstrip()
    if body == "":
        return text[: start + 1] + "\n" + BLOCK + "\n" + text[end:]
    # The separator goes immediately after the last value, before any trailing comment — otherwise it
    # lands inside the comment and the appended block has no comma in front of it.
    last = last_significant(body)
    if last >= 0 and body[last] != ",":
        body = body[: last + 1] + "," + body[last + 1 :]
    return text[: start + 1] + body + "\n" + BLOCK + "\n" + text[end:]


def main(argv):
    if len(argv) != 2:
        print("usage: ensure_autobot_block.py <project-config.jsonc>", file=sys.stderr)
        return 1
    path = argv[1]
    try:
        config = load_jsonc(path)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except (OSError, ValueError) as error:
        print(f"WARN: cannot read {path}: {error}", file=sys.stderr)
        return 1
    if isinstance(config, dict) and "autobot" in config:
        print("present")
        return 0
    updated = inject(text)
    if updated is None:
        print(f"WARN: no top-level object in {path}", file=sys.stderr)
        return 1
    try:
        # Write beside the target and replace, so an interrupted run cannot truncate a project config.
        handle = tempfile.NamedTemporaryFile(
            "w", encoding="utf-8", dir=os.path.dirname(path), delete=False
        )
        try:
            handle.write(updated)
            handle.close()
            os.replace(handle.name, path)
        except OSError:
            os.unlink(handle.name)
            raise
    except OSError as error:
        print(f"WARN: cannot write {path}: {error}", file=sys.stderr)
        return 1
    print("injected")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
