#!/usr/bin/env python3
"""ownership — unit-level ownership and churn from git blame.

Approximate by design (AD-5): blame runs over the *current* unit line spans, so a
unit's history is inferred from the lines that survive in it today, not from
reconstructed historical ASTs.
"""

from __future__ import annotations

import hashlib

import gitmine


def unit_key(path: str, kind: str, name: str) -> str:
    """A stable id for a unit that survives line shifts."""
    return hashlib.sha1(("%s|%s|%s" % (path, kind, name)).encode("utf-8")).hexdigest()[:16]


def aggregate_units(blame_lines: list, units: list) -> tuple:
    """Map blame lines onto unit spans → (ownership_rows, churn_rows)."""
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
            author = blame.get("author_email") or blame.get("author_name") or ""
            authors[author] = authors.get(author, 0) + 1
            hashes.add(blame.get("hash", ""))
            date = blame.get("date") or ""
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


def unit_blame(repo: str, units: list) -> tuple:
    """Blame each file once and aggregate every unit's span on it."""
    by_path = {}
    for unit in units:
        by_path.setdefault(unit["path"], []).append(unit)

    ownership_rows = []
    churn_rows = []
    for path, unit_list in by_path.items():
        result = gitmine.mine_blame(repo, path)
        lines = result.get("lines", []) if isinstance(result, dict) else []
        rows, churn = aggregate_units(lines, unit_list)
        ownership_rows += rows
        churn_rows += churn

    return ownership_rows, churn_rows
