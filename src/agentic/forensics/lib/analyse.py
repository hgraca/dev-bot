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


_NOISE = (
    "composer.lock",
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    ".min.js",
    ".min.css",
    ".snap",
)


def _is_noise(path: str) -> bool:
    """Generated / vendored / dependency files that co-change without meaning."""
    if any(token in path for token in _NOISE):
        return True
    segments = path.split("/")
    return any(segment in ("vendor", "node_modules", "dist", "build", ".git") for segment in segments)


def change_rate(conn: sqlite3.Connection, top=None) -> list:
    """Files ranked by commits, with commits-per-active-day as the rate."""
    rows = conn.execute(
        "SELECT path, type, commits, active_days, first_seen, last_seen FROM files ORDER BY commits DESC, path"
    ).fetchall()
    results = []
    for row in rows:
        days = row["active_days"] or 0
        results.append(
            {
                "path": row["path"],
                "type": row["type"],
                "commits": row["commits"],
                "active_days": days,
                "rate": round((row["commits"] or 0) / days, 2) if days else 0.0,
                "first_seen": row["first_seen"],
                "last_seen": row["last_seen"],
            }
        )
    return results[:top] if top is not None else results


def coupling(conn: sqlite3.Connection, top=None, min_shared: int = 2, max_commit_files: int = 30) -> list:
    """Temporal coupling: files that repeatedly change in the same commits.

    Bulk commits (more than ``max_commit_files``) and generated/vendored paths are
    dropped as noise. Coupling is the share of the less-changed file's commits
    that the pair shares.
    """
    transactions = {}
    for row in conn.execute("SELECT commit_hash, path FROM changes").fetchall():
        if _is_noise(row["path"]):
            continue
        transactions.setdefault(row["commit_hash"], []).append(row["path"])

    revisions = {row["path"]: row["commits"] or 0 for row in conn.execute("SELECT path, commits FROM files").fetchall()}

    shared = {}
    for paths in transactions.values():
        paths = sorted(set(paths))
        if len(paths) < 2 or len(paths) > max_commit_files:
            continue
        for left in range(len(paths)):
            for right in range(left + 1, len(paths)):
                key = (paths[left], paths[right])
                shared[key] = shared.get(key, 0) + 1

    results = []
    for (path_a, path_b), count in shared.items():
        if count < min_shared:
            continue
        rev_a, rev_b = revisions.get(path_a, 0), revisions.get(path_b, 0)
        denominator = min(rev_a, rev_b) or count
        results.append(
            {
                "path_a": path_a,
                "path_b": path_b,
                "shared_commits": count,
                "commits_a": rev_a,
                "commits_b": rev_b,
                "coupling_pct": round(100.0 * count / denominator, 1),
            }
        )

    results.sort(key=lambda item: (item["coupling_pct"], item["shared_commits"]), reverse=True)
    return results[:top] if top is not None else results


def ownership(conn: sqlite3.Connection, top=None) -> list:
    """Per-file authorship: how many authors, and the top author's share."""
    per_path = {}
    for row in conn.execute(
        "SELECT ch.path AS path, co.author_email AS author, COUNT(DISTINCT co.hash) AS commits"
        " FROM changes ch JOIN commits co ON co.hash = ch.commit_hash"
        " GROUP BY ch.path, co.author_email"
    ).fetchall():
        per_path.setdefault(row["path"], {})[row["author"]] = row["commits"]

    meta = {row["path"]: row for row in conn.execute("SELECT path, commits, last_seen FROM files").fetchall()}

    results = []
    for path, authors in per_path.items():
        total = sum(authors.values()) or 1
        top_author = max(authors, key=lambda author: authors[author])
        info = meta.get(path)
        results.append(
            {
                "path": path,
                "authors": len(authors),
                "top_author": top_author,
                "top_share": round(100.0 * authors[top_author] / total, 1),
                "commits": info["commits"] if info else total,
                "last_seen": info["last_seen"] if info else None,
            }
        )

    results.sort(key=lambda item: item["path"])
    return results[:top] if top is not None else results


