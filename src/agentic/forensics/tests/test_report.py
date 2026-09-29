#!/usr/bin/env python3
"""Unit tests for lib/report.py — the assembled document and its coverage block."""

from __future__ import annotations

import os
import sqlite3
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import report  # noqa: E402
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
    conn.execute("INSERT INTO changes(commit_hash, path) VALUES ('a', 'app/a.php')")
    return conn


class DataQualityTests(unittest.TestCase):
    def test_absent_optional_sources_are_reported_with_their_remedy(self):
        conn = _store()

        doc = report.build(conn)
        quality = {row["source"]: row for row in doc["data-quality"]}

        self.assertEqual(quality["external defects"]["count"], 0)
        self.assertEqual(quality["external defects"]["enable"], "mine --defects <csv>")
        self.assertEqual(quality["complexity trends"]["enable"], "mine --trends")
        self.assertEqual(quality["module boundaries"]["enable"], "mine --modules name=prefix,...")

    def test_the_szz_row_states_its_remedy_and_tickets_are_counted(self):
        conn = _store()
        conn.execute("UPDATE commits SET ticket = 'TP-1' WHERE hash = 'a'")

        quality = {row["source"]: row for row in report.build(conn)["data-quality"]}

        self.assertEqual(quality["SZZ defect links"]["count"], 0)
        self.assertEqual(quality["SZZ defect links"]["enable"], "mine without --no-defects")
        self.assertEqual(quality["tickets"]["count"], 1)

    def test_the_markdown_renders_the_data_quality_section(self):
        conn = _store()

        rendered = report.to_markdown(report.build(conn))

        self.assertIn("## Data quality", rendered)
        self.assertIn("--defects", rendered)


if __name__ == "__main__":
    unittest.main()
