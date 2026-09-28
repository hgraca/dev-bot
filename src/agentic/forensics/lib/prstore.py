#!/usr/bin/env python3
"""prstore — the stable pull-request cache for the forensics module.

Remote PR data accumulates here, separate from the timestamped analysis store:
that store is reset on every ``mine``, so a cumulative cache cannot live in it.
Tables are provider-agnostic — one row per ``(source, repo, number)`` — and the
``pr_coverage`` table records which windows have already been fetched, so a
request only reaches the provider for the spans it is missing.
"""

from __future__ import annotations

import datetime
import sqlite3

SCHEMA_VERSION = "1"

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT
);
CREATE TABLE IF NOT EXISTS prs (
  source        TEXT,
  repo          TEXT,
  number        INTEGER,
  author        TEXT,
  created_at    TEXT,
  merged_at     TEXT,
  commits       INTEGER DEFAULT 0,
  added         INTEGER DEFAULT 0,
  deleted       INTEGER DEFAULT 0,
  changed_files INTEGER DEFAULT 0,
  url           TEXT,
  PRIMARY KEY (source, repo, number)
);
CREATE TABLE IF NOT EXISTS pr_coverage (
  source     TEXT,
  repo       TEXT,
  since      TEXT,
  until      TEXT,
  fetched_at TEXT,
  PRIMARY KEY (source, repo, since, until)
);
"""


def connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def init(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', ?)", (SCHEMA_VERSION,))
    conn.commit()


def check(conn: sqlite3.Connection):
    """A human problem string when the store is not a compatible PR cache."""
    try:
        row = conn.execute("SELECT value FROM meta WHERE key = 'schema_version'").fetchone()
    except sqlite3.Error as exc:
        return "unreadable PR cache (%s)" % exc
    if row is None:
        return "not a forensics PR cache (no schema_version)"
    if row["value"] != SCHEMA_VERSION:
        return "PR cache schema_version %s, expected %s" % (row["value"], SCHEMA_VERSION)
    tables = {entry["name"] for entry in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'").fetchall()}
    missing = [name for name in ("prs", "pr_coverage") if name not in tables]
    if missing:
        return "PR cache is missing table(s): %s" % ", ".join(missing)
    return None


def _iso(value) -> str:
    """Normalise an ISO-8601 timestamp (or datetime) to UTC ``+00:00`` form, or ''."""
    if not value:
        return ""
    if isinstance(value, datetime.datetime):
        moment = value
    else:
        raw = str(value).strip().replace("Z", "+00:00")
        try:
            moment = datetime.datetime.fromisoformat(raw)
        except ValueError:
            return raw
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=datetime.timezone.utc)
    return moment.astimezone(datetime.timezone.utc).isoformat()


def _parse(value):
    if not value:
        return None
    try:
        moment = datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=datetime.timezone.utc)
    return moment.astimezone(datetime.timezone.utc)


def upsert_prs(conn: sqlite3.Connection, source: str, repo: str, prs: list) -> None:
    rows = []
    for pr in prs:
        number = pr.get("number")
        if number is None:
            continue
        rows.append(
            (
                source,
                repo,
                int(number),
                pr.get("author") or "",
                _iso(pr.get("created_at")),
                _iso(pr.get("merged_at")),
                int(pr.get("commits") or 0),
                int(pr.get("added") or 0),
                int(pr.get("deleted") or 0),
                int(pr.get("changed_files") or 0),
                pr.get("url") or "",
            )
        )
    conn.executemany(
        "INSERT OR REPLACE INTO prs(source, repo, number, author, created_at, merged_at,"
        " commits, added, deleted, changed_files, url) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        rows,
    )
    conn.commit()


def record_coverage(conn: sqlite3.Connection, source: str, repo: str, since, until) -> None:
    conn.execute(
        "INSERT OR REPLACE INTO pr_coverage(source, repo, since, until, fetched_at) VALUES (?, ?, ?, ?, ?)",
        (
            source,
            repo,
            _iso(since),
            _iso(until),
            datetime.datetime.now(datetime.timezone.utc).isoformat(),
        ),
    )
    conn.commit()


def covered(conn: sqlite3.Connection, source: str, repo: str) -> list:
    """The fetched windows for a source/repo as ``(since, until)`` datetimes."""
    rows = conn.execute(
        "SELECT since, until FROM pr_coverage WHERE source = ? AND repo = ?", (source, repo)
    ).fetchall()
    intervals = []
    for row in rows:
        start, end = _parse(row["since"]), _parse(row["until"])
        if start and end:
            intervals.append((start, end))
    return intervals


def query_merged(conn: sqlite3.Connection, source: str, repo: str, since, until) -> list:
    """Merged PRs for a source/repo whose ``merged_at`` falls within the window."""
    rows = conn.execute(
        "SELECT number, author, created_at, merged_at, commits, added, deleted, changed_files, url"
        " FROM prs WHERE source = ? AND repo = ? AND merged_at <> '' AND merged_at >= ? AND merged_at <= ?"
        " ORDER BY merged_at",
        (source, repo, _iso(since), _iso(until)),
    ).fetchall()
    return [dict(row) for row in rows]
