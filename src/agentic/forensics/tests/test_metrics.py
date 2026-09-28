#!/usr/bin/env python3
"""Unit tests for lib/metrics.py — window resolution, statistics and interval maths."""

from __future__ import annotations

import os
import sys
import unittest
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import metrics  # noqa: E402


def utc(*args) -> datetime:
    return datetime(*args, tzinfo=timezone.utc)


class MedianTests(unittest.TestCase):
    def test_empty_returns_none(self):
        self.assertIsNone(metrics.median([]))

    def test_single_value(self):
        self.assertEqual(metrics.median([7]), 7.0)

    def test_odd_count_returns_middle(self):
        self.assertEqual(metrics.median([3, 1, 2]), 2.0)

    def test_even_count_returns_mean_of_middle_two(self):
        self.assertEqual(metrics.median([1, 2, 3, 4]), 2.5)

    def test_unsorted_input(self):
        self.assertEqual(metrics.median([9, 1, 5, 3]), 4.0)


class CalendarDaysTests(unittest.TestCase):
    def test_same_day_is_one(self):
        self.assertEqual(metrics.calendar_days(utc(2026, 9, 21), utc(2026, 9, 21)), 1)

    def test_monday_to_friday_is_five(self):
        self.assertEqual(metrics.calendar_days(utc(2026, 9, 21), utc(2026, 9, 25)), 5)

    def test_across_month_boundary(self):
        self.assertEqual(metrics.calendar_days(utc(2026, 8, 30), utc(2026, 9, 2)), 4)

    def test_reversed_is_zero(self):
        self.assertEqual(metrics.calendar_days(utc(2026, 9, 25), utc(2026, 9, 21)), 0)


class PerDayTests(unittest.TestCase):
    def test_rate_over_window(self):
        self.assertEqual(metrics.per_day(10, utc(2026, 9, 21), utc(2026, 9, 25)), 2.0)

    def test_zero_window_is_zero(self):
        self.assertEqual(metrics.per_day(3, utc(2026, 9, 25), utc(2026, 9, 21)), 0.0)

    def test_zero_count_is_zero(self):
        self.assertEqual(metrics.per_day(0, utc(2026, 9, 21), utc(2026, 9, 25)), 0.0)


class MinusOneMonthTests(unittest.TestCase):
    def test_same_day_previous_month(self):
        self.assertEqual(metrics.minus_one_month(utc(2026, 9, 28)), utc(2026, 8, 28))

    def test_clamps_to_shorter_month(self):
        self.assertEqual(metrics.minus_one_month(utc(2026, 3, 31)), utc(2026, 2, 28))

    def test_clamps_in_leap_year(self):
        self.assertEqual(metrics.minus_one_month(utc(2024, 3, 31)), utc(2024, 2, 29))

    def test_crosses_year_boundary(self):
        self.assertEqual(metrics.minus_one_month(utc(2026, 1, 31)), utc(2025, 12, 31))

    def test_preserves_time(self):
        self.assertEqual(metrics.minus_one_month(utc(2026, 1, 15, 8, 30, 5)), utc(2025, 12, 15, 8, 30, 5))


class MergeIntervalsTests(unittest.TestCase):
    def test_empty(self):
        self.assertEqual(metrics.merge_intervals([]), [])

    def test_overlapping_merged(self):
        result = metrics.merge_intervals([(utc(2026, 9, 1), utc(2026, 9, 10)), (utc(2026, 9, 5), utc(2026, 9, 15))])
        self.assertEqual(result, [(utc(2026, 9, 1), utc(2026, 9, 15))])

    def test_adjacent_merged(self):
        result = metrics.merge_intervals([(utc(2026, 9, 1), utc(2026, 9, 10)), (utc(2026, 9, 10), utc(2026, 9, 20))])
        self.assertEqual(result, [(utc(2026, 9, 1), utc(2026, 9, 20))])

    def test_disjoint_kept_and_sorted(self):
        result = metrics.merge_intervals([(utc(2026, 9, 20), utc(2026, 9, 25)), (utc(2026, 9, 1), utc(2026, 9, 5))])
        self.assertEqual(result, [(utc(2026, 9, 1), utc(2026, 9, 5)), (utc(2026, 9, 20), utc(2026, 9, 25))])


