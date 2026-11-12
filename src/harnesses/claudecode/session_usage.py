#!/usr/bin/env python3
"""Read the live context occupancy of one claudecode session.

Claude Code appends one JSONL transcript per session under
``<projects>/<slug>/<session>.jsonl``. Every assistant line repeats the
message's ``usage``; the last one is the current window: non-cached input,
cache reads, cache writes and the produced output.
"""
from __future__ import annotations

import glob
import json
import os
import re

PROJECTS_ENV = "CLAUDE_PROJECTS_DIR"
DEFAULT_PROJECTS = "~/.claude/projects"
DEFAULT_PROVIDER = "anthropic"

_SESSION_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

_USAGE_KEYS = (
    "input_tokens",
    "cache_read_input_tokens",
    "cache_creation_input_tokens",
    "output_tokens",
)


def projects_dir(path=None):
    path = path or os.environ.get(PROJECTS_ENV)
    return os.path.expanduser(path) if path else os.path.expanduser(DEFAULT_PROJECTS)


def find_transcript(session_id, root=None):
    # The id becomes part of a glob: a path or wildcard must never select
    # another transcript.
    if not _SESSION_ID_RE.match(session_id or "") or ".." in session_id:
        return None
    root = projects_dir(root)
    for pattern in (
        os.path.join(root, "*", f"{session_id}.jsonl"),
        os.path.join(root, "*", "**", f"{session_id}.jsonl"),
    ):
        matches = sorted(glob.glob(pattern, recursive=True))
        if matches:
            return matches[0]
    return None


def _last_assistant(path):
    last = None
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(entry, dict) or entry.get("type") != "assistant":
                    continue
                usage = (entry.get("message") or {}).get("usage")
                if isinstance(usage, dict):
                    last = entry
    except OSError:
        return None
    return last


def gather(session_id, root=None):
    path = find_transcript(session_id, root)
    if path is None:
        return {"error": "unknown-session", "session": session_id}
    entry = _last_assistant(path)
    if entry is None:
        return {"error": "no-usage", "session": session_id}
    usage = entry["message"]["usage"]
    tokens = sum(int(usage.get(key) or 0) for key in _USAGE_KEYS)
    if tokens <= 0:
        return {"error": "no-usage", "session": session_id}
    message = entry.get("message") or {}
    return {
        "session": session_id,
        "provider": DEFAULT_PROVIDER,
        "model": str(message.get("model") or entry.get("model") or ""),
        "context_tokens": tokens,
    }
