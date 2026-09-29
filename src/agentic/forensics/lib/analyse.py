#!/usr/bin/env python3
"""analyse — views over the mined store.

Phase 1 starts with hotspots: code that is both complex and frequently changed,
ranked so the two dimensions are combined on a common scale. Ranks are
percentile-normalised rather than raw products, so one very large class cannot
dominate the list (AD-7).
"""

from __future__ import annotations

import bisect
import datetime
import sqlite3

CONCENTRATION_THRESHOLD = 80.0
LARGE_COMMIT_LINES = 500


def _percentile_ranks(values: list) -> list:
    """Rank values on [0, 1] aligned with the input; equal values share a rank."""
    count = len(values)
    if count == 0:
        return []
    if count == 1:
        return [1.0]
    ordered = sorted(values)
    return [bisect.bisect_left(ordered, value) / (count - 1) for value in values]


def hotspots(conn: sqlite3.Connection, top=None) -> list:
    """Files ranked by percentile(complexity) × percentile(change rate).

    File complexity uses the leaf units (methods/functions); a class' WMC already
    sums its methods, so adding both would double-count.
    """
    raw = conn.execute(
        "SELECT f.path AS path, f.commits AS commits,"
        " COALESCE(SUM(CASE WHEN u.kind IN ('method', 'function') THEN u.complexity ELSE 0 END), 0) AS leaf,"
        " COALESCE(SUM(u.complexity), 0) AS total,"
        " COUNT(u.name) AS unit_count"
        " FROM files f JOIN units u ON u.path = f.path"
        " GROUP BY f.path"
        " ORDER BY f.path"
    ).fetchall()

    rows = []
    for row in raw:
        complexity = row["leaf"] or row["total"] or 0
        if complexity > 0 or (row["commits"] or 0) > 0:
            rows.append(
                {"path": row["path"], "commits": row["commits"], "complexity": complexity, "unit_count": row["unit_count"]}
            )

    complexity_ranks = _percentile_ranks([row["complexity"] for row in rows])
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


def concentration(conn: sqlite3.Connection, top=None, threshold: float = CONCENTRATION_THRESHOLD) -> list:
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
        " SUM(CASE WHEN COALESCE(type, '') = '' THEN 0 ELSE 1 END) AS conventional"
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


def _utc(value: str):
    """Parse an ISO-8601 timestamp to UTC, or None — for offset-safe ordering."""
    try:
        parsed = datetime.datetime.fromisoformat(value)
    except (ValueError, TypeError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.timezone.utc)
    return parsed.astimezone(datetime.timezone.utc)


def tickets(conn: sqlite3.Connection, top=None) -> list:
    """Ticket references found in commit subjects: activity, fixes and first/last seen."""
    aggregated = {}
    for row in conn.execute(
        "SELECT ticket, committer_date, COALESCE(type, '') AS type FROM commits WHERE ticket <> ''"
    ).fetchall():
        entry = aggregated.setdefault(row["ticket"], {"commits": 0, "fixes": 0, "dates": []})
        entry["commits"] += 1
        if row["type"] in ("fix", "hotfix", "bugfix"):
            entry["fixes"] += 1
        if row["committer_date"]:
            entry["dates"].append(row["committer_date"])

    floor = datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)
    results = []
    for ticket, entry in aggregated.items():
        dates = sorted(entry["dates"], key=lambda value: _utc(value) or floor)
        results.append(
            {
                "ticket": ticket,
                "commits": entry["commits"],
                "fixes": entry["fixes"],
                "first_seen": dates[0] if dates else None,
                "last_seen": dates[-1] if dates else None,
            }
        )
    results.sort(key=lambda item: item["commits"], reverse=True)
    return results[:top] if top is not None else results


def defects(conn: sqlite3.Connection, top=None) -> list:
    """Fix commits with their inducing commit and the time between them."""
    rows = conn.execute(
        "SELECT fix_hash, fix_type, fix_author, inducing_hash, inducing_author, delta_seconds, matched_lines"
        " FROM defect_links ORDER BY delta_seconds DESC"
    ).fetchall()
    results = []
    for row in rows:
        entry = dict(row)
        entry["delta_hours"] = round((row["delta_seconds"] or 0) / 3600.0, 2)
        results.append(entry)
    return results[:top] if top is not None else results


def _percentile(values: list, fraction: float):
    if not values:
        return None
    values = sorted(values)
    position = (len(values) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(values) - 1)
    if lower == upper:
        return values[lower]
    return values[lower] + (values[upper] - values[lower]) * (position - lower)


