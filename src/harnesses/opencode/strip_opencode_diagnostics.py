#!/usr/bin/env python3
"""Strip workspace-wide LSP diagnostics from opencode's stored session payloads.

opencode attached a ``state.metadata.diagnostics`` map to every ``write`` and
``edit`` tool part. The map covers every file in the workspace: in a 28-repo
checkout that is ~114k paths / ~18 MB per call, and it is stored twice - once in
``part`` and once in the ``event`` replay journal. It is dead weight: in a
measured session only 6 of 114,564 entries carried an actual diagnostic.
Opening a session replays all of it, which is what makes switching to an old tab
take tens of seconds.

This removes exactly that field, from both tables, and nothing else - messages,
tool inputs and tool outputs are preserved. Dry run by default; ``--apply``
rewrites the rows and then VACUUMs to reclaim the file. Idempotent: rows already
stripped no longer match.

Runs offline. Fail-open: a missing, busy or schema-less database, or a running
opencode, is reported and the script exits 0 without changing anything.
"""

import argparse
import os
import sqlite3
import stat
import subprocess
import sys
import time

from opencode_db import resolve_db_path

# table -> JSON path of the diagnostics map inside that table's ``data`` column.
TARGETS = (
    ("part", "$.state.metadata.diagnostics"),
    ("event", "$.part.state.metadata.diagnostics"),
)

BATCH_ROWS = 250
BATCH_BYTES = 32 * 1024 * 1024


def _opencode_running():
    # The DB is per-user, so another user's opencode cannot lock ours.
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


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if abs(n) < 1024 or unit == "GB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024.0


def _table_exists(con, name):
    return (
        con.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
        ).fetchone()
        is not None
    )


def _candidates(con, table):
    """Rows whose payload mentions diagnostics at all - one cheap column scan.

    ``instr`` avoids parsing every JSON document; the candidate set is small, so
    the exact ``json_type`` check is then done per row by primary key.
    """
    sql = (
        f"SELECT rowid, length(CAST(data AS BLOB)) FROM {table} "
        f"WHERE instr(data, '\"diagnostics\"') > 0"
    )
    return con.execute(sql).fetchall()


def _confirmed(con, table, path, candidates):
    """Keep only the candidates that really hold the diagnostics object.

    Returns ``(rowid, payload_bytes, diagnostics_bytes)``. Measuring the subtree
    length is exact and cheaper than reserialising the whole payload.
    """
    rows = []
    for rowid, size in candidates:
        hit = con.execute(
            f"SELECT json_type(data, ?), "
            f"length(CAST(json_extract(data, ?) AS BLOB)) "
            f"FROM {table} WHERE rowid = ?",
            (path, path, rowid),
        ).fetchone()
        if hit and hit[0] is not None:
            rows.append((rowid, size, hit[1] or 0))
    return rows


def _batches(rows):
    """Group rows into bounded transactions.

    One payload can be ~18 MB, so a row count alone bounds nothing: the byte
    budget is the real limit and the row cap is the secondary one. A row larger
    than the budget still gets a batch of its own.
    """
    batch, payload = [], 0
    for rowid, row_bytes, _ in rows:
        if batch and (len(batch) >= BATCH_ROWS or payload + row_bytes > BATCH_BYTES):
            yield batch
            batch, payload = [], 0
        batch.append(rowid)
        payload += row_bytes
    if batch:
        yield batch


def _strip(con, table, path, rows):
    """Apply the removal in bounded batches.

    Each batch commits on its own so the WAL stays small on a multi-gigabyte
    database. A failure therefore leaves earlier batches applied; the operation
    is idempotent, so a re-run finishes the remainder.
    """
    for batch in _batches(rows):
        marks = ",".join("?" * len(batch))
        con.execute("BEGIN IMMEDIATE")
        try:
            con.execute(
                f"UPDATE {table} SET data = json_remove(data, ?) WHERE rowid IN ({marks})",
                (path, *batch),
            )
            con.execute("COMMIT")
        except sqlite3.Error:
            con.execute("ROLLBACK")
            raise
    return len(rows)


def plan_strip(con, log=None):
    """Find every row that still carries the map. Returns ``(plan, reclaim)``."""
    plan = []
    reclaim = 0
    for table, json_path in TARGETS:
        if not _table_exists(con, table):
            if log:
                log(f"{table}: no such table - skipped")
            continue
        rows = _confirmed(con, table, json_path, _candidates(con, table))
        if not rows:
            if log:
                log(f"{table}: nothing to strip")
            continue
        saved = sum(diag for _, _, diag in rows)
        reclaim += saved
        plan.append((table, json_path, rows))
        if log:
            payload = sum(size for _, size, _ in rows)
            log(
                f"{table}: {len(rows)} row(s), {human(payload)} payload, "
                f"{human(saved)} reclaimable"
            )
    return plan, reclaim