class SubtractIntervalsTests(unittest.TestCase):
    def test_no_coverage_returns_whole_window(self):
        result = metrics.subtract_intervals(utc(2026, 9, 1), utc(2026, 9, 30), [])
        self.assertEqual(result, [(utc(2026, 9, 1), utc(2026, 9, 30))])

    def test_full_hit_returns_empty(self):
        result = metrics.subtract_intervals(utc(2026, 9, 1), utc(2026, 9, 30), [(utc(2026, 9, 1), utc(2026, 9, 30))])
        self.assertEqual(result, [])

    def test_partial_hit_returns_tail(self):
        result = metrics.subtract_intervals(utc(2026, 9, 1), utc(2026, 9, 30), [(utc(2026, 9, 1), utc(2026, 9, 10))])
        self.assertEqual(result, [(utc(2026, 9, 10), utc(2026, 9, 30))])

    def test_partial_hit_returns_head(self):
        result = metrics.subtract_intervals(utc(2026, 9, 1), utc(2026, 9, 30), [(utc(2026, 9, 20), utc(2026, 9, 30))])
        self.assertEqual(result, [(utc(2026, 9, 1), utc(2026, 9, 20))])

    def test_gap_in_the_middle(self):
        covered = [(utc(2026, 9, 5), utc(2026, 9, 10)), (utc(2026, 9, 20), utc(2026, 9, 25))]
        result = metrics.subtract_intervals(utc(2026, 9, 1), utc(2026, 9, 30), covered)
        self.assertEqual(
            result,
            [
                (utc(2026, 9, 1), utc(2026, 9, 5)),
                (utc(2026, 9, 10), utc(2026, 9, 20)),
                (utc(2026, 9, 25), utc(2026, 9, 30)),
            ],
        )

    def test_coverage_entirely_before_window(self):
        result = metrics.subtract_intervals(utc(2026, 9, 1), utc(2026, 9, 30), [(utc(2026, 8, 1), utc(2026, 8, 10))])
        self.assertEqual(result, [(utc(2026, 9, 1), utc(2026, 9, 30))])

    def test_coverage_entirely_after_window(self):
        result = metrics.subtract_intervals(utc(2026, 9, 1), utc(2026, 9, 30), [(utc(2026, 10, 1), utc(2026, 10, 10))])
        self.assertEqual(result, [(utc(2026, 9, 1), utc(2026, 9, 30))])

    def test_adjacent_coverage_is_a_full_hit(self):
        covered = [(utc(2026, 9, 1), utc(2026, 9, 15)), (utc(2026, 9, 15), utc(2026, 9, 30))]
        result = metrics.subtract_intervals(utc(2026, 9, 1), utc(2026, 9, 30), covered)
        self.assertEqual(result, [])


class ParseWhenTests(unittest.TestCase):
    def test_date_only_is_start_of_day_utc(self):
        self.assertEqual(metrics.parse_when("2026-09-21"), utc(2026, 9, 21, 0, 0, 0))

    def test_date_only_end_of_day(self):
        self.assertEqual(metrics.parse_when("2026-09-21", end_of_day=True), utc(2026, 9, 21, 23, 59, 59))

    def test_iso_datetime_with_offset_preserved(self):
        self.assertEqual(metrics.parse_when("2026-09-21T12:30:00+02:00"), utc(2026, 9, 21, 10, 30, 0))

    def test_naive_datetime_treated_as_utc(self):
        self.assertEqual(metrics.parse_when("2026-09-21T12:30:00"), utc(2026, 9, 21, 12, 30, 0))

    def test_invalid_raises(self):
        with self.assertRaises(ValueError):
            metrics.parse_when("not-a-date")


class ResolveWindowTests(unittest.TestCase):
    def test_both_given(self):
        since, until = metrics.resolve_window("2026-09-21", "2026-09-25", now=utc(2026, 9, 28, 12))
        self.assertEqual(since, utc(2026, 9, 21, 0, 0, 0))
        self.assertEqual(until, utc(2026, 9, 25, 23, 59, 59))

    def test_only_until_defaults_since_to_one_month_before(self):
        since, until = metrics.resolve_window(None, "2026-09-25", now=utc(2026, 9, 28, 12))
        self.assertEqual(until, utc(2026, 9, 25, 23, 59, 59))
        self.assertEqual(since, utc(2026, 8, 25, 23, 59, 59))

    def test_neither_defaults_to_last_month_from_now(self):
        since, until = metrics.resolve_window(None, None, now=utc(2026, 9, 28, 12, 0, 0))
        self.assertEqual(until, utc(2026, 9, 28, 12, 0, 0))
        self.assertEqual(since, utc(2026, 8, 28, 12, 0, 0))


if __name__ == "__main__":
    unittest.main()
