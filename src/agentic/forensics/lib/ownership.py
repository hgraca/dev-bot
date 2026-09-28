#!/usr/bin/env python3
"""ownership — unit-level ownership and churn from git blame.

Approximate by design (AD-5): blame runs over the *current* unit line spans, so a
unit's history is inferred from the lines that survive in it today, not from
reconstructed historical ASTs.

Ownership is cumulative and anchored at the window's *end* date: a line written
after the anchor did not exist then, so it is not attributed. The window's start
does not bind ownership — authorship is not a windowed quantity.
"""

from __future__ import annotations

import datetime
import hashlib

import gitmine


def unit_key(path: str, kind: str, name: str) -> str:
    """A stable id for a unit that survives line shifts."""
    return hashlib.sha1(("%s|%s|%s" % (path, kind, name)).encode("utf-8")).hexdigest()[:16]


def _utc(value: str):
    """Parse an ISO-8601 blame timestamp to UTC, or None (a naive value is UTC)."""
    try:
        moment = datetime.datetime.fromisoformat(value)
    except (ValueError, TypeError):
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=datetime.timezone.utc)
    return moment.astimezone(datetime.timezone.utc)


def _kept_at_anchor(date: str, until) -> bool:
    """Whether a blame line existed by the anchor (the window's end date).

    An undated line is kept — it cannot be shown to postdate the anchor.
    """
    if until is None or not date:
        return True
    moment = _utc(date)
    return moment is None or moment <= until


def aggregate_units(blame_lines: list, units: list, until=None) -> tuple:
    """Map blame lines onto unit spans → (ownership_rows, churn_rows).

    ``until`` anchors attribution at the window's end date; a line introduced
    after it is dropped. ``None`` keeps the whole blame.
    """
    by_line = {line["line"]: line for line in blame_lines}
    ownership_rows = []
    churn_rows = []

    for unit in units:
        start = unit.get("start_line") or 0
        end = unit.get("end_line") or start
        authors = {}
        hashes = set()
        days = set()
        last_change = None

        for line in range(start, end + 1):
            blame = by_line.get(line)
            if blame is None:
                continue
            date = blame.get("date") or ""
            if not _kept_at_anchor(date, until):
                continue
            author = blame.get("author_email") or blame.get("author_name") or ""
            authors[author] = authors.get(author, 0) + 1
            hashes.add(blame.get("hash", ""))
            if date:
                days.add(date[:10])
                if last_change is None or date > last_change:
                    last_change = date

        key = unit_key(unit["path"], unit["kind"], unit["name"])
        for author, lines_owned in authors.items():
            ownership_rows.append(
                {
                    "unit_key": key,
                    "path": unit["path"],
                    "name": unit["name"],
                    "kind": unit["kind"],
                    "author": author,
                    "lines_owned": lines_owned,
                    "last_change": last_change,
                }
            )
        churn_rows.append(
            {
                "unit_key": key,
                "path": unit["path"],
                "name": unit["name"],
                "kind": unit["kind"],
                "commits": len(hashes),
                "active_days": len(days),
                "last_change": last_change,
            }
        )

    return ownership_rows, churn_rows


def unit_blame(repo: str, units: list, until=None) -> tuple:
    """Blame each file once and aggregate every unit's span on it."""
    by_path = {}
    for unit in units:
        by_path.setdefault(unit["path"], []).append(unit)

    ownership_rows = []
    churn_rows = []
    for path, unit_list in by_path.items():
        result = gitmine.mine_blame(repo, path)
        lines = result.get("lines", []) if isinstance(result, dict) else []
        rows, churn = aggregate_units(lines, unit_list, until)
        ownership_rows += rows
        churn_rows += churn

    return ownership_rows, churn_rows
