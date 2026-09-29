#!/usr/bin/env python3
"""Unit tests for lib/analyse.py — the module roll-up."""

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


def _commit(conn, sha, author="alice@example.com"):
    conn.execute(
        "INSERT INTO commits(hash, author_email, date, committer_date, message, type)"
        " VALUES (?, ?, '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:00+00:00', 'feat: x', 'feat')",
        (sha, author),
    )


def _change(conn, sha, path):
    conn.execute("INSERT INTO changes(commit_hash, path) VALUES (?, ?)", (sha, path))


class ModulesTests(unittest.TestCase):
    def test_commits_counts_distinct_commits_not_file_touches(self):
        conn = _store()
        conn.execute("INSERT INTO boundaries(module, prefix) VALUES ('Core', 'app/Core')")
        # One commit touching two files, then a second touching one of them.
        _commit(conn, "a")
        _change(conn, "a", "app/Core/one.php")
        _change(conn, "a", "app/Core/two.php")
        _commit(conn, "b")
        _change(conn, "b", "app/Core/one.php")

        rows = {row["module"]: row for row in analyse.modules(conn)}

        self.assertEqual(rows["Core"]["commits"], 2, rows)
        self.assertEqual(rows["Core"]["files"], 2, rows)
        self.assertEqual(rows["Core"]["authors"], 1, rows)


if __name__ == "__main__":
    unittest.main()
