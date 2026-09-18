#!/usr/bin/env python3
"""Attach aggregated tool grades to the canonical ``devbot stats`` JSON.

Reads the shared grade matrix (``<DEV_BOT_ROOT>/.agents/logs/tools-grades.csv``,
written by the ``devbot:grade-tools`` skill) and appends an optional
``tool_grades`` block to the stats document on stdin, so ``devbot stats`` can
report the quality signal next to raw usage.

The block is produced by ``bin/stats.sh`` (the parent) — harness adapters never
emit it. A missing or malformed CSV degrades to a pass-through, never an error.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from pathlib import Path

# Must stay in sync with BASE_COLUMNS in grade-tools' record-grades.py, which
# owns the CSV's column order.
BASE_COLUMNS = ("session_id", "datetime", "project", "notes")
MCP_PREFIX = "mcp:"
SKILL_PREFIX = "skill:"
DEV_TOOLS = "devbot-tools"
POOR_GRADES = (1, 2, 3)
SCOPE_CURRENT = "current"
SCOPE_ALL = "all"


def _warn_default(message: str) -> None:
    print(message, file=sys.stderr)


def project_name(project_root: str) -> str:
    """``<parent folder>/<folder>`` — same rule as ``record-grades.py``."""
    parts = [part for part in Path(project_root).parts if part not in (os.sep, "")]
    return "/".join(parts[-2:])


def _session_of(row_id: str) -> str:
    """The session id behind a ``<session-id>-NN`` row id."""
    base, sep, suffix = row_id.rpartition("-")
    return base if sep and suffix.isdigit() else row_id


def tool_columns(header: list[str]) -> list[str]:
    """The graded tool columns — every ``mcp:``/``skill:`` column."""
    return [
        column
        for column in header
        if column not in BASE_COLUMNS
        and (column.startswith(MCP_PREFIX) or column.startswith(SKILL_PREFIX))
    ]


def tool_kind(column: str) -> str:
    if column.startswith(SKILL_PREFIX):
        return "skill"
    if column.startswith(MCP_PREFIX + DEV_TOOLS + ":"):
        return "devbot-tool"
    return "mcp"


def display_name(column: str) -> str:
    """Column with the ``mcp:`` / ``skill:`` group prefix stripped."""
    for prefix in (SKILL_PREFIX, MCP_PREFIX):
        if column.startswith(prefix):
            return column[len(prefix):]
    return column


def short_name(column: str) -> str:
    return column.rpartition(":")[2]


def _label_match(stripped: str, column: str) -> tuple[tuple, re.Match] | None:
    """The most specific mention of ``column``'s name in a line, if any.

    A whole-word mention of the display name (``devbot:makefile``) beats the
    short name (``makefile``) at the same position; otherwise the earliest
    mention wins.
    """
    best: tuple[tuple, re.Match] | None = None
    for label, is_display in ((display_name(column), True), (short_name(column), False)):
        if not label:
            continue
        match = re.search(r"(?<!\w)" + re.escape(label) + r"(?!\w)", stripped, re.IGNORECASE)
        if not match:
            continue
        score = (match.start(), 0 if is_display else 1, -len(label))
        if best is None or score < best[0]:
            best = (score, match)
    return best


def attribute_reasons(notes: str, columns: list[str]) -> dict[str, list[str]]:
    """Map each notes line to at most one column.

    The writer only requires a tool's name to appear *somewhere* in the notes,
    so the reader matches whole-word mentions rather than only line-initial
    labels. To stop one line being attributed to several columns (``mcp:datasources``
    and ``skill:devbot:datasources`` share the short name ``datasources``), the
    most specific then earliest mention wins and owns the line exclusively.
    """
    attributed: dict[str, list[str]] = {column: [] for column in columns}
    for line in (notes or "").split("\n"):
        stripped = line.strip()
        if not stripped:
            continue
        winner: tuple[tuple, str, re.Match] | None = None
        for column in columns:
            hit = _label_match(stripped, column)
            if hit is None:
                continue
            key = (hit[0], column)
            if winner is None or key < winner[0]:
                winner = (key, column, hit[1])
        if winner is None:
            continue
        match = winner[2]
        if match.start() == 0:
            # A leading label is the tool's own tag — strip it and its separator.
            rest = re.sub(r"^\s*\(\d+\)\s*:?", "", stripped[match.end():])
            rest = re.sub(r"^\s*[:–—-]\s*", "", rest).strip()
        else:
            # The name is embedded in prose; the whole line is the reason.
            rest = stripped
        if rest:
            attributed[winner[1]].append(rest)
    return attributed


def reason_texts(notes: str, column: str) -> list[str]:
    """Reason lines for a single column — a convenience wrapper."""
    return attribute_reasons(notes, [column]).get(column, [])


def _normalise_reason(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower()).rstrip(" .,;:-")


def _dedupe_reasons(texts: list[str]) -> list[dict]:
    """One entry per distinct reason (normalized), with an occurrence count."""
    seen: dict[str, int] = {}
    reasons: list[dict] = []
    for text in texts:
        key = _normalise_reason(text)
        if key in seen:
            reasons[seen[key]]["count"] += 1
        else:
            seen[key] = len(reasons)
            reasons.append({"text": text, "count": 1})
    return reasons


def read_rows(path: str) -> tuple[list[str], list[dict[str, str]]]:
    with open(path, newline="", encoding="utf-8") as fh:
        raw = [values for values in csv.reader(fh) if values]
    if not raw:
        return [], []
    header = [value.strip() for value in raw[0]]
    rows: list[dict[str, str]] = []
    for values in raw[1:]:
        rows.append(
            {
                header[i]: (values[i].strip() if i < len(values) else "")
                for i in range(len(header))
            }
        )
    return header, rows


def aggregate(
    header: list[str], rows: list[dict[str, str]], scope_project: str | None = None
) -> dict:
    """Average per tool over used rows; collect poor-grade reasons per tool."""
    columns = tool_columns(header)
    grades: dict[str, list[int]] = {column: [] for column in columns}
    reasons: dict[str, list[str]] = {column: [] for column in columns}
    in_scope = 0

    for row in rows:
        if scope_project is not None and row.get("project", "") != scope_project:
            continue
        in_scope += 1
        notes = row.get("notes", "")
        poor_columns: list[str] = []
        for column in columns:
            raw = row.get(column, "").strip()
            if not raw:
                continue
            try:
                grade = int(raw)
            except ValueError:
                continue
            if grade < 1:
                continue
            grades[column].append(grade)
            if grade in POOR_GRADES:
                poor_columns.append(column)
        if poor_columns:
            attributed = attribute_reasons(notes, poor_columns)
            for column in poor_columns:
                reasons[column].extend(attributed[column])

    tools: list[dict] = []
    for column in columns:
        tool_grades = grades[column]
        used = len(tool_grades)
        tools.append(
            {
                "column": column,
                "name": display_name(column),
                "kind": tool_kind(column),
                "avg": round(sum(tool_grades) / used, 2) if used else None,
                "uses": used,
                "reasons": _dedupe_reasons(reasons[column]),
            }
        )
    tools.sort(key=lambda tool: (tool["uses"] == 0, -(tool["avg"] or 0), tool["name"]))
    return {
        "rows": in_scope,
        "total_rows": len(rows),
        "sessions": len({_session_of(row.get("session_id", "")) for row in rows}),
        "tools": tools,
    }


def build_tool_grades(
    csv_path: str, scope: str, project_root: str, warn=None
) -> dict | None:
    """The ``tool_grades`` block, or ``None`` when there is nothing to report."""
    warn = warn or _warn_default
    if not os.path.isfile(csv_path):
        return None
    try:
        header, rows = read_rows(csv_path)
    except (OSError, csv.Error, UnicodeDecodeError) as exc:
        warn(f"WARN: cannot read tool grades CSV {csv_path}: {exc}")
        return None
    if not header:
        return None
    missing = [column for column in BASE_COLUMNS if column not in header]
    if missing:
        warn(f"WARN: {csv_path} is not a tool-grades CSV (missing {', '.join(sorted(missing))})")
        return None
    if not rows:
        return None

    scope_project = None if scope == SCOPE_ALL else project_name(project_root)
    block = aggregate(header, rows, scope_project)
    block["scope"] = scope
    if block["rows"] == 0 or not block["tools"]:
        return None
    return block


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="tool_grades.py",
        description="Attach aggregated tool grades to the canonical devbot stats JSON.",
    )
    parser.add_argument("--csv", required=True, help="path to tools-grades.csv")
    parser.add_argument("--scope", choices=(SCOPE_CURRENT, SCOPE_ALL), default=SCOPE_CURRENT)
    parser.add_argument("--project-root", default=os.getcwd())
    args = parser.parse_args(argv)

    try:
        stats = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid stats JSON on stdin: {exc}", file=sys.stderr)
        return 1
    if not isinstance(stats, dict):
        print("ERROR: stats JSON must be an object", file=sys.stderr)
        return 1

    block = build_tool_grades(args.csv, args.scope, args.project_root)
    if block is not None:
        stats["tool_grades"] = block

    json.dump(stats, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
