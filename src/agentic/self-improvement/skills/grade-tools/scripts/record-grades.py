#!/usr/bin/env python3
"""Append one tool-grading row to <project>/.agents/logs/tools-grades.csv.

The script owns the CSV so the calling agent only supplies judgement:

  * canonical column order — session_id, datetime, notes, then every tool
    column, MCP columns (`mcp:`) before skill columns (`skill:`)
  * a session-scoped row id `<session-id>-NN`, NN starting at 01
  * column union — a tool used for the first time becomes a new column and
    every earlier row is backfilled with 0 ("not used")
  * RFC-4180 quoting for the free-text notes, written atomically

Usage:
    record-grades.py --notes "..." \\
        [--mcp <server>=<grade>]... \\
        [--mcp-tool <tool>=<grade>]... \\
        [--skill <name>=<grade>]... \\
        [--project-root DIR] [--session-id ID] [--now "YYYY-MM-DD HH:MM:SS"]

`--mcp-tool` targets the self-owned `devbot-tools` server, one column per tool.
"""

from __future__ import annotations

import argparse
import csv
import fcntl
import os
import sys
import tempfile
from datetime import datetime
from typing import NoReturn

BASE_COLUMNS = ["session_id", "datetime", "notes"]
DEV_TOOLS = "devbot-tools"
SESSION_ID_ENV = "DEVBOT_SESSION_ID"
UNKNOWN_SESSION = "unknown"
DEFAULT_CSV_PARTS = (".agents", "logs", "tools-grades.csv")
MCP_PREFIX = "mcp:"
SKILL_PREFIX = "skill:"
GRADE_MIN, GRADE_MAX = 0, 5
DATETIME_FORMAT = "%Y-%m-%d %H:%M:%S"
TMP_PREFIX = ".tools-grades-"
LOCK_SUFFIX = ".lock"


def _fail(prefix: str, message: str, code: int) -> NoReturn:
    print(f"{prefix}: {message}", file=sys.stderr)
    raise SystemExit(code)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="record-grades.py",
        description="Append one tool-grading row to tools-grades.csv.",
    )
    parser.add_argument("--notes", default="", help="free-text notes for this row")
    parser.add_argument("--mcp", action="append", default=[], metavar="NAME=GRADE",
                        help="grade an MCP server (repeatable)")
    parser.add_argument("--mcp-tool", action="append", default=[], metavar="TOOL=GRADE",
                        help=f"grade one {DEV_TOOLS} tool (repeatable)")
    parser.add_argument("--skill", action="append", default=[], metavar="NAME=GRADE",
                        help="grade a skill (repeatable)")
    parser.add_argument("--project-root", default=os.getcwd(),
                        help="project root holding .agents/ (default: cwd)")
    parser.add_argument("--session-id", default=None, help="override the harness session id")
    parser.add_argument("--now", default=None, help="row timestamp (default: now, local)")
    parser.add_argument("--verbose", action="store_true", help="print the appended row id (debug aid)")
    return parser.parse_args(argv)


def _parse_grade(flag: str, pair: str) -> tuple[str, int]:
    name, sep, raw = pair.rpartition("=")
    if not sep or not name.strip() or not raw.strip():
        _fail("ERROR", f"{flag} expects NAME=GRADE, got {pair!r}", 2)
    try:
        grade = int(raw.strip())
    except ValueError:
        _fail("ERROR", f"{flag} grade must be an integer 0-5, got {raw.strip()!r}", 2)
    if not (GRADE_MIN <= grade <= GRADE_MAX):
        _fail("ERROR", f"{flag} grade {grade} is out of range 0-5", 2)
    return name.strip(), grade


def _put(tools: dict[str, int], column: str, grade: int, flag: str) -> None:
    if column in tools:
        _fail("ERROR", f"{flag} {column!r} was given more than once", 2)
    tools[column] = grade


def collect_tools(args: argparse.Namespace) -> dict[str, int]:
    tools: dict[str, int] = {}
    for pair in args.mcp:
        name, grade = _parse_grade("--mcp", pair)
        if name == DEV_TOOLS:
            _fail("ERROR", f"--mcp {DEV_TOOLS} is graded per tool; use --mcp-tool", 2)
        _put(tools, MCP_PREFIX + name, grade, "--mcp")
    for pair in args.mcp_tool:
        name, grade = _parse_grade("--mcp-tool", pair)
        _put(tools, f"{MCP_PREFIX}{DEV_TOOLS}:{name}", grade, "--mcp-tool")
    for pair in args.skill:
        name, grade = _parse_grade("--skill", pair)
        _put(tools, SKILL_PREFIX + name, grade, "--skill")
    return tools


