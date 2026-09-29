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

# Tokens shaped like a ticket key but naming a standard or identifier instead —
# `SHA-256`, `ISO-8601`, `CVE-2021` and friends would otherwise become tickets.
_TICKET_DENY = frozenset(
    {
        "UTF",
        "SHA",
        "ISO",
        "CVE",
        "RFC",
        "HTTP",
        "HTTPS",
        "AES",
        "TLS",
        "SSL",
        "MD",
        "IPV",
        "UUID",
        "BASE64",
        "ASCII",
        "UNICODE",
    }
)
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

    # Leftmost wins, so a ticket in the scope beats one in the subject; a denied
    # token is skipped rather than stopping the scan.
    ticket = ""
    for candidate in _TICKET.findall(header):
        if candidate.split("-", 1)[0] not in _TICKET_DENY:
            ticket = candidate
            break

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
