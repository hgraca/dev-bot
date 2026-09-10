#!/usr/bin/env python3
"""Shared helpers for ``devbot stats`` adapters.

Small, harness-independent argument-normalisation helpers used by the harness
adapters (opencode, claudecode) when aggregating tool arguments.
"""
from __future__ import annotations

import re
import shlex


def _is_bare_cd(line: str) -> bool:
    """True if the line is just ``cd <path>`` with no trailing command."""
    match = re.match(r"^\s*cd\s+", line)
    if not match:
        return False
    rest = line[match.end():]
    return "&&" not in rest and ";" not in rest


def strip_leading_cd(line: str) -> str:
    """Drop a leading ``cd <path> && `` (or ``; ``) from a single line."""
    while True:
        match = re.match(r"^\s*cd\s+", line)
        if not match:
            return line
        rest = line[match.end():]
        positions = [p for p in (rest.find("&&"), rest.find(";")) if p != -1]
        if not positions:
            return line
        idx = min(positions)
        sep_len = 2 if rest[idx:idx + 2] == "&&" else 1
        line = rest[idx + sep_len:].strip()


def bash_value(command) -> str:
    """Normalise a bash command to ``program subcommand`` (first two tokens).

    Agents prefix the project dir in several shapes — ``cd <path> && cmd``, a
    leading ``cd <path>`` line, or a leading comment line — all of which are
    stripped before the first two tokens are taken.
    """
    lines = (command or "").strip().splitlines()
    idx = 0
    while idx < len(lines):
        line = lines[idx].strip()
        if not line or line.startswith("#") or _is_bare_cd(line):
            idx += 1
            continue
        break
    line = strip_leading_cd(lines[idx].strip()) if idx < len(lines) else ""
    try:
        tokens = shlex.split(line)
    except ValueError:
        tokens = line.split()
    return " ".join(tokens[:2])
