#!/usr/bin/env python3
"""Attach aggregated tool grades to the canonical ``devbot stats`` JSON.

Reads the shared grade matrix (``<DEV_BOT_ROOT>/.agents/logs/tools-grades.csv``,
written by the ``devbot:grade-tools`` skill) and appends an optional
``tool_grades`` block to the stats document on stdin, so ``devbot stats`` can
report the quality signal next to raw usage. The block honours the report's
window and project scope, so the grades describe the same slice of time as the
usage figures beside them.

The block is produced by ``bin/stats.sh`` (the parent) — harness adapters never
emit it. A missing or malformed CSV degrades to a pass-through, never an error.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import statistics
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Must stay in sync with BASE_COLUMNS in grade-tools' record-grades.py, which
# owns the CSV's column order.
BASE_COLUMNS = ("session_id", "datetime", "project", "notes", "actor")
# What the reader needs present to make sense of a matrix. `actor` arrived later,
# so requiring every base column would reject a matrix written before it and drop
# the whole Tool Grades section on every existing install.
REQUIRED_COLUMNS = ("session_id", "datetime", "project", "notes")
MCP_PREFIX = "mcp:"
SKILL_PREFIX = "skill:"
DEV_TOOLS = "devbot-tools"
POOR_GRADES = (1, 2, 3)
# Quality is absolute — the 0-5 rubric is. Demand is relative: "often used" only
# means anything against the rest of the dataset, so the bar is recomputed per
# report rather than fixed.
#
# 3.5 is the midpoint between the rubric's 3 ("poor" — see POOR_GRADES) and 4
# ("good"). At 3.0 a tool graded predominantly 3 counted as high quality while
# the same report listed it under Poor ratings.
QUALITY_THRESHOLD = 3.5
MIN_MANY_USES = 3
MIN_USES_FOR_STDEV = 3
# Must stay in sync with DATETIME_FORMAT in grade-tools' record-grades.py, which
# owns the format the matrix is written in.
DATETIME_FORMAT = "%Y-%m-%d %H:%M:%S"
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


def row_datetime(row: dict[str, str]) -> datetime | None:
    """The row's stamp, or ``None`` when it is missing or unreadable."""
    try:
        return datetime.strptime((row.get("datetime") or "").strip(), DATETIME_FORMAT)
    except ValueError:
        return None


def window_rows(
    rows: list[dict[str, str]], days: int, now: datetime | None = None
) -> list[dict[str, str]]:
    """The rows stamped within the last ``days`` days.

    The matrix is append-ordered, so an undated row is placed by its neighbours:
    it is kept only when the nearest dated row before it and the nearest dated
    row after it are both inside the window. Rows sharing those bounds — a run of
    undated rows, and every row when the matrix carries no stamps at all — are
    kept or dropped together; one sitting before the first dated row or after the
    last has no placement and is dropped.
    """
    cutoff = (now or datetime.now()) - timedelta(days=days)
    stamps = [row_datetime(row) for row in rows]

    before: list[datetime | None] = [None] * len(rows)
    latest: datetime | None = None
    for index, stamp in enumerate(stamps):
        before[index] = latest
        if stamp is not None:
            latest = stamp

    after: list[datetime | None] = [None] * len(rows)
    latest = None
    for index in range(len(stamps) - 1, -1, -1):
        after[index] = latest
        if stamps[index] is not None:
            latest = stamps[index]

    kept: list[dict[str, str]] = []
    for index, stamp in enumerate(stamps):
        if stamp is None:
            preceding, following = before[index], after[index]
            in_window = (
                preceding is not None
                and preceding >= cutoff
                and following is not None
                and following >= cutoff
            )
        else:
            in_window = stamp >= cutoff
        if in_window:
            kept.append(rows[index])
    return kept


def demand_bar(uses: list[int]) -> int:
    """The "often used" cut: the median use count of the tools actually used.

    Recomputed per report so the bar tracks the dataset instead of a fixed
    number. The floor keeps a thin CSV — where nearly everything sits at one
    use — from declaring a single use "often used".
    """
    used = [count for count in uses if count > 0]
    if not used:
        return MIN_MANY_USES
    return max(MIN_MANY_USES, math.ceil(statistics.median(used)))


def classify_bucket(avg: float | None, uses: int, bar: int) -> str:
    """Place a tool on the quality x demand grid."""
    if uses < 1 or avg is None:
        return "unused"
    if avg > QUALITY_THRESHOLD:
        return "workhorse" if uses >= bar else "specialist"
    return "improve" if uses >= bar else "unproven"


def aggregate(
    header: list[str],
    rows: list[dict[str, str]],
    scope_project: str | None = None,
    days: int | None = None,
    now: datetime | None = None,
) -> dict:
    """Average per tool over used rows; collect poor-grade reasons per tool."""
    columns = tool_columns(header)
    grades: dict[str, list[int]] = {column: [] for column in columns}
    reasons: dict[str, list[str]] = {column: [] for column in columns}
    # Both totals stay all-time, so the report can say how much of the matrix
    # the window actually covers.
    total_rows = len(rows)
    total_sessions = len({_session_of(row.get("session_id", "")) for row in rows})
    if days is not None:
        rows = window_rows(rows, days, now)
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

    bar = demand_bar([len(tool_grades) for tool_grades in grades.values()])
    tools: list[dict] = []
    for column in columns:
        tool_grades = grades[column]
        used = len(tool_grades)
        avg = round(sum(tool_grades) / used, 2) if used else None
        tools.append(
            {
                "column": column,
                "name": display_name(column),
                "kind": tool_kind(column),
                "avg": avg,
                "uses": used,
                "min": min(tool_grades) if used else None,
                "stdev": (
                    round(statistics.pstdev(tool_grades), 2)
                    if used >= MIN_USES_FOR_STDEV
                    else None
                ),
                "bucket": classify_bucket(avg, used, bar),
                "reasons": _dedupe_reasons(reasons[column]),
            }
        )
    tools.sort(key=lambda tool: (tool["uses"] == 0, -(tool["avg"] or 0), tool["name"]))
    return {
        "rows": in_scope,
        "total_rows": total_rows,
        "sessions": total_sessions,
        "days": days,
        "demand_bar": bar,
        "quality_threshold": QUALITY_THRESHOLD,
        "tools": tools,
    }


def build_tool_grades(
    csv_path: str,
    scope: str,
    project_root: str,
    days: int | None = None,
    now: datetime | None = None,
    warn=None,
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
    missing = [column for column in REQUIRED_COLUMNS if column not in header]
    if missing:
        warn(f"WARN: {csv_path} is not a tool-grades CSV (missing {', '.join(sorted(missing))})")
        return None
    if not rows:
        return None

    scope_project = None if scope == SCOPE_ALL else project_name(project_root)
    block = aggregate(header, rows, scope_project, days=days, now=now)
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
    parser.add_argument(
        "--days",
        type=int,
        default=None,
        help="only count rows from the last N days (default: no window)",
    )
    args = parser.parse_args(argv)

    if args.days is not None and args.days < 1:
        print("ERROR: --days must be a positive integer", file=sys.stderr)
        return 2

    try:
        stats = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid stats JSON on stdin: {exc}", file=sys.stderr)
        return 1
    if not isinstance(stats, dict):
        print("ERROR: stats JSON must be an object", file=sys.stderr)
        return 1

    block = build_tool_grades(args.csv, args.scope, args.project_root, days=args.days)
    if block is not None:
        stats["tool_grades"] = block

    json.dump(stats, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
