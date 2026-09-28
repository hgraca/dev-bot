#!/usr/bin/env python3
"""Unit tests for lib/prstore.py — the stable pull-request cache."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import prstore  # noqa: E402


def utc(*args) -> datetime:
    return datetime(*args, tzinfo=timezone.utc)


def pr(number, merged_at, **overrides) -> dict:
    row = {
        "number": number,
        "author": "hgraca",
        "created_at": "2026-09-24T13:13:33Z",
        "merged_at": merged_at,
        "commits": 7,
        "added": 749,
        "deleted": 179,
        "changed_files": 32,
        "url": "https://example/%d" % number,
    }
    row.update(overrides)
    return row


class PrStoreTests(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.db = os.path.join(self._dir.name, "prs.sqlite")
        self.conn = prstore.connect(self.db)
        prstore.init(self.conn)

    def tearDown(self):
        self.conn.close()
        self._dir.cleanup()

    def test_check_passes_after_init(self):
        self.assertIsNone(prstore.check(self.conn))

    def test_check_reports_an_unreadable_database(self):
        other = prstore.connect(os.path.join(self._dir.name, "fresh.sqlite"))
        self.assertIsNotNone(prstore.check(other))
        other.close()

    def test_check_rejects_a_database_without_a_version(self):
        other = prstore.connect(os.path.join(self._dir.name, "noversion.sqlite"))
        other.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
        other.commit()
        self.assertIn("not a forensics PR cache", prstore.check(other))
        other.close()

    def test_check_rejects_a_wrong_version(self):
        self.conn.execute("UPDATE meta SET value = '99' WHERE key = 'schema_version'")
        self.conn.commit()
        self.assertIn("schema_version", prstore.check(self.conn))

    def test_check_rejects_a_database_without_the_tables(self):
        other = prstore.connect(os.path.join(self._dir.name, "notables.sqlite"))
        other.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
        other.execute("INSERT INTO meta(key, value) VALUES ('schema_version', ?)", (prstore.SCHEMA_VERSION,))
        other.commit()
        self.assertIn("pr_coverage", prstore.check(other))
        other.close()

    def test_query_merged_filters_by_window(self):
        prstore.upsert_prs(
            self.conn,
            "github",
            "GET-E/core",
            [pr(1, "2026-09-21T09:00:00Z"), pr(2, "2026-09-25T14:36:11Z"), pr(3, "2026-10-02T10:00:00Z")],
        )
        rows = prstore.query_merged(
            self.conn, "github", "GET-E/core", utc(2026, 9, 21), utc(2026, 9, 25, 23, 59, 59)
        )
        self.assertEqual([row["number"] for row in rows], [1, 2])

    def test_query_merged_excludes_unmerged(self):
        prstore.upsert_prs(self.conn, "github", "GET-E/core", [pr(1, "")])
        rows = prstore.query_merged(self.conn, "github", "GET-E/core", utc(2026, 9, 1), utc(2026, 9, 30))
        self.assertEqual(rows, [])

    def test_upsert_is_idempotent_and_updates(self):
        prstore.upsert_prs(self.conn, "github", "GET-E/core", [pr(1, "2026-09-25T14:36:11Z", commits=7)])
        prstore.upsert_prs(self.conn, "github", "GET-E/core", [pr(1, "2026-09-25T14:36:11Z", commits=9)])
        rows = prstore.query_merged(self.conn, "github", "GET-E/core", utc(2026, 9, 1), utc(2026, 9, 30))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["commits"], 9)

    def test_sources_and_repos_are_isolated(self):
        prstore.upsert_prs(self.conn, "github", "GET-E/core", [pr(1, "2026-09-25T14:36:11Z")])
        window = (utc(2026, 9, 1), utc(2026, 9, 30))
        self.assertEqual(prstore.query_merged(self.conn, "gitlab", "GET-E/core", *window), [])
        self.assertEqual(prstore.query_merged(self.conn, "github", "GET-E/other", *window), [])

    def test_timestamps_are_normalised_to_utc(self):
        prstore.upsert_prs(self.conn, "github", "GET-E/core", [pr(1, "2026-09-25T16:36:11+02:00")])
        rows = prstore.query_merged(self.conn, "github", "GET-E/core", utc(2026, 9, 1), utc(2026, 9, 30))
        self.assertTrue(rows[0]["merged_at"].endswith("+00:00"))

    def test_coverage_round_trip(self):
        prstore.record_coverage(
            self.conn, "github", "GET-E/core", utc(2026, 9, 21), utc(2026, 9, 25, 23, 59, 59)
        )
        intervals = prstore.covered(self.conn, "github", "GET-E/core")
        self.assertEqual(intervals, [(utc(2026, 9, 21), utc(2026, 9, 25, 23, 59, 59))])

    def test_coverage_is_scoped_by_source_and_repo(self):
        prstore.record_coverage(self.conn, "github", "GET-E/core", utc(2026, 9, 21), utc(2026, 9, 25))
        self.assertEqual(prstore.covered(self.conn, "gitlab", "GET-E/core"), [])
        self.assertEqual(prstore.covered(self.conn, "github", "GET-E/other"), [])
        self.assertEqual(len(prstore.covered(self.conn, "github", "GET-E/core")), 1)


if __name__ == "__main__":
    unittest.main()