def time_to_fix(conn: sqlite3.Connection, top=None) -> list:
    """Distribution of inducing→fix time in hours."""
    deltas = [
        row["delta_seconds"]
        for row in conn.execute("SELECT delta_seconds FROM defect_links WHERE delta_seconds IS NOT NULL").fetchall()
    ]
    if not deltas:
        return [{"count": 0}]
    hours = [delta / 3600.0 for delta in deltas]
    return [
        {
            "count": len(hours),
            "avg_hours": round(sum(hours) / len(hours), 2),
            "median_hours": round(_percentile(hours, 0.5) or 0, 2),
            "p75_hours": round(_percentile(hours, 0.75) or 0, 2),
            "p90_hours": round(_percentile(hours, 0.9) or 0, 2),
            "fastest_hours": round(min(hours), 2),
            "slowest_hours": round(max(hours), 2),
        }
    ]


def fixers(conn: sqlite3.Connection, top=None) -> list:
    """Who fixes whose code: fix author vs the author of the inducing commit."""
    rows = conn.execute(
        "SELECT fix_author, inducing_author, COUNT(*) AS fixes FROM defect_links"
        " GROUP BY fix_author, inducing_author ORDER BY fixes DESC"
    ).fetchall()
    results = [dict(row) for row in rows]
    return results[:top] if top is not None else results


def process(conn: sqlite3.Connection, top=None) -> list:
    """Commit-process metrics: batch size, churn and Conventional Commits hygiene."""
    rows = conn.execute(
        "SELECT committer_date, files_changed, lines_added, lines_deleted, type FROM commits"
    ).fetchall()
    if not rows:
        return [{"commits": 0}]

    sizes = [row["files_changed"] or 0 for row in rows]
    churn = [(row["lines_added"] or 0) + (row["lines_deleted"] or 0) for row in rows]
    days = {(row["committer_date"] or "")[:10] for row in rows if row["committer_date"]}
    conventional = sum(1 for row in rows if row["type"])

    release_dates = [
        row["date"] for row in conn.execute("SELECT date FROM releases WHERE date <> '' ORDER BY date").fetchall()
    ]
    gaps = []
    for index in range(1, len(release_dates)):
        try:
            gap = datetime.datetime.fromisoformat(release_dates[index]) - datetime.datetime.fromisoformat(
                release_dates[index - 1]
            )
            gaps.append(gap.days)
        except ValueError:
            continue

    return [
        {
            "commits": len(rows),
            "active_days": len(days),
            "commits_per_day": round(len(rows) / len(days), 2) if days else 0.0,
            "avg_files_per_commit": round(sum(sizes) / len(sizes), 2),
            "max_files_in_commit": max(sizes),
            "avg_lines_per_commit": round(sum(churn) / len(churn), 1),
            "large_commits": sum(1 for value in churn if value > LARGE_COMMIT_LINES),
            "conventional_pct": round(100.0 * conventional / len(rows), 1),
            "tags": len(release_dates),
            "avg_days_between_releases": round(sum(gaps) / len(gaps), 1) if gaps else 0,
        }
    ]


def releases(conn: sqlite3.Connection, top=None) -> list:
    """Tags in creation order — the release history."""
    rows = conn.execute("SELECT tag, date FROM releases ORDER BY date").fetchall()
    results = [dict(row) for row in rows]
    return results[:top] if top is not None else results


def unit_ownership(conn: sqlite3.Connection, top=None) -> list:
    """Per-unit authorship from blame: authors and the top author's share."""
    units = {}
    for row in conn.execute("SELECT unit_key, path, name, kind, author, lines_owned FROM unit_ownership").fetchall():
        entry = units.setdefault(
            row["unit_key"],
            {"unit_key": row["unit_key"], "path": row["path"], "name": row["name"], "kind": row["kind"], "owners": {}},
        )
        entry["owners"][row["author"]] = row["lines_owned"]

    results = []
    for entry in units.values():
        total = sum(entry["owners"].values()) or 1
        top_author = max(entry["owners"], key=lambda author: entry["owners"][author])
        results.append(
            {
                "unit_key": entry["unit_key"],
                "path": entry["path"],
                "name": entry["name"],
                "kind": entry["kind"],
                "authors": len(entry["owners"]),
                "top_author": top_author,
                "top_share": round(100.0 * entry["owners"][top_author] / total, 1),
            }
        )

    results.sort(key=lambda item: (-item["top_share"], item["path"], item["name"]))
    return results[:top] if top is not None else results


def unit_concentration(conn: sqlite3.Connection, top=None, threshold: float = CONCENTRATION_THRESHOLD) -> list:
    """Units whose knowledge is single-owner or >= ``threshold``% one author."""
    flagged = [row for row in unit_ownership(conn, None) if row["authors"] == 1 or row["top_share"] >= threshold]
    return flagged[:top] if top is not None else flagged


DEFAULT_WEIGHTS = {"change": 1.0, "complexity": 1.0, "coupling": 0.5, "defect": 1.0, "ownership": 0.5}


