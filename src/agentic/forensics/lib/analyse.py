#!/usr/bin/env python3
"""analyse — views over the mined store.

Phase 1 starts with hotspots: code that is both complex and frequently changed,
ranked so the two dimensions are combined on a common scale. Ranks are
percentile-normalised rather than raw products, so one very large class cannot
dominate the list (AD-7).
"""

from __future__ import annotations

import sqlite3


def _percentile_ranks(values: list) -> list:
    """Rank values on [0, 1], aligned with the input order; ties share a slot."""
    count = len(values)
    if count == 0:
        return []
    if count == 1:
        return [1.0]
    order = sorted(range(count), key=lambda index: values[index])
    ranks = [0.0] * count
    for position, index in enumerate(order):
        ranks[index] = position / (count - 1)
    return ranks


def hotspots(conn: sqlite3.Connection, top=None) -> list:
    """Files ranked by percentile(complexity) × percentile(change rate)."""
    rows = conn.execute(
        "SELECT f.path AS path, f.commits AS commits,"
        " COALESCE(SUM(u.complexity), 0) AS complexity,"
        " COUNT(u.name) AS unit_count"
        " FROM files f LEFT JOIN units u ON u.path = f.path"
        " WHERE f.type = 'php'"
        " GROUP BY f.path"
    ).fetchall()

    rows = [row for row in rows if (row["complexity"] or 0) > 0 or (row["commits"] or 0) > 0]
    complexity_ranks = _percentile_ranks([row["complexity"] or 0 for row in rows])
    churn_ranks = _percentile_ranks([row["commits"] or 0 for row in rows])

    results = []
    for index, row in enumerate(rows):
        results.append(
            {
                "path": row["path"],
                "commits": row["commits"],
                "complexity": row["complexity"],
                "units": row["unit_count"],
                "hotspot": round(complexity_ranks[index] * churn_ranks[index], 4),
            }
        )

    results.sort(key=lambda item: (item["hotspot"], item["complexity"], item["commits"]), reverse=True)
    return results[:top] if top is not None else results


_VIEWS = {"hotspots": hotspots}