def concentration(conn: sqlite3.Connection, top=None, threshold: float = 80.0) -> list:
    """Knowledge-risk files: single-owner, or one author holding >= ``threshold``%.

    Ranked by change activity — a concentrated file nobody touches is lower risk
    than one changed every week.
    """
    flagged = [row for row in ownership(conn, None) if row["authors"] == 1 or row["top_share"] >= threshold]
    flagged.sort(key=lambda item: (item["commits"], item["top_share"]), reverse=True)
    return flagged[:top] if top is not None else flagged


def bus_factor(conn: sqlite3.Connection, threshold: float = 0.5) -> dict:
    """How few authors cover ``threshold`` of all commits (knowledge loss risk)."""
    rows = conn.execute(
        "SELECT author_email AS author, COUNT(DISTINCT hash) AS commits FROM commits GROUP BY author_email ORDER BY commits DESC"
    ).fetchall()
    total = sum(row["commits"] for row in rows)
    if not total:
        return {"authors": 0, "bus_factor": 0, "total_commits": 0}
    cumulative = 0
    factor = 0
    for row in rows:
        cumulative += row["commits"]
        factor += 1
        if cumulative / total >= threshold:
            break
    return {"authors": len(rows), "bus_factor": factor, "total_commits": total}


def commit_types(conn: sqlite3.Connection, top=None) -> list:
    """Overall Conventional Commits type mix."""
    rows = conn.execute(
        "SELECT COALESCE(NULLIF(type, ''), '(non-conventional)') AS type, COUNT(*) AS commits"
        " FROM commits GROUP BY type ORDER BY commits DESC"
    ).fetchall()
    total = sum(row["commits"] for row in rows) or 1
    results = [
        {"type": row["type"], "commits": row["commits"], "pct": round(100.0 * row["commits"] / total, 1)} for row in rows
    ]
    return results[:top] if top is not None else results


def authors(conn: sqlite3.Connection, top=None) -> list:
    """Per-author commit mix and Conventional Commits compliance."""
    rows = conn.execute(
        "SELECT author_email AS author, COUNT(*) AS commits,"
        " SUM(CASE WHEN type = 'feat' THEN 1 ELSE 0 END) AS feat,"
        " SUM(CASE WHEN type = 'fix' THEN 1 ELSE 0 END) AS fix,"
        " SUM(CASE WHEN type = 'hotfix' THEN 1 ELSE 0 END) AS hotfix,"
        " SUM(CASE WHEN breaking = 1 THEN 1 ELSE 0 END) AS breaking,"
        " SUM(CASE WHEN type = '' THEN 0 ELSE 1 END) AS conventional"
        " FROM commits GROUP BY author_email ORDER BY commits DESC"
    ).fetchall()
    results = []
    for row in rows:
        commits = row["commits"] or 1
        results.append(
            {
                "author": row["author"],
                "commits": row["commits"],
                "feat": row["feat"],
                "fix": row["fix"],
                "hotfix": row["hotfix"],
                "breaking": row["breaking"],
                "compliance_pct": round(100.0 * row["conventional"] / commits, 1),
            }
        )
    return results[:top] if top is not None else results


def tickets(conn: sqlite3.Connection, top=None) -> list:
    """Ticket references found in commit scopes: activity and fix counts."""
    rows = conn.execute(
        "SELECT ticket, COUNT(*) AS commits, SUM(CASE WHEN type IN ('fix', 'hotfix', 'bugfix') THEN 1 ELSE 0 END) AS fixes,"
        " MIN(date) AS first_seen, MAX(date) AS last_seen"
        " FROM commits WHERE ticket <> '' GROUP BY ticket ORDER BY commits DESC"
    ).fetchall()
    results = [dict(row) for row in rows]
    return results[:top] if top is not None else results


_VIEWS = {
    "hotspots": hotspots,
    "change-rate": change_rate,
    "coupling": coupling,
    "ownership": ownership,
    "concentration": concentration,
    "commit-types": commit_types,
    "authors": authors,
    "tickets": tickets,
}