def priority(conn: sqlite3.Connection, top=None, weights=None) -> list:
    """Composite debt interest-rate: weighted, percentile-ranked signals per file.

    A transparent weighted sum (not a raw product) so every row can be explained
    by its components — change, complexity, coupling, defect rate and ownership
    risk — each normalised to [0, 1].
    """
    effective = dict(DEFAULT_WEIGHTS)
    if weights:
        effective.update({key: value for key, value in weights.items() if key in effective})

    files = {}
    for row in conn.execute(
        "SELECT f.path AS path, f.commits AS commits,"
        " COALESCE(SUM(CASE WHEN u.kind IN ('method', 'function') THEN u.complexity ELSE 0 END), 0) AS leaf,"
        " COALESCE(SUM(u.complexity), 0) AS total"
        " FROM files f JOIN units u ON u.path = f.path GROUP BY f.path"
    ).fetchall():
        files[row["path"]] = {
            "path": row["path"],
            "commits": row["commits"] or 0,
            "complexity": row["leaf"] or row["total"] or 0,
            "fixes": 0,
            "authors": 1,
        }

    for row in conn.execute(
        "SELECT ch.path AS path,"
        " SUM(CASE WHEN co.type IN ('fix', 'hotfix', 'bugfix') THEN 1 ELSE 0 END) AS fixes,"
        " COUNT(DISTINCT co.author_email) AS authors"
        " FROM changes ch JOIN commits co ON co.hash = ch.commit_hash GROUP BY ch.path"
    ).fetchall():
        entry = files.get(row["path"])
        if entry is not None:
            entry["fixes"] = row["fixes"] or 0
            entry["authors"] = row["authors"] or 1

    coupling_degree = {}
    for pair in coupling(conn, None):
        coupling_degree[pair["path_a"]] = coupling_degree.get(pair["path_a"], 0.0) + pair["coupling_pct"]
        coupling_degree[pair["path_b"]] = coupling_degree.get(pair["path_b"], 0.0) + pair["coupling_pct"]

    paths = sorted(files)
    commits = [files[path]["commits"] for path in paths]
    complexity = [files[path]["complexity"] for path in paths]
    coupling_values = [coupling_degree.get(path, 0.0) for path in paths]
    defect_values = [files[path]["fixes"] / files[path]["commits"] if files[path]["commits"] else 0.0 for path in paths]
    max_authors = max((files[path]["authors"] for path in paths), default=1)
    ownership_risk = [
        1.0 - (files[path]["authors"] - 1) / (max_authors - 1) if max_authors > 1 else 1.0 for path in paths
    ]

    change_ranks = _percentile_ranks(commits)
    complexity_ranks = _percentile_ranks(complexity)
    coupling_ranks = _percentile_ranks(coupling_values)
    defect_ranks = _percentile_ranks(defect_values)
    total_weight = sum(effective.values()) or 1.0

    results = []
    for index, path in enumerate(paths):
        score = (
            effective["change"] * change_ranks[index]
            + effective["complexity"] * complexity_ranks[index]
            + effective["coupling"] * coupling_ranks[index]
            + effective["defect"] * defect_ranks[index]
            + effective["ownership"] * ownership_risk[index]
        ) / total_weight
        results.append(
            {
                "path": path,
                "priority": round(score, 4),
                "change_rank": round(change_ranks[index], 3),
                "complexity_rank": round(complexity_ranks[index], 3),
                "coupling_rank": round(coupling_ranks[index], 3),
                "defect_rank": round(defect_ranks[index], 3),
                "ownership_risk": round(ownership_risk[index], 3),
            }
        )

    results.sort(key=lambda item: item["priority"], reverse=True)
    return results[:top] if top is not None else results


def trends(conn: sqlite3.Connection, top=None) -> list:
    """Per-file complexity change across the sampled revisions (A9)."""
    series = {}
    for row in conn.execute("SELECT path, revision, date, complexity FROM complexity_trend ORDER BY date").fetchall():
        series.setdefault(row["path"], []).append(row)

    results = []
    for path, points in series.items():
        first, last = points[0], points[-1]
        results.append(
            {
                "path": path,
                "snapshots": len(points),
                "first_complexity": first["complexity"],
                "last_complexity": last["complexity"],
                "delta": (last["complexity"] or 0) - (first["complexity"] or 0),
            }
        )
    results.sort(key=lambda item: item["delta"], reverse=True)
    return results[:top] if top is not None else results


def defect_density(conn: sqlite3.Connection, top=None) -> list:
    """External defect counts per file, joined to change activity."""
    rows = conn.execute(
        "SELECT d.path AS path, d.count AS defects, d.source AS source, f.commits AS commits, f.type AS type"
        " FROM defects d LEFT JOIN files f ON f.path = d.path ORDER BY d.count DESC, d.path"
    ).fetchall()
    results = [dict(row) for row in rows]
    return results[:top] if top is not None else results


