#!/usr/bin/env python3
"""Append one tool-grading row to <DEV_BOT_ROOT>/.agents/logs/tools-grades.csv.

The CSV is install-level, not per-project: every project's sessions land in the
same file, each row tagged with the project it came from, so tool quality
accumulates across the whole workspace instead of fragmenting per consumer.

The script owns the CSV so the calling agent only supplies judgement:

  * canonical column order — session_id, datetime, project, notes, actor, then
    every tool column, MCP columns (`mcp:`) before skill columns (`skill:`)
  * a session-scoped row id `<session-id>-NN`, NN starting at 01
  * column union — a tool used for the first time becomes a new column and
    every earlier row is backfilled with 0 ("not used")
  * RFC-4180 quoting for the free-text notes, embedded line breaks included,
    written atomically
  * the notes keep their line breaks, and every grade of 1-3 must name its
    tool there

Usage:
    record-grades.py --notes $'tool-a: why it scored 3\\n\\ntool-b: why it scored 2' \\
        [--mcp <server>=<grade>]... \\
        [--mcp-tool <tool>=<grade>]... \\
        [--skill <name>=<grade>]... \\
        [--devbot-root DIR] [--project-root DIR] \\
        [--actor NAME] [--session-id ID] [--now "YYYY-MM-DD HH:MM:SS"]

`--mcp-tool` targets the self-owned `devbot-tools` server, one column per tool.
`--project-root` defaults to the current directory — run from the project root.
"""

from __future__ import annotations

import argparse
import csv
import fcntl
import os
import sys
import tempfile
from collections.abc import Mapping
from datetime import datetime
from pathlib import Path
from typing import NoReturn

BASE_COLUMNS = ["session_id", "datetime", "project", "notes", "actor"]
DEV_TOOLS = "devbot-tools"
SESSION_ID_ENV = "DEV_BOT_SESSION_ID"
AGENT_NAME_ENV = "DEV_BOT_AGENT_NAME"
ROOT_ENV_VAR = "DEV_BOT_ROOT"
UNKNOWN_SESSION = "unknown"
UNKNOWN_ACTOR = "unknown"
# Rows written before the actor column existed all came from the primary agent,
# so a blank actor is backfilled with that rather than left to read as unknown.
DEFAULT_ACTOR = "DevBot"
CSV_PARTS = (".agents", "logs", "tools-grades.csv")
# A directory holding this marker is a devbot install root. Used only for the
# walk-up fallback, when DEV_BOT_ROOT was not exported into the agent's shell.
ROOT_MARKER = ("src", "agentic")
MCP_PREFIX = "mcp:"
SKILL_PREFIX = "skill:"
GRADE_MIN, GRADE_MAX = 0, 5
# 1-3 mean "used, but something was wrong with it" — that something is what
# drives the keep/remove/substitute decision, so it must be written down.
GRADES_NEEDING_EXPLANATION = (1, 2, 3)
DATETIME_FORMAT = "%Y-%m-%d %H:%M:%S"
TMP_PREFIX = ".tools-grades-"
LOCK_SUFFIX = ".lock"


def _fail(prefix: str, message: str, code: int) -> NoReturn:
    print(f"{prefix}: {message}", file=sys.stderr)
    raise SystemExit(code)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="record-grades.py",
        description="Append one tool-grading row to the shared tools-grades.csv.",
    )
    parser.add_argument("--notes", default="", help="free-text notes for this row (line breaks kept)")
    parser.add_argument("--mcp", action="append", default=[], metavar="NAME=GRADE",
                        help="grade an MCP server (repeatable)")
    parser.add_argument("--mcp-tool", action="append", default=[], metavar="TOOL=GRADE",
                        help=f"grade one {DEV_TOOLS} tool (repeatable)")
    parser.add_argument("--skill", action="append", default=[], metavar="NAME=GRADE",
                        help="grade a skill (repeatable)")
    parser.add_argument("--devbot-root", default=None,
                        help=f"devbot install root (default: ${ROOT_ENV_VAR}, else discover it)")
    parser.add_argument("--project-root", default=None,
                        help="project the session belongs to (default: the current directory)")
    parser.add_argument("--session-id", default=None, help="override the harness session id")
    parser.add_argument(
        "--actor", default=None, help=f"agent owning this row (default: ${AGENT_NAME_ENV})"
    )
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


def explanation_key(column: str) -> str:
    """The name the notes must mention for a graded tool.

    The last colon-separated segment, so `mcp:devbot-tools:format-md` only
    requires `format-md` and `skill:devbot:makefile` only `makefile`.
    """
    return column.rpartition(":")[2]


