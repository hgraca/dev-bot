#!/usr/bin/env python3
"""store — SQLite persistence for the forensics module.

The evidence layer is written once and queried by every analysis. Tables are
added per phase; only what the current phase writes exists (no speculative
schema).
"""

from __future__ import annotations

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
  message       TEXT,
  files_changed INTEGER DEFAULT 0,
  lines_added   INTEGER DEFAULT 0,
  lines_deleted INTEGER DEFAULT 0
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
"""

_TABLES = ("meta", "commits", "changes", "files")


def connect(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def init(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA)
    conn.commit()


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
        "(hash, author_name, author_email, date, message, files_changed, lines_added, lines_deleted)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [
            (
                c["hash"],
                c["author_name"],
                c["author_email"],
                c["date"],
                c["message"],
                c["files_changed"],
                c["lines_added"],
                c["lines_deleted"],
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


def derive_files(conn: sqlite3.Connection) -> None:
    """Roll per-commit file changes up into one row per path."""
    conn.execute("DELETE FROM files")
    rows = conn.execute(
        "SELECT ch.path AS path, co.date AS date, co.author_email AS author, ch.commit_hash AS hash"
        " FROM changes ch JOIN commits co ON co.hash = ch.commit_hash"
    ).fetchall()

    acc = {}
    for row in rows:
        entry = acc.setdefault(
            row["path"], {"commits": set(), "days": set(), "authors": set(), "first": None, "last": None}
        )
        entry["commits"].add(row["hash"])
        entry["days"].add((row["date"] or "")[:10])
        entry["authors"].add(row["author"])
        date = row["date"]
        if date:
            if entry["first"] is None or date < entry["first"]:
                entry["first"] = date
            if entry["last"] is None or date > entry["last"]:
                entry["last"] = date

    for path, entry in acc.items():
        extension = os.path.splitext(path)[1].lstrip(".").lower()
        conn.execute(
            "INSERT OR REPLACE INTO files(path, type, commits, active_days, first_seen, last_seen, authors_count)"
            " VALUES (?, ?, ?, ?, ?, ?, ?)",
            (path, extension, len(entry["commits"]), len(entry["days"]), entry["first"], entry["last"], len(entry["authors"])),
        )
    conn.commit()


def counts(conn: sqlite3.Connection) -> dict:
    return {table: conn.execute("SELECT COUNT(*) FROM %s" % table).fetchone()[0] for table in _TABLES}