def risk(conn: sqlite3.Connection, top=None) -> list:
    """Risk = composite priority × external defects (H10) — hot *and* buggy."""
    defects = {row["path"]: row["count"] for row in conn.execute("SELECT path, count FROM defects").fetchall()}
    if not defects:
        return []

    results = []
    for row in priority(conn, None):
        count = defects.get(row["path"])
        if count:
            entry = dict(row)
            entry["defects"] = count
            entry["risk"] = round(row["priority"] * (1 + count), 4)
            results.append(entry)
    results.sort(key=lambda item: item["risk"], reverse=True)
    return results[:top] if top is not None else results


def _load_boundaries(conn: sqlite3.Connection) -> list:
    return [(row["module"], row["prefix"]) for row in conn.execute("SELECT module, prefix FROM boundaries").fetchall()]


def _module_for(path: str, boundaries: list) -> str:
    """The module a path belongs to — longest matching prefix, else its top dir."""
    if boundaries:
        best = None
        for module, prefix in boundaries:
            if path == prefix or path.startswith(prefix.rstrip("/") + "/"):
                if best is None or len(prefix) > len(best[1]):
                    best = (module, prefix)
        return best[0] if best else "(unassigned)"
    return path.split("/", 1)[0] if "/" in path else "(root)"


def architecture(conn: sqlite3.Connection, top=None) -> list:
    """Cross-module temporal coupling — dependencies the architecture hides (A12)."""
    boundaries = _load_boundaries(conn)
    pairs = {}
    for pair in coupling(conn, None):
        module_a = _module_for(pair["path_a"], boundaries)
        module_b = _module_for(pair["path_b"], boundaries)
        if module_a == module_b:
            continue
        key = tuple(sorted((module_a, module_b)))
        entry = pairs.setdefault(key, {"module_a": key[0], "module_b": key[1], "couplings": 0, "shared_commits": 0})
        entry["couplings"] += 1
        entry["shared_commits"] += pair["shared_commits"]

    results = sorted(pairs.values(), key=lambda item: (item["shared_commits"], item["couplings"]), reverse=True)
    return results[:top] if top is not None else results


def modules(conn: sqlite3.Connection, top=None) -> list:
    """Per-module size, activity and ownership diffusion (A12)."""
    boundaries = _load_boundaries(conn)
    aggregated = {}
    for row in conn.execute(
        "SELECT ch.path AS path, co.author_email AS author, COUNT(DISTINCT co.hash) AS commits"
        " FROM changes ch JOIN commits co ON co.hash = ch.commit_hash GROUP BY ch.path, co.author_email"
    ).fetchall():
        module = _module_for(row["path"], boundaries)
        entry = aggregated.setdefault(module, {"module": module, "files": set(), "commits": 0, "authors": set()})
        entry["files"].add(row["path"])
        entry["commits"] += row["commits"]
        entry["authors"].add(row["author"])

    results = [
        {"module": e["module"], "files": len(e["files"]), "commits": e["commits"], "authors": len(e["authors"])}
        for e in aggregated.values()
    ]
    results.sort(key=lambda item: item["commits"], reverse=True)
    return results[:top] if top is not None else results


def structural(conn: sqlite3.Connection, top=None) -> list:
    """Class-level structural coupling (ca/ce/cbo) from the plugin (A15).

    A cross-check for temporal coupling: a pair that changes together with no
    structural edge between them is the interesting one.
    """
    rows = conn.execute(
        "SELECT path, name, COALESCE(ca, 0) AS ca, COALESCE(ce, 0) AS ce, COALESCE(cbo, 0) AS cbo"
        " FROM units WHERE kind = 'class' AND (ca IS NOT NULL OR ce IS NOT NULL OR cbo IS NOT NULL)"
        " ORDER BY (COALESCE(ca, 0) + COALESCE(ce, 0)) DESC, path, name"
    ).fetchall()
    results = [dict(row) for row in rows]
    return results[:top] if top is not None else results


_VIEWS = {
    "hotspots": hotspots,
    "priority": priority,
    "trends": trends,
    "change-rate": change_rate,
    "coupling": coupling,
    "ownership": ownership,
    "concentration": concentration,
    "unit-ownership": unit_ownership,
    "unit-concentration": unit_concentration,
    "commit-types": commit_types,
    "authors": authors,
    "tickets": tickets,
    "defects": defects,
    "defect-density": defect_density,
    "risk": risk,
    "time-to-fix": time_to_fix,
    "fixers": fixers,
    "process": process,
    "releases": releases,
    "architecture": architecture,
    "modules": modules,
    "structural": structural,
}
