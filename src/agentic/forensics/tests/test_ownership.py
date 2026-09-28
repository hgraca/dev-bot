#!/usr/bin/env python3
"""Unit tests for lib/ownership.py — blame aggregation anchored at a window end."""

from __future__ import annotations

import os
import sys
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import ownership  # noqa: E402


def utc(*args) -> datetime:
    return datetime(*args, tzinfo=timezone.utc)


def blame_line(number: int, commit: str, author: str, date: str) -> dict:
    return {"line": number, "hash": commit, "author_name": author, "author_email": author, "date": date}


CLASS_UNIT = {"path": "src/A.php", "name": "A", "kind": "class", "start_line": 1, "end_line": 3}


def owners(rows: list) -> dict:
    return {row["author"]: row["lines_owned"] for row in rows}


class AggregateUnitsTests(unittest.TestCase):
    def test_counts_every_author_when_no_until_is_given(self):
        lines = [
            blame_line(1, "c1", "ana", "2024-01-01T00:00:00+00:00"),
            blame_line(2, "c1", "ana", "2024-01-01T00:00:00+00:00"),
            blame_line(3, "c2", "bo", "2026-09-20T00:00:00+00:00"),
        ]
        rows, _ = ownership.aggregate_units(lines, [CLASS_UNIT], None)
        self.assertEqual(owners(rows), {"ana": 2, "bo": 1})

    def test_drops_lines_introduced_after_until(self):
        lines = [
            blame_line(1, "c1", "ana", "2024-01-01T00:00:00+00:00"),
            blame_line(2, "c1", "ana", "2024-01-01T00:00:00+00:00"),
            blame_line(3, "c2", "bo", "2026-09-20T00:00:00+00:00"),
        ]
        rows, _ = ownership.aggregate_units(lines, [CLASS_UNIT], utc(2026, 9, 1))
        self.assertEqual(owners(rows), {"ana": 2})

    def test_keeps_lines_introduced_before_the_window_start(self):
        """Ownership is cumulative up to the anchor — the window start does not bind it."""
        lines = [blame_line(1, "c1", "ana", "2016-02-01T00:00:00+00:00")]
        rows, _ = ownership.aggregate_units(lines, [CLASS_UNIT], utc(2026, 9, 28))
        self.assertEqual(owners(rows), {"ana": 1})

    def test_until_is_inclusive(self):
        lines = [blame_line(1, "c1", "ana", "2026-09-28T10:00:00+00:00")]
        rows, _ = ownership.aggregate_units(lines, [CLASS_UNIT], utc(2026, 9, 28, 10, 0, 0))
        self.assertEqual(owners(rows), {"ana": 1})

    def test_line_without_a_date_is_kept(self):
        lines = [blame_line(1, "c1", "ana", "")]
        rows, _ = ownership.aggregate_units(lines, [CLASS_UNIT], utc(2026, 9, 28))
        self.assertEqual(owners(rows), {"ana": 1})

    def test_every_line_after_until_leaves_no_owners(self):
        lines = [blame_line(1, "c1", "ana", "2026-09-29T00:00:00+00:00")]
        rows, churn = ownership.aggregate_units(lines, [CLASS_UNIT], utc(2026, 9, 28))
        self.assertEqual(rows, [])
        self.assertEqual(churn[0]["commits"], 0)

    def test_churn_counts_distinct_commits_and_active_days(self):
        lines = [
            blame_line(1, "c1", "ana", "2026-09-01T00:00:00+00:00"),
            blame_line(2, "c1", "ana", "2026-09-01T00:00:00+00:00"),
            blame_line(3, "c2", "bo", "2026-09-02T00:00:00+00:00"),
        ]
        _, churn = ownership.aggregate_units(lines, [CLASS_UNIT], None)
        self.assertEqual(churn[0]["commits"], 2)
        self.assertEqual(churn[0]["active_days"], 2)

    def test_last_change_is_the_newest_kept_line(self):
        lines = [
            blame_line(1, "c1", "ana", "2026-09-01T00:00:00+00:00"),
            blame_line(2, "c2", "bo", "2026-09-02T00:00:00+00:00"),
        ]
        rows, _ = ownership.aggregate_units(lines, [CLASS_UNIT], utc(2026, 9, 1, 12))
        self.assertEqual({row["last_change"] for row in rows}, {"2026-09-01T00:00:00+00:00"})


if __name__ == "__main__":
    unittest.main()