def apply_plan(con, plan, log=None):
    """Strip the planned rows. Returns the number of rows rewritten."""
    stripped = 0
    for table, json_path, rows in plan:
        stripped += _strip(con, table, json_path, rows)
        if log:
            log(f"{table}: stripped {len(rows)} row(s)")
    return stripped


def _vacuum(con):
    try:
        con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        con.execute("VACUUM")
        con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    except sqlite3.Error as exc:
        print(
            f"WARN vacuum failed ({exc}) - rows stripped, space not reclaimed",
            file=sys.stderr,
        )


def _verify(con):
    try:
        result = con.execute("PRAGMA quick_check").fetchone()[0]
    except sqlite3.Error as exc:
        print(f"WARN integrity check could not run: {exc}", file=sys.stderr)
        return
    print(f"integrity: {result}")


def _remove_quietly(path):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.unlink(path + suffix)
        except OSError:
            pass


def _reserve_backup(path):
    """Create a fresh backup path, never reusing one, with the database's mode.

    The database itself is 0600, so the copy must be too: the process umask
    would otherwise leave prompts and tool output world-readable. ``O_EXCL``
    also keeps a second run in the same second from overwriting the first.
    Any other filesystem error propagates for the caller to report.
    """
    base = f"{path}.pre-strip-{time.strftime('%Y%m%dT%H%M%S')}"
    mode = stat.S_IMODE(os.stat(path).st_mode)
    for attempt in range(100):
        candidate = base if attempt == 0 else f"{base}-{attempt}"
        try:
            os.close(os.open(candidate, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
        except FileExistsError:
            continue
        try:
            os.chmod(candidate, mode)
        except OSError:
            _remove_quietly(candidate)
            raise
        return candidate
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Strip workspace-wide LSP diagnostics from opencode session payloads."
    )
    parser.add_argument(
        "--apply", action="store_true", help="Rewrite rows, then VACUUM unless --no-vacuum"
    )
    parser.add_argument("--db", default=None, help="Database path (default $OPENCODE_DB_PATH)")
    parser.add_argument("--force", action="store_true", help="Skip the running-opencode guard")
    parser.add_argument("--no-backup", action="store_true", help="Skip the pre-apply database copy")
    parser.add_argument(
        "--no-vacuum", action="store_true", help="Leave reclaiming to a later VACUUM"
    )
    args = parser.parse_args(argv)

    path = resolve_db_path(args.db)
    if not os.path.isfile(path):
        print(f"WARN opencode db not found: {path}", file=sys.stderr)
        return 0

    if args.apply and not args.force and _opencode_running():
        print("WARN opencode is running - refusing to rewrite the db", file=sys.stderr)
        return 0

    try:
        con = sqlite3.connect(path, timeout=30)
        con.isolation_level = None  # autocommit; _strip manages its own transaction
        con.execute("PRAGMA busy_timeout=30000")
    except sqlite3.Error as exc:
        print(f"ERROR cannot open {path}: {exc}", file=sys.stderr)
        return 1

    mode = "APPLY" if args.apply else "DRY RUN"
    print(f"opencode db: {path}")
    print(f"mode: {mode}")

    try:
        size_before = os.path.getsize(path)
        plan, reclaim = plan_strip(con, log=print)
    except sqlite3.Error as exc:
        print(f"ERROR cannot read {path}: {exc}", file=sys.stderr)
        con.close()
        return 0

    if not plan:
        print("nothing to strip")
        con.close()
        return 0

    print(f"projected: {human(size_before)} -> ~{human(max(size_before - reclaim, 0))}")
    if not args.apply:
        print("dry run - re-run with --apply to rewrite and reclaim")
        con.close()
        return 0

    if not args.no_backup:
        try:
            backup = _reserve_backup(path)
        except OSError as exc:
            print(f"ERROR cannot create backup ({exc}) - not applied", file=sys.stderr)
            con.close()
            return 0
        if backup is None:
            print("ERROR cannot reserve a backup name - not applied", file=sys.stderr)
            con.close()
            return 0
        print(f"backup: {backup} ({human(size_before)}) ...")
        try:
            dst = sqlite3.connect(backup)
            with dst:
                con.backup(dst)
            dst.close()
        except sqlite3.Error as exc:
            _remove_quietly(backup)
            print(f"ERROR backup failed - not applied: {exc}", file=sys.stderr)
            con.close()
            return 0

    try:
        apply_plan(con, plan, log=print)
        if args.no_vacuum:
            print("vacuum deferred to the caller")
        else:
            _vacuum(con)
            _verify(con)
    except sqlite3.Error as exc:
        print(
            f"ERROR rewrite aborted (database busy or locked?): {exc} - "
            "some batches may already be applied; re-run --apply to finish",
            file=sys.stderr,
        )
        con.close()
        return 0

    size_after = os.path.getsize(path)
    reclaimed = human(size_before - size_after)
    print(f"size: {human(size_before)} -> {human(size_after)} (reclaimed {reclaimed})")
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
