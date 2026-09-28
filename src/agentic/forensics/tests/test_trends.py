#!/usr/bin/env python3
"""Unit tests for lib/trends.py — interval bucketing and revision sampling."""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import trends  # noqa: E402


class BucketTests(unittest.TestCase):
    def test_day(self):
        self.assertEqual(trends._bucket("2026-09-21T10:00:00+00:00", "day"), "2026-09-21")

    def test_week_is_the_iso_week(self):
        self.assertEqual(trends._bucket("2026-09-21T10:00:00+00:00", "week"), "2026-W39")
        self.assertEqual(trends._bucket("2026-09-28T10:00:00+00:00", "week"), "2026-W40")

    def test_month_is_the_default_for_an_unknown_interval(self):
        self.assertEqual(trends._bucket("2026-09-21T10:00:00+00:00", "month"), "2026-09")
        self.assertEqual(trends._bucket("2026-09-21T10:00:00+00:00", "bogus"), "2026-09")

    def test_quarter(self):
        self.assertEqual(trends._bucket("2026-09-21T10:00:00+00:00", "quarter"), "2026-Q3")
        self.assertEqual(trends._bucket("2026-01-01T10:00:00+00:00", "quarter"), "2026-Q1")

    def test_year(self):
        self.assertEqual(trends._bucket("2026-09-21T10:00:00+00:00", "year"), "2026")

    def test_unparseable_date_is_returned_verbatim(self):
        self.assertEqual(trends._bucket("not-a-date", "day"), "not-a-date")


class LastCommitPerBucketTests(unittest.TestCase):
    def test_keeps_the_last_commit_of_each_bucket(self):
        entries = [
            {"revision": "a", "date": "2026-09-01T10:00:00+00:00"},
            {"revision": "b", "date": "2026-09-01T18:00:00+00:00"},
            {"revision": "c", "date": "2026-09-02T10:00:00+00:00"},
        ]
        result = trends.last_commit_per_bucket(entries, "day")
        self.assertEqual([row["revision"] for row in result], ["b", "c"])

    def test_preserves_first_appearance_order(self):
        entries = [
            {"revision": "a", "date": "2026-01-05T10:00:00+00:00"},
            {"revision": "b", "date": "2026-03-05T10:00:00+00:00"},
            {"revision": "c", "date": "2026-02-05T10:00:00+00:00"},
        ]
        result = trends.last_commit_per_bucket(entries, "month")
        self.assertEqual([row["revision"] for row in result], ["a", "b", "c"])

    def test_a_week_collapses_to_one_sample(self):
        entries = [
            {"revision": "mon", "date": "2026-09-21T10:00:00+00:00"},
            {"revision": "fri", "date": "2026-09-25T10:00:00+00:00"},
        ]
        result = trends.last_commit_per_bucket(entries, "week")
        self.assertEqual([row["revision"] for row in result], ["fri"])

    def test_empty(self):
        self.assertEqual(trends.last_commit_per_bucket([], "day"), [])


if __name__ == "__main__":
    unittest.main()