def assert_grades_explained(tools: dict[str, int], notes: str) -> None:
    lowered = notes.lower()
    unexplained = sorted(
        column
        for column, grade in tools.items()
        if grade in GRADES_NEEDING_EXPLANATION and explanation_key(column).lower() not in lowered
    )
    if unexplained:
        grades = "/".join(str(grade) for grade in GRADES_NEEDING_EXPLANATION)
        detail = ", ".join(
            f"{column} (mention {explanation_key(column)!r})" for column in unexplained
        )
        _fail(
            "ERROR",
            f"a grade of {grades} must be explained in --notes, naming the tool: {detail}",
            2,
        )


def normalise_notes(raw: str) -> str:
    """Keep the author's line breaks; drop only incidental whitespace.

    Line breaks are the point — a row whose notes run to a single long line is
    unreadable once the CSV is opened. So CRLF/CR become LF and each line's
    trailing whitespace is stripped, but the breaks themselves survive, along
    with a blank line between tool blocks.
    """
    lines = [line.rstrip() for line in raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines)


def project_name(project_root: str) -> str:
    """`<parent folder>/<folder>` for the project a session belongs to.

    From /home/me/Get-e/positioning-activities that is
    `Get-e/positioning-activities`: enough to tell sibling checkouts apart
    without carrying an absolute path into the CSV. A root with a single
    component yields just that component.
    """
    parts = [part for part in Path(project_root).parts if part not in (os.sep, "")]
    return "/".join(parts[-2:])


def resolve_devbot_root(
    explicit: str | None, environ: Mapping[str, str], script_path: Path
) -> str:
    """Locate the devbot install root that owns the shared CSV.

    Precedence: an explicit override, then $DEV_BOT_ROOT, then a walk up from
    this script's *real* location. Resolving the location matters because a
    project reaches the skill through a symlink
    (`.agents/skills/devbot/<area>` -> `<root>/src/agentic/<area>/skills`), so
    the unresolved path would point back into the project.
    """
    if explicit:
        return explicit
    env = (environ.get(ROOT_ENV_VAR) or "").strip()
    if env:
        return env
    for candidate in Path(script_path).resolve().parents:
        if candidate.joinpath(*ROOT_MARKER).is_dir():
            return str(candidate)
    marker = "/".join(ROOT_MARKER)
    _fail(
        "FATAL",
        f"cannot locate the devbot install root: ${ROOT_ENV_VAR} is unset and no ancestor of "
        f"{script_path} contains {marker}/",
        3,
    )


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


def resolve_actor(explicit: str | None) -> str:
    """The agent that owns this row.

    A blank value never reaches the CSV, unlike the session id: a blank actor
    reads as "written before the column existed" and would be backfilled later,
    mislabelling the row.
    """
    candidate = (explicit or "").strip()
    if candidate:
        return candidate
    env = os.environ.get(AGENT_NAME_ENV, "").strip()
    if env:
        return env
    print(
        f"WARN: {AGENT_NAME_ENV} is not set — recording this row under {UNKNOWN_ACTOR!r}",
        file=sys.stderr,
    )
    return UNKNOWN_ACTOR


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
    notes = normalise_notes(args.notes)
    assert_grades_explained(tools, notes)

    root = resolve_devbot_root(args.devbot_root, os.environ, Path(__file__))
    csv_path = os.path.join(root, *CSV_PARTS)
    os.makedirs(os.path.dirname(csv_path) or ".", exist_ok=True)

    session = resolve_session_id(args.session_id)
    actor = resolve_actor(args.actor)
    project = project_name(args.project_root or os.getcwd())
    now = args.now or datetime.now().strftime(DATETIME_FORMAT)

    # Exclusive lock around the whole read-modify-write: write_csv is atomic
    # per write, but two concurrent appends would otherwise read the same base
    # and the later os.replace would silently drop the earlier row. With the
    # CSV shared across projects this serialises unrelated sessions too, which
    # is exactly why the lock is keyed off the CSV path rather than a project.
    with open(csv_path + LOCK_SUFFIX, "w", encoding="utf-8") as lock_fh:
        fcntl.flock(lock_fh, fcntl.LOCK_EX)
        try:
            header, rows = read_existing(csv_path)
            tool_columns = [column for column in header if column not in BASE_COLUMNS]
            for column, grade in tools.items():
                if grade >= 1 and column not in tool_columns:
                    tool_columns.append(column)

            # A matrix with no `actor` column predates it, so every row it holds
            # came from the primary agent and is stamped accordingly. This is a
            # one-time migration keyed on the header, not a rule about empty
            # cells: once the column exists, a blank actor means "not known" and
            # is left alone.
            if "actor" not in header:
                for row in rows:
                    row["actor"] = DEFAULT_ACTOR

            new_row: dict[str, object] = {
                "session_id": next_row_id(rows, session),
                "datetime": now,
                "project": project,
                "notes": notes,
                "actor": actor,
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
