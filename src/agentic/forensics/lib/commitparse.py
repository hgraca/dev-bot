#!/usr/bin/env python3
"""commitparse — Conventional Commits parsing for the forensics module.

The commit-history intelligence assumes a Conventional Commits convention
(`type(scope)!: subject`); a message that does not match is kept as
non-conventional rather than dropped, so compliance can be measured.
"""

from __future__ import annotations

import re

_HEADER = re.compile(r"^([a-z]+)(?:\(([^)]*)\))?(!)?:\s*(.+)$")
_TICKET = re.compile(r"\b([A-Z][A-Z0-9]*-\d+)\b")

# Only a known, lowercase type is a Conventional Commit — this rejects `http:`,
# `WIP:` or `Fix:` (which would otherwise smuggle into the fix/hotfix set).
TYPES = {"feat", "fix", "hotfix", "bugfix", "chore", "docs", "style", "refactor", "perf", "test", "build", "ci", "revert"}

FIX_TYPES = {"fix", "hotfix", "bugfix"}


def parse_message(message: str) -> dict:
    """Split a commit message into type, scope, ticket, breaking and compliance."""
    text = message or ""
    lines = text.splitlines()
    header = lines[0].strip() if lines else ""
    match = _HEADER.match(header)
    breaking = "BREAKING CHANGE" in text

    if match and match.group(1) in TYPES:
        ctype = match.group(1)
        scope = (match.group(2) or "").strip()
        breaking = breaking or bool(match.group(3))
        conventional = True
    else:
        ctype, scope, conventional = "", "", False

    ticket = ""
    if scope:
        ticket_match = _TICKET.search(scope)
        ticket = ticket_match.group(1) if ticket_match else ""

    return {
        "type": ctype,
        "scope": scope,
        "ticket": ticket,
        "breaking": 1 if breaking else 0,
        "conventional": conventional,
    }


def enrich(commits: list) -> list:
    """Return the commits with their parsed conventional fields merged in."""
    enriched = []
    for commit in commits:
        row = dict(commit)
        row.update(parse_message(commit.get("message", "")))
        enriched.append(row)
    return enriched


def is_fix(commit_type: str) -> bool:
    return commit_type in FIX_TYPES
