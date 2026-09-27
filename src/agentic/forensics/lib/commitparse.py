#!/usr/bin/env python3
"""commitparse — Conventional Commits parsing for the forensics module.

The commit-history intelligence assumes a Conventional Commits convention
(`type(scope)!: subject`); a message that does not match is kept as
non-conventional rather than dropped, so compliance can be measured.
"""

from __future__ import annotations

import re

_HEADER = re.compile(r"^([a-zA-Z]+)(?:\(([^)]*)\))?(!)?:\s*(.+)$")
_TICKET = re.compile(r"\b([A-Z][A-Z0-9]*-\d+)\b")

FIX_TYPES = {"fix", "hotfix", "bugfix"}


def parse_message(message: str) -> dict:
    """Split a commit message into type, scope, ticket, breaking and compliance."""
    text = message or ""
    header = text.splitlines()[0].strip() if text.splitlines() else ""
    match = _HEADER.match(header)
    breaking = "BREAKING CHANGE" in text

    if match:
        ctype = match.group(1).lower()
        scope = (match.group(2) or "").strip()
        breaking = breaking or bool(match.group(3))
        conventional = True
    else:
        ctype, scope, conventional = "", "", False

    ticket_match = _TICKET.search(scope) or _TICKET.search(header)
    return {
        "type": ctype,
        "scope": scope,
        "ticket": ticket_match.group(1) if ticket_match else "",
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
