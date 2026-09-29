#!/usr/bin/env python3
"""store — SQLite persistence for the forensics module.

The evidence layer is written once and queried by every analysis. Tables are
added per phase; only what the current phase writes exists (no speculative
schema).
"""

from __future__ import annotations

import datetime
import os
import sqlite3

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT
);
CREATE TABLE IF NOT EXISTS commits (
  hash          TEXT PRIMARY KEY,
  author_name   TEXT,
  author_email  TEXT,
  date          TEXT,
  committer_date TEXT,
  message       TEXT,
  files_changed INTEGER DEFAULT 0,
  lines_added   INTEGER DEFAULT 0,
  lines_deleted INTEGER DEFAULT 0,
  type          TEXT,
  scope         TEXT,
  ticket        TEXT,
  breaking      INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS changes (
  commit_hash TEXT,
  path        TEXT,
  added       INTEGER DEFAULT 0,
  deleted     INTEGER DEFAULT 0,
  is_rename   INTEGER DEFAULT 0,
  old_path    TEXT,
  PRIMARY KEY (commit_hash, path)
);
CREATE TABLE IF NOT EXISTS files (
  path          TEXT PRIMARY KEY,
  type          TEXT,
  commits       INTEGER DEFAULT 0,
  active_days   INTEGER DEFAULT 0,
  first_seen    TEXT,
  last_seen     TEXT,
  authors_count INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS units (
  path       TEXT,
  name       TEXT,
  kind       TEXT,
  start_line INTEGER,
  end_line   INTEGER,
  complexity INTEGER,
  loc        INTEGER,
  parent     TEXT,
  ca         INTEGER,
  ce         INTEGER,
  cbo        INTEGER,
  PRIMARY KEY (path, kind, name)
);
CREATE TABLE IF NOT EXISTS defect_links (
  fix_hash        TEXT,
  fix_type        TEXT,
  fix_author      TEXT,
  inducing_hash   TEXT,
  inducing_author TEXT,
  delta_seconds   INTEGER,
  matched_lines   INTEGER,
  PRIMARY KEY (fix_hash, inducing_hash)
);
CREATE TABLE IF NOT EXISTS unit_ownership (
  unit_key    TEXT,
  path        TEXT,
  name        TEXT,
  kind        TEXT,
  author      TEXT,
  lines_owned INTEGER,
  last_change TEXT,
  PRIMARY KEY (unit_key, author)
);
CREATE TABLE IF NOT EXISTS unit_churn (
  unit_key    TEXT PRIMARY KEY,
  path        TEXT,
  name        TEXT,
  kind        TEXT,
  commits     INTEGER,
  active_days INTEGER,
  last_change TEXT
);
CREATE TABLE IF NOT EXISTS releases (
  tag  TEXT PRIMARY KEY,
  date TEXT
);
CREATE TABLE IF NOT EXISTS complexity_trend (
  revision   TEXT,
  date       TEXT,
  path       TEXT,
  complexity INTEGER,
  PRIMARY KEY (revision, path)
);
CREATE TABLE IF NOT EXISTS defects (
  path   TEXT PRIMARY KEY,
  count  INTEGER DEFAULT 0,
  source TEXT
);
CREATE TABLE IF NOT EXISTS boundaries (
  module TEXT,
  prefix TEXT,
  PRIMARY KEY (module, prefix)
);
"""

_TABLES = (
    "meta",
    "commits",
    "changes",
    "files",
    "units",
    "defect_links",
    "unit_ownership",
    "unit_churn",
    "releases",
    "complexity_trend",
    "defects",
    "boundaries",
)


def connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


SCHEMA_VERSION = "3"


def init(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', ?)", (SCHEMA_VERSION,))
    conn.commit()


def check(conn: sqlite3.Connection):
    """A human problem string when the store is not a compatible forensics DB."""
    try:
        row = conn.execute("SELECT value FROM meta WHERE key = 'schema_version'").fetchone()
    except sqlite3.Error as exc:
        return "unreadable store (%s)" % exc
    if row is None:
        return "not a forensics store (no schema_version) — re-run: forensics mine"
    if row["value"] != SCHEMA_VERSION:
        return "store schema_version %s, expected %s — re-run: forensics mine" % (row["value"], SCHEMA_VERSION)
    return None


def reset(conn: sqlite3.Connection) -> None:
    for table in _TABLES:
        conn.execute("DROP TABLE IF EXISTS %s" % table)
    conn.commit()
    init(conn)


def write_meta(conn: sqlite3.Connection, values: dict) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)",
        [(key, str(value)) for key, value in values.items()],
    )


def write_commits(conn: sqlite3.Connection, commits: list) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO commits"
        "(hash, author_name, author_email, date, committer_date, message, files_changed, lines_added, lines_deleted,"
        " type, scope, ticket, breaking)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (
                c["hash"],
                c["author_name"],
                c["author_email"],
                c["date"],
                c.get("committer_date", ""),
                c["message"],
                c["files_changed"],
                c["lines_added"],
                c["lines_deleted"],
                c.get("type", ""),
                c.get("scope", ""),
                c.get("ticket", ""),
                int(c.get("breaking", 0) or 0),
            )
            for c in commits
        ],
    )


def write_changes(conn: sqlite3.Connection, changes: list) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO changes(commit_hash, path, added, deleted, is_rename, old_path)"
        " VALUES (?, ?, ?, ?, ?, ?)",
        [
            (
                ch["commit_hash"],
                ch["path"],
                ch["added"],
                ch["deleted"],
                1 if ch["is_rename"] else 0,
                ch["old_path"] or "",
            )
            for ch in changes
        ],
    )


def _utc_key(value: str):
    """A UTC datetime for an ISO-8601 string, so mixed offsets compare correctly."""
    try:
        parsed = datetime.datetime.fromisoformat(value)
    except ValueError:
        return value
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.timezone.utc)
    return parsed.astimezone(datetime.timezone.utc)


def derive_files(conn: sqlite3.Connection) -> None:
    """Roll per-commit file changes up into one row per path.

    Dates are the commits' committer dates, so first/last seen line up with the
    window `mine` selected on.
    """
    conn.execute("DELETE FROM files")
    rows = conn.execute(
        "SELECT ch.path AS path, co.committer_date AS committer_date, co.author_email AS author, ch.commit_hash AS hash"
        " FROM changes ch JOIN commits co ON co.hash = ch.commit_hash"
    ).fetchall()

    acc = {}
    for row in rows:
        entry = acc.setdefault(
            row["path"],
            {"commits": set(), "days": set(), "authors": set(), "first": None, "last": None, "first_key": None, "last_key": None},
        )
        entry["commits"].add(row["hash"])
        entry["authors"].add(row["author"])
        date = row["committer_date"]
        if not date:
            continue
        key = _utc_key(date)
        entry["days"].add(key.date().isoformat() if isinstance(key, datetime.datetime) else date[:10])
        if entry["first_key"] is None or key < entry["first_key"]:
            entry["first"], entry["first_key"] = date, key
        if entry["last_key"] is None or key > entry["last_key"]:
            entry["last"], entry["last_key"] = date, key

    for path, entry in acc.items():
        extension = os.path.splitext(path)[1].lstrip(".").lower()
        conn.execute(
            "INSERT OR REPLACE INTO files(path, type, commits, active_days, first_seen, last_seen, authors_count)"
            " VALUES (?, ?, ?, ?, ?, ?, ?)",
            (path, extension, len(entry["commits"]), len(entry["days"]), entry["first"], entry["last"], len(entry["authors"])),
        )
    conn.commit()


def write_units(conn: sqlite3.Connection, units: list) -> None:
    rows = []
    for unit in units:
        path, name, kind = unit.get("path"), unit.get("name"), unit.get("kind")
        if not path or not name or not kind:
            continue
        rows.append(
            (
                path,
                name,
                kind,
                unit.get("start_line"),
                unit.get("end_line"),
                unit.get("complexity"),
                unit.get("loc"),
                unit.get("parent") or "",
                unit.get("ca"),
                unit.get("ce"),
                unit.get("cbo"),
            )
        )
    conn.executemany(
        "INSERT OR REPLACE INTO units(path, name, kind, start_line, end_line, complexity, loc, parent, ca, ce, cbo)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        rows,
    )


def write_defect_links(conn: sqlite3.Connection, links: list) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO defect_links"
        "(fix_hash, fix_type, fix_author, inducing_hash, inducing_author, delta_seconds, matched_lines)"
        " VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
            (
                link["fix_hash"],
                link.get("fix_type", ""),
                link.get("fix_author", ""),
                link.get("inducing_hash", ""),
                link.get("inducing_author", ""),
                link.get("delta_seconds"),
                link.get("matched_lines", 0),
            )
            for link in links
        ],
    )


def write_unit_ownership(conn: sqlite3.Connection, rows: list) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO unit_ownership(unit_key, path, name, kind, author, lines_owned, last_change)"
        " VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
            (row["unit_key"], row["path"], row["name"], row["kind"], row["author"], row["lines_owned"], row["last_change"])
            for row in rows
        ],
    )


def write_unit_churn(conn: sqlite3.Connection, rows: list) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO unit_churn(unit_key, path, name, kind, commits, active_days, last_change)"
        " VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
            (row["unit_key"], row["path"], row["name"], row["kind"], row["commits"], row["active_days"], row["last_change"])
            for row in rows
        ],
    )


def write_releases(conn: sqlite3.Connection, releases: list) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO releases(tag, date) VALUES (?, ?)",
        [(release["tag"], release.get("date", "")) for release in releases],
    )


def write_complexity_trend(conn: sqlite3.Connection, rows: list) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO complexity_trend(revision, date, path, complexity) VALUES (?, ?, ?, ?)",
        [(row["revision"], row["date"], row["path"], row["complexity"]) for row in rows],
    )


def write_defects(conn: sqlite3.Connection, rows: list) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO defects(path, count, source) VALUES (?, ?, ?)",
        [(row["path"], row["count"], row.get("source", "")) for row in rows],
    )


def write_boundaries(conn: sqlite3.Connection, rows: list) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO boundaries(module, prefix) VALUES (?, ?)",
        [(row["module"], row["prefix"]) for row in rows],
    )


def counts(conn: sqlite3.Connection) -> dict:
    return {table: conn.execute("SELECT COUNT(*) FROM %s" % table).fetchone()[0] for table in _TABLES}
