#!/usr/bin/env python3
"""report — assemble every view into one document (Markdown or JSON)."""

from __future__ import annotations

import html
import sqlite3

import analyse

# view name -> (heading, top-N in the report)
SECTIONS = (
    ("hotspots", "Hotspots", 20),
    ("priority", "Debt priority", 20),
    ("trends", "Complexity trends", 20),
    ("change-rate", "Change rate", 10),
    ("coupling", "Temporal coupling", 15),
    ("ownership", "Ownership", 15),
    ("concentration", "Ownership concentration", 15),
    ("unit-ownership", "Unit ownership", 15),
    ("unit-concentration", "Unit ownership risk", 15),
    ("commit-types", "Commit types", 20),
    ("authors", "Authors", 20),
    ("tickets", "Tickets", 20),
    ("defects", "Defect origin (SZZ)", 20),
    ("defect-density", "Defect density", 20),
    ("risk", "Risk (hotspot x defects)", 20),
    ("fixers", "Fixer ↔ originator", 20),
    ("process", "Commit process", 1),
    ("releases", "Releases", 20),
    ("modules", "Modules", 20),
    ("architecture", "Cross-module coupling", 20),
    ("structural", "Structural coupling", 20),
)

_METHOD = (
    "Every metric is bound to the mining window above (the last month by default;\n"
    "`mine --all` lifts the bound). Unit ownership and churn are anchored at the\n"
    "window's *end* date, not restricted by its start: authorship is cumulative to\n"
    "that instant, and a line written after it is not attributed. Static complexity\n"
    "has no time dimension — it measures the current tree, so hotspots and priority\n"
    "rank today's code against the window's change rate.\n"
    "The window is applied to mined history on *committer* date (git's walk), and the\n"
    "dates this report prints are those committer dates, so every window-scoped figure\n"
    "agrees with the selection. The `commits` activity command keeps *author* dates\n"
    "instead — a rebased or backdated commit can appear in one and not the other.\n"
    "Release counts and release-cadence figures are window-scoped, not all-time.\n"
    "Attribution is otherwise approximate: blame runs over the *current* unit line\n"
    "spans, and historical spans are not reconstructed. Defect origin is a simplified\n"
    "SZZ (blame of the lines a fix changed at its parent revision) and has known false\n"
    "positives and negatives — treat it as a process signal, never a verdict about a\n"
    "person. Coupling drops bulk commits and generated/vendored paths. True DORA\n"
    "metrics need deploy/incident data and are outside the git-only path."
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


def _escape(value) -> str:
    return html.escape(str(value))


def _html_table(rows: list) -> str:
    if not rows:
        return "<p><em>(none)</em></p>"
    keys = list(rows[0].keys())
    head = "".join("<th>%s</th>" % _escape(key) for key in keys)
    body = "".join(
        "<tr>" + "".join("<td>%s</td>" % _escape(row.get(key, "")) for key in keys) + "</tr>" for row in rows
    )
    return "<table><thead><tr>%s</tr></thead><tbody>%s</tbody></table>" % (head, body)


def _hotspot_svg(rows: list) -> str:
    """A complexity × change scatter — the codebase's activity geography."""
    if not rows:
        return "<p><em>(no hotspots)</em></p>"
    width, height, pad = 720, 320, 40
    max_commits = max((row["commits"] or 0) for row in rows) or 1
    max_complexity = max((row["complexity"] or 0) for row in rows) or 1

    points = []
    for row in rows:
        x = pad + (row["commits"] or 0) / max_commits * (width - 2 * pad)
        y = height - pad - (row["complexity"] or 0) / max_complexity * (height - 2 * pad)
        points.append(
            '<circle cx="%.1f" cy="%.1f" r="4" fill="#d64545"><title>%s</title></circle>'
            % (x, y, _escape(row["path"]))
        )

    axes = (
        '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#999"/>' % (pad, height - pad, width - pad, height - pad)
        + '<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#999"/>' % (pad, pad, pad, height - pad)
        + '<text x="%d" y="%d" font-size="12" fill="#666">commits &#8594;</text>' % (width - 130, height - 8)
        + '<text x="6" y="16" font-size="12" fill="#666">complexity &#8593;</text>'
    )
    return '<svg width="%d" height="%d" viewBox="0 0 %d %d">%s%s</svg>' % (
        width,
        height,
        width,
        height,
        axes,
        "".join(points),
    )


def to_html(doc: dict) -> str:
    meta = doc["meta"]
    parts = [
        "<!DOCTYPE html>",
        '<html lang="en"><head><meta charset="utf-8"><title>Code forensics report</title>',
        "<style>body{font-family:system-ui,sans-serif;margin:2rem;max-width:1100px}"
        "table{border-collapse:collapse;width:100%;margin:1rem 0}"
        "th,td{border:1px solid #ccc;padding:4px 8px;font-size:13px;text-align:left}"
        "th{background:#f3f3f3}h2{margin-top:2rem}svg{background:#fafafa;border:1px solid #ddd}</style>",
        "</head><body>",
        "<h1>Code forensics report</h1>",
        "<ul><li>repo: %s</li><li>range: %s .. %s</li><li>unit ownership anchored at: %s</li>"
        "<li>head: %s</li><li>tool: forensics %s</li></ul>"
        % (
            _escape(meta.get("repo", "")),
            _escape(meta.get("since", "") or "start"),
            _escape(meta.get("until", "") or "HEAD"),
            _escape(meta.get("until", "") or "HEAD"),
            _escape(meta.get("head", "")),
            _escape(meta.get("version", "")),
        ),
        "<h2>Hotspot geography</h2>",
        _hotspot_svg(doc.get("hotspots", [])),
    ]
    for view, title, _top in SECTIONS:
        parts.append("<h2>%s</h2>" % _escape(title))
        parts.append(_html_table(doc.get(view, [])))
    parts.append("<h2>Time to fix</h2>")
    parts.append(_html_table(doc.get("time-to-fix", [])))
    parts.append("<h2>Methodology</h2><p>%s</p>" % _escape(_METHOD).replace("\n", " "))
    parts.append("</body></html>")
    return "\n".join(parts) + "\n"


def to_markdown(doc: dict) -> str:
    meta = doc["meta"]
    lines = [
        "# Code forensics report",
        "",
        "- repo: %s" % meta.get("repo", ""),
        "- range: %s .. %s" % (meta.get("since", "") or "start", meta.get("until", "") or "HEAD"),
        "- unit ownership anchored at: %s" % (meta.get("until", "") or "HEAD"),
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