def resolve_session_id(explicit: str | None) -> str:
    if explicit:
        return explicit
    env = os.environ.get(SESSION_ID_ENV, "").strip()
    if env:
        return env
    print(
        f"WARN: {SESSION_ID_ENV} is not set — grouping this row under {UNKNOWN_SESSION!r}",
        file=sys.stderr,
    )
    return UNKNOWN_SESSION


def read_existing(path: str) -> tuple[list[str], list[dict[str, object]]]:
    if not os.path.isfile(path):
        return [], []
    with open(path, newline="", encoding="utf-8") as fh:
        raw = [row for row in csv.reader(fh) if row]
    if not raw:
        return [], []
    header = raw[0]
    rows: list[dict[str, object]] = []
    for values in raw[1:]:
        rows.append({header[i]: (values[i] if i < len(values) else "") for i in range(len(header))})
    return header, rows


def next_row_id(rows: list[dict[str, object]], session: str) -> str:
    prefix = session + "-"
    highest = 0
    for row in rows:
        value = str(row.get("session_id") or "").strip()
        if value.startswith(prefix):
            suffix = value[len(prefix):]
            if suffix.isdigit():
                highest = max(highest, int(suffix))
    return f"{session}-{highest + 1:02d}"


def tool_sort_key(column: str) -> tuple[int, str]:
    return (0 if column.startswith(MCP_PREFIX) else 1, column)


def canonical_columns(tool_columns: list[str]) -> list[str]:
    return BASE_COLUMNS + sorted(tool_columns, key=tool_sort_key)


def target_mode(path: str) -> int:
    # mkstemp creates the temp file 0600; restore an existing file's mode, or
    # the umask default for a new one, so the CSV is never left owner-only.
    if os.path.exists(path):
        return os.stat(path).st_mode & 0o7777
    umask = os.umask(0)
    os.umask(umask)
    return 0o644 & ~umask


def write_csv(path: str, columns: list[str], rows: list[dict[str, object]]) -> None:
    dirpath = os.path.dirname(path) or "."
    os.makedirs(dirpath, exist_ok=True)
    tool_columns = set(columns) - set(BASE_COLUMNS)
    fd, tmp = tempfile.mkstemp(dir=dirpath, prefix=TMP_PREFIX, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh, lineterminator="\n")
            writer.writerow(columns)
            for row in rows:
                values: list[object] = []
                for column in columns:
                    if column in tool_columns:
                        values.append(row.get(column, 0))
                    else:
                        values.append(row.get(column, ""))
                writer.writerow(values)
        os.chmod(tmp, target_mode(path))
        os.replace(tmp, path)
    except OSError as exc:
        if os.path.exists(tmp):
            os.unlink(tmp)
        _fail("FATAL", f"cannot write {path}: {exc}", 3)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    tools = collect_tools(args)

    if not os.path.isdir(os.path.join(args.project_root, ".agents")):
        _fail("ERROR", f"{args.project_root} is not a dev-bot project (no .agents/)", 2)
    csv_path = os.path.join(args.project_root, *DEFAULT_CSV_PARTS)
    os.makedirs(os.path.dirname(csv_path) or ".", exist_ok=True)

    session = resolve_session_id(args.session_id)
    now = args.now or datetime.now().strftime(DATETIME_FORMAT)

    # Exclusive lock around the whole read-modify-write: write_csv is atomic
    # per write, but two concurrent appends would otherwise read the same base
    # and the later os.replace would silently drop the earlier row.
    with open(csv_path + LOCK_SUFFIX, "w", encoding="utf-8") as lock_fh:
        fcntl.flock(lock_fh, fcntl.LOCK_EX)
        try:
            header, rows = read_existing(csv_path)
            tool_columns = [column for column in header if column not in BASE_COLUMNS]
            for column, grade in tools.items():
                if grade >= 1 and column not in tool_columns:
                    tool_columns.append(column)

            new_row: dict[str, object] = {
                "session_id": next_row_id(rows, session),
                "datetime": now,
                "notes": " ".join(args.notes.split()),
            }
            for column in tool_columns:
                new_row[column] = tools.get(column, 0)
            rows.append(new_row)

            write_csv(csv_path, canonical_columns(tool_columns), rows)
        finally:
            fcntl.flock(lock_fh, fcntl.LOCK_UN)

    if args.verbose:
        print(f"{csv_path}: appended {new_row['session_id']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
