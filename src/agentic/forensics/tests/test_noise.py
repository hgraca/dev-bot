#!/usr/bin/env python3
"""Unit tests for the noise-path filter in lib/analyse.py."""

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
    conn.execute(
        "INSERT INTO commits(hash, author_email, date, committer_date, message, type)"
        " VALUES ('a', 'alice@example.com', '2026-01-01T00:00:00+00:00',"
        " '2026-01-01T00:00:00+00:00', 'feat: x', 'feat')"
    )
    return conn


def _change(conn, path):
    conn.execute("INSERT INTO changes(commit_hash, path) VALUES ('a', ?)", (path,))


class NoisePathTests(unittest.TestCase):
    def test_vendored_and_tool_owned_paths_are_noise(self):
        for path in ("vendor/lib/x.php", "node_modules/p/i.js", ".agents/memory/n.md", "storage/logs/l.log", "phpstan-baseline.neon"):
            self.assertTrue(analyse._is_noise(path), path)

    def test_real_source_is_not_noise(self):
        for path in ("app/Services/GoogleApi.php", "tests/Unit/FooTest.php", ".github/workflows/ci.yml"):
            self.assertFalse(analyse._is_noise(path), path)

    def test_file_views_exclude_noise_paths(self):
        conn = _store()
        _change(conn, "app/Service.php")
        _change(conn, ".agents/memory/note.md")
        _change(conn, "storage/logs/laravel.log")
        store.derive_files(conn)

        rates = {row["path"] for row in analyse.change_rate(conn)}
        self.assertIn("app/Service.php", rates, rates)
        self.assertNotIn(".agents/memory/note.md", rates, rates)
        self.assertNotIn("storage/logs/laravel.log", rates, rates)

        owned = {row["path"] for row in analyse.ownership(conn)}
        self.assertIn("app/Service.php", owned, owned)
        self.assertNotIn(".agents/memory/note.md", owned, owned)


if __name__ == "__main__":
    unittest.main()
