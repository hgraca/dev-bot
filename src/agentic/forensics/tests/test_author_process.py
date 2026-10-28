#!/usr/bin/env python3
"""Unit tests for lib/analyse.author_process — per-author batch size and commit hygiene."""

from __future__ import annotations

import os
import sqlite3
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import analyse  # noqa: E402
import store  # noqa: E402


def _store():
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    store.init(conn)
    return conn


def _commit(conn, sha, author, day, files, added, deleted, ctype=None):
    conn.execute(
        "INSERT INTO commits(hash, author_email, committer_date, files_changed, lines_added,"
        " lines_deleted, type) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (sha, author, day, files, added, deleted, ctype),
    )


def _by_author(rows):
    return {row["author"]: row for row in rows}


class AuthorProcessTests(unittest.TestCase):
    def test_reports_batch_size_per_author(self):
        conn = _store()
        _commit(conn, "c1", "ana", "2026-10-01T10:00:00+00:00", 2, 30, 10)
        _commit(conn, "c2", "ana", "2026-10-02T10:00:00+00:00", 4, 50, 0)
        _commit(conn, "c3", "bo", "2026-10-02T11:00:00+00:00", 1, 5, 1)

        rows = _by_author(analyse.author_process(conn))

        self.assertEqual(rows["ana"]["commits"], 2)
        self.assertEqual(rows["ana"]["avg_files_per_commit"], 3.0)
        self.assertEqual(rows["ana"]["max_files_in_commit"], 4)
        self.assertEqual(rows["ana"]["avg_lines_per_commit"], 45.0)
        self.assertEqual(rows["bo"]["commits"], 1)
        self.assertEqual(rows["bo"]["avg_lines_per_commit"], 6.0)

    def test_counts_active_days_per_author(self):
        conn = _store()
        _commit(conn, "c1", "ana", "2026-10-01T10:00:00+00:00", 1, 1, 0)
        _commit(conn, "c2", "ana", "2026-10-01T18:00:00+00:00", 1, 1, 0)
        _commit(conn, "c3", "ana", "2026-10-02T10:00:00+00:00", 1, 1, 0)

        row = _by_author(analyse.author_process(conn))["ana"]

        self.assertEqual(row["active_days"], 2)
        self.assertEqual(row["commits_per_day"], 1.5)

    def test_large_commits_are_attributed_to_their_own_author(self):
        conn = _store()
        _commit(conn, "big", "ana", "2026-10-01T10:00:00+00:00", 40, 400, 200)
        _commit(conn, "small", "bo", "2026-10-01T11:00:00+00:00", 1, 2, 0)

        rows = _by_author(analyse.author_process(conn))

        self.assertEqual(rows["ana"]["large_commits"], 1)
        self.assertEqual(rows["bo"]["large_commits"], 0)

    def test_conventional_compliance_is_per_author(self):
        conn = _store()
        _commit(conn, "c1", "ana", "2026-10-01T10:00:00+00:00", 1, 1, 0, "feat")
        _commit(conn, "c2", "ana", "2026-10-01T11:00:00+00:00", 1, 1, 0, None)
        _commit(conn, "c3", "bo", "2026-10-01T12:00:00+00:00", 1, 1, 0, "fix")

        rows = _by_author(analyse.author_process(conn))

        self.assertEqual(rows["ana"]["conventional_pct"], 50.0)
        self.assertEqual(rows["bo"]["conventional_pct"], 100.0)

    def test_orders_by_commit_count_descending(self):
        conn = _store()
        _commit(conn, "c1", "ana", "2026-10-01T10:00:00+00:00", 1, 1, 0)
        _commit(conn, "c2", "bo", "2026-10-01T11:00:00+00:00", 1, 1, 0)
        _commit(conn, "c3", "bo", "2026-10-01T12:00:00+00:00", 1, 1, 0)

        self.assertEqual([row["author"] for row in analyse.author_process(conn)], ["bo", "ana"])

    def test_empty_store_returns_no_rows(self):
        self.assertEqual(analyse.author_process(_store()), [])

    def test_null_author_does_not_break_the_ordering(self):
        conn = _store()
        _commit(conn, "c1", None, "2026-10-01T10:00:00+00:00", 1, 1, 0)
        _commit(conn, "c2", "ana", "2026-10-01T11:00:00+00:00", 1, 1, 0)

        rows = analyse.author_process(conn)

        self.assertEqual(len(rows), 2)
        self.assertEqual({row["author"] for row in rows}, {"", "ana"})


if __name__ == "__main__":
    unittest.main()
