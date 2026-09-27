#!/usr/bin/env python3
"""report — assemble every view into one document (Markdown or JSON)."""

from __future__ import annotations

import sqlite3

import analyse

# view name -> (heading, top-N in the report)
SECTIONS = (
    ("hotspots", "Hotspots", 20),
    ("change-rate", "Change rate", 10),
    ("coupling", "Temporal coupling", 15),
    ("concentration", "Ownership concentration", 15),
    ("unit-concentration", "Unit ownership risk", 15),
    ("commit-types", "Commit types", 20),
    ("authors", "Authors", 20),
    ("tickets", "Tickets", 20),
    ("defects", "Defect origin (SZZ)", 20),
    ("fixers", "Fixer ↔ originator", 20),
    ("process", "Commit process", 1),
)

_METHOD = (
    "Attribution is approximate: unit churn and ownership derive from `git blame`\n"
    "over the *current* unit line spans, and historical spans are not reconstructed.\n"
    "Defect origin is a simplified SZZ (blame of the lines a fix changed at its\n"
    "parent revision) and has known false positives and negatives — treat it as a\n"
    "process signal, never a verdict about a person. Coupling drops bulk commits and\n"
    "generated/vendored paths. True DORA metrics need deploy/incident data and are\n"
    "outside the git-only path."
)


def build(conn: sqlite3.Connection) -> dict:
    """Every view, plus run metadata, bus factor and the time-to-fix distribution."""
    meta = {row["key"]: row["value"] for row in conn.execute("SELECT key, value FROM meta").fetchall()}
    doc = {
        "meta": meta,
        "bus_factor": analyse.bus_factor(conn),
        "time-to-fix": analyse.time_to_fix(conn),
    }
    for view, _title, top in SECTIONS:
        doc[view] = analyse._VIEWS[view](conn, top)
    return doc


def _table(rows: list) -> list:
    if not rows:
        return ["_(none)_", ""]
    keys = list(rows[0].keys())
    lines = ["| " + " | ".join(keys) + " |", "| " + " | ".join("---" for _ in keys) + " |"]
    for row in rows:
        lines.append("| " + " | ".join(str(row.get(key, "")) for key in keys) + " |")
    lines.append("")
    return lines


def to_markdown(doc: dict) -> str:
    meta = doc["meta"]
    lines = [
        "# Code forensics report",
        "",
        "- repo: %s" % meta.get("repo", ""),
        "- range: %s .. %s" % (meta.get("since", "") or "start", meta.get("until", "") or "HEAD"),
        "- head: %s" % meta.get("head", ""),
        "- tool: forensics %s" % meta.get("version", ""),
        "- bus factor: %s of %s author(s) hold >=50%% of commits" % (doc["bus_factor"].get("bus_factor"), doc["bus_factor"].get("authors")),
        "",
    ]

    for view, title, _top in SECTIONS:
        lines.append("## %s" % title)
        lines.append("")
        lines.extend(_table(doc[view]))

    lines.append("## Time to fix")
    lines.append("")
    lines.extend(_table(doc["time-to-fix"]))

    lines.append("## Methodology")
    lines.append("")
    lines.append(_METHOD)
    lines.append("")
    return "\n".join(lines)
