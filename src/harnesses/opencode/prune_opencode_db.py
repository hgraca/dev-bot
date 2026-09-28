#!/usr/bin/env python3
"""Prune opencode's SQLite database: drop rows older than N days, reclaim space.

Only derived state is touched. The ``event`` replay journal (~13 GB in a real
database) is keyed to ``event_sequence.aggregate_id``, not to ``session``, so it
is deleted explicitly — deleting a session does not cascade to it. Sessions do
cascade to ``message``/``part``/``todo``/``session_share``/``session_message``/
``session_input``/``session_context_epoch``. ``project`` rows are never
age-pruned: ``session.project_id`` cascades *from* ``project``, so deleting an
aged project would remove every session still in it, recent ones included.
``event_sequence`` rows whose session is already gone (opencode's own
``session delete`` leaves them — there is no FK to ``session``) have no timestamp
to age on, so they are removed outright.

Runs offline, detached from the last devbot session exit. Fail-open: a missing,
corrupt/schema-less, or busy/locked database, or a running opencode, is reported
and the script exits 0 without changing anything.
"""

import argparse
import os
import sqlite3
import subprocess
import sys
import time

from opencode_db import resolve_db_path

DEFAULT_DAYS = 30


def _default_days():
    try:
        return int(os.environ.get("DEVBOT_OPENCODE_DB_RETENTION_DAYS", DEFAULT_DAYS))
    except ValueError:
        return DEFAULT_DAYS


def _opencode_running():
    # The DB is per-user, so another user's opencode cannot lock ours — scope the
    # process probe to this uid.
    argv = ["pgrep", "-x"]
    if hasattr(os, "getuid"):
        argv += ["-u", str(os.getuid())]
    argv.append("opencode")
    try:
        rc = subprocess.run(
            argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ).returncode
    except (OSError, ValueError):
        return False
    return rc == 0


def _is_schema_error(exc):
    return "no such table" in str(exc) or "not a database" in str(exc)


def _vacuum(con):
    try:
        con.execute("VACUUM")
        con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    except sqlite3.Error as exc:
        print(f"WARN vacuum failed ({exc}) — rows deleted, space not reclaimed", file=sys.stderr)


def _prune(con, cutoff):
    """Delete aged + orphaned rows in one transaction.

    Returns ``(sessions, orphans)`` — the session rows removed and the orphan
    journal sequences removed.
    """
    con.execute("BEGIN IMMEDIATE")
    try:
        con.execute(
            "DELETE FROM event_sequence WHERE aggregate_id IN "
            "(SELECT id FROM session WHERE time_updated < ?)",
            (cutoff,),
        )
        deleted = con.execute(
            "DELETE FROM session WHERE time_updated < ?", (cutoff,)
        ).rowcount
        # After the session delete, any sequence whose aggregate is no longer a
        # session is unreachable — remove it (its events cascade).
        orphans = con.execute(
            "DELETE FROM event_sequence WHERE aggregate_id NOT IN (SELECT id FROM session)"
        ).rowcount
        con.execute("COMMIT")
    except sqlite3.Error:
        try:
            con.execute("ROLLBACK")
        except sqlite3.Error:
            pass
        raise
    return deleted, orphans


def main(argv=None):
    parser = argparse.ArgumentParser(description="Prune opencode DB rows older than N days.")
    parser.add_argument("--days", type=int, default=_default_days())
    parser.add_argument("--db", default=None, help="Database path (default $OPENCODE_DB_PATH)")
    parser.add_argument("--force", action="store_true", help="Skip the running-opencode guard")
    args = parser.parse_args(argv)

    if args.days < 0:
        print(f"FATAL invalid retention: {args.days} day(s)", file=sys.stderr)
        return 2

    path = resolve_db_path(args.db)
    if not os.path.isfile(path):
        print(f"WARN opencode db not found: {path}", file=sys.stderr)
        return 0

    if not args.force and _opencode_running():
        print("WARN opencode is running — skipping db prune", file=sys.stderr)
        return 0

    cutoff = int((time.time() - args.days * 86400) * 1000)

    try:
        con = sqlite3.connect(path, timeout=30)
    except sqlite3.Error as exc:
        print(f"ERROR cannot open {path}: {exc}", file=sys.stderr)
        return 1

    try:
        try:
            con.isolation_level = None  # autocommit; _prune manages its own transaction
            con.execute("PRAGMA busy_timeout=30000")
            con.execute("PRAGMA foreign_keys=ON")
            old = con.execute(
                "SELECT COUNT(*) FROM session WHERE time_updated < ?", (cutoff,)
            ).fetchone()[0]
            orphans = con.execute(
                "SELECT COUNT(*) FROM event_sequence "
                "WHERE aggregate_id NOT IN (SELECT id FROM session)"
            ).fetchone()[0]
        except sqlite3.Error as exc:
            print(f"ERROR cannot read opencode db {path}: {exc}", file=sys.stderr)
            return 0

        print(f"opencode db: {path}")
        print(
            f"retention: {args.days} day(s) — sessions older than cutoff: {old}; "
            f"orphan journals: {orphans}"
        )
        if old == 0 and orphans == 0:
            print("nothing to prune")
            return 0

        before = os.path.getsize(path)
        try:
            deleted, removed_orphans = _prune(con, cutoff)
        except sqlite3.Error as exc:
            if _is_schema_error(exc):
                print(f"ERROR opencode db schema mismatch — not pruned: {exc}", file=sys.stderr)
            else:
                print(f"ERROR prune aborted (database busy or locked?): {exc}", file=sys.stderr)
            return 0
        print(
            f"deleted {deleted} session(s) and {removed_orphans} orphan journal(s); "
            "cascaded to message/part/todo/…"
        )

        _vacuum(con)
        after = os.path.getsize(path)
        print(f"size: {before} → {after} bytes (reclaimed {before - after})")
    finally:
        con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
