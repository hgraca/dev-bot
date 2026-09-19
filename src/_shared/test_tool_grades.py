#!/usr/bin/env python3
"""Unit tests for ``src/_shared/tool_grades.py`` — the grade aggregation helper.

Exercises the pure functions (scope, averages, kind mapping, notes attribution,
dedupe) and the CLI that attaches the block to the canonical stats JSON.
"""
from __future__ import annotations

import csv
import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tool_grades as tg  # noqa: E402

BASE = ["session_id", "datetime", "project", "notes"]
HEADER = BASE + [
    "mcp:datasources",
    "mcp:devbot-tools:search-memories",
    "mcp:signoz",
    "skill:devbot:makefile",
    "skill:devbot:agent-communication",
    "skill:test-driven-development",
]


def write_csv(path: str, header: list[str], rows: list[dict]) -> str:
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow(header)
        for row in rows:
            writer.writerow([row.get(column, "") for column in header])
    return path


def row(project: str = "Get-e/dev-bot", notes: str = "", grades: dict | None = None) -> dict:
    base = {
        "session_id": "s-01",
        "datetime": "2026-09-18 12:00:00",
        "project": project,
        "notes": notes,
    }
    # Cells are strings, exactly as read_rows() yields them from the CSV.
    base.update({column: str(grade) for column, grade in (grades or {}).items()})
    return base


def dated(when: str, project: str = "Get-e/dev-bot", grades: dict | None = None) -> dict:
    """A row stamped with an explicit datetime — or deliberately stripped of one."""
    stamped = row(project=project, grades=grades)
    stamped["datetime"] = when
    return stamped


class ToolGradesTest(unittest.TestCase):
    @staticmethod
    def _tool(block: dict, column: str) -> dict:
        for tool in block["tools"]:
            if tool["column"] == column:
                return tool
        raise AssertionError(f"{column} not in {[t['column'] for t in block['tools']]}")

    # ── pure helpers ──────────────────────────────────────────────────────────

    def test_project_name_takes_last_two_components(self):
        self.assertEqual(tg.project_name("/home/me/Get-e/dev-bot"), "Get-e/dev-bot")
        self.assertEqual(tg.project_name("/solo"), "solo")

    def test_tool_kind_classifies_each_group(self):
        self.assertEqual(tg.tool_kind("mcp:datasources"), "mcp")
        self.assertEqual(tg.tool_kind("mcp:devbot-tools:format-md"), "devbot-tool")
        self.assertEqual(tg.tool_kind("skill:devbot:makefile"), "skill")

    def test_display_name_strips_the_prefix(self):
        self.assertEqual(tg.display_name("mcp:datasources"), "datasources")
        self.assertEqual(tg.display_name("mcp:devbot-tools:format-md"), "devbot-tools:format-md")
        self.assertEqual(tg.display_name("skill:devbot:makefile"), "devbot:makefile")

    def test_reason_texts_match_label_and_short_name(self):
        notes = (
            "devbot:makefile (3): guided the make targets, but the Makefile itself is the substitute.\n"
            "makefile: its app-container model does not match.\n"
            "unrelated: no match here."
        )
        self.assertEqual(
            tg.reason_texts(notes, "skill:devbot:makefile"),
            [
                "guided the make targets, but the Makefile itself is the substitute.",
                "its app-container model does not match.",
            ],
        )

    def test_reason_texts_match_short_name_for_devbot_tool(self):
        notes = "search-memories: surfaced a stale index entry.\n"
        self.assertEqual(
            tg.reason_texts(notes, "mcp:devbot-tools:search-memories"),
            ["surfaced a stale index entry."],
        )

    def test_reason_texts_ignore_blank_and_preamble_lines(self):
        notes = "\n\nWhole session (SAML SSO).\n\nmakefile (1): loaded preemptively.\n\n"
        self.assertEqual(tg.reason_texts(notes, "skill:devbot:makefile"), ["loaded preemptively."])

    def test_reason_texts_find_a_whole_word_mention_anywhere(self):
        notes = "The reindex-memories tool launched a full build instead of the cheap prune.\n"
        self.assertEqual(
            tg.reason_texts(notes, "mcp:devbot-tools:reindex-memories"),
            ["The reindex-memories tool launched a full build instead of the cheap prune."],
        )

    def test_reason_texts_strip_a_dash_separator(self):
        notes = "makefile - the Makefile covered it.\n"
        self.assertEqual(
            tg.reason_texts(notes, "skill:devbot:makefile"), ["the Makefile covered it."]
        )

    def test_shared_short_name_line_goes_to_one_column(self):
        notes = "datasources: indispensable early.\ndevbot:datasources: skill-level note.\n"
        attributed = tg.attribute_reasons(notes, ["mcp:datasources", "skill:devbot:datasources"])
        self.assertEqual(attributed["mcp:datasources"], ["indispensable early."])
        self.assertEqual(attributed["skill:devbot:datasources"], ["skill-level note."])

    def test_shared_short_name_reason_is_not_duplicated_across_tools(self):
        header = BASE + ["mcp:datasources", "skill:devbot:datasources"]
        rows = [
            row(
                notes="datasources: covered the same ground.\n",
                grades={"mcp:datasources": 2, "skill:devbot:datasources": 2},
            )
        ]
        block = tg.aggregate(header, rows)
        texts = {t["name"]: [r["text"] for r in t["reasons"]] for t in block["tools"]}
        self.assertEqual(texts["datasources"], ["covered the same ground."])
        self.assertEqual(texts["devbot:datasources"], [])

    # ── aggregation ───────────────────────────────────────────────────────────

    def test_avg_ignores_unused_rows(self):
        rows = [
            row(grades={"mcp:signoz": 5}),
            row(grades={"mcp:signoz": 0}),
            row(grades={"mcp:signoz": 3}),
        ]
        signoz = self._tool(tg.aggregate(HEADER, rows), "mcp:signoz")
        self.assertEqual(signoz["avg"], 4.0)
        self.assertEqual(signoz["uses"], 2)

    def test_unused_tool_is_listed_without_usage(self):
        rows = [row(grades={"mcp:signoz": 0}), row(grades={"mcp:signoz": 0})]
        signoz = self._tool(tg.aggregate(HEADER, rows), "mcp:signoz")
        self.assertIsNone(signoz["avg"])
        self.assertEqual(signoz["uses"], 0)
        self.assertEqual(signoz["reasons"], [])

    def test_reasons_come_only_from_poor_graded_rows(self):
        rows = [
            row(notes="signoz: critical, the only verification path.\n", grades={"mcp:signoz": 5}),
            row(notes="signoz: flaky and wrong.\n", grades={"mcp:signoz": 2}),
        ]
        signoz = self._tool(tg.aggregate(HEADER, rows), "mcp:signoz")
        self.assertEqual([r["text"] for r in signoz["reasons"]], ["flaky and wrong."])

    def test_reasons_dedupe_case_and_whitespace_insensitively(self):
        rows = [
            row(notes="makefile (3): The Makefile covered it.\n", grades={"skill:devbot:makefile": 3}),
            row(notes="makefile (3): the  makefile   covered it\n", grades={"skill:devbot:makefile": 3}),
        ]
        makefile = self._tool(tg.aggregate(HEADER, rows), "skill:devbot:makefile")
        self.assertEqual(len(makefile["reasons"]), 1)
        self.assertEqual(makefile["reasons"][0]["count"], 2)
        self.assertEqual(makefile["reasons"][0]["text"], "The Makefile covered it.")

    def test_tools_sorted_by_average_descending_with_unused_last(self):
        rows = [
            row(grades={"mcp:signoz": 5, "mcp:datasources": 3, "skill:devbot:makefile": 1})
        ]
        tools = tg.aggregate(HEADER, rows)["tools"]
        self.assertEqual(
            [t["name"] for t in tools[:3]], ["signoz", "datasources", "devbot:makefile"]
        )
        self.assertTrue(all(t["uses"] == 0 for t in tools[3:]))
        self.assertEqual(len(tools), len(HEADER) - len(BASE))

    def test_scope_project_filters_rows(self):
        rows = [
            row(project="Get-e/dev-bot", grades={"mcp:signoz": 5}),
            row(project="Get-e/core", grades={"mcp:signoz": 1}),
        ]
        block = tg.aggregate(HEADER, rows, scope_project="Get-e/dev-bot")
        self.assertEqual(self._tool(block, "mcp:signoz")["avg"], 5.0)
        self.assertEqual(self._tool(block, "mcp:signoz")["uses"], 1)
        self.assertEqual(block["rows"], 1)

    def test_scope_all_keeps_every_project(self):
        rows = [
            row(project="Get-e/dev-bot", grades={"mcp:signoz": 5}),
            row(project="Get-e/core", grades={"mcp:signoz": 1}),
        ]
        block = tg.aggregate(HEADER, rows)
        self.assertEqual(self._tool(block, "mcp:signoz")["uses"], 2)
        self.assertEqual(block["rows"], 2)

    def test_block_reports_total_rows_and_distinct_sessions(self):
        first = row(project="Get-e/dev-bot", grades={"mcp:signoz": 5})
        first["session_id"] = "ses_a-01"
        second = row(project="Get-e/core", grades={"mcp:signoz": 1})
        second["session_id"] = "ses_a-02"
        third = row(project="Get-e/core", grades={"mcp:signoz": 3})
        third["session_id"] = "ses_b-01"
        block = tg.aggregate(HEADER, [first, second, third], scope_project="Get-e/dev-bot")
        self.assertEqual(block["rows"], 1)
        self.assertEqual(block["total_rows"], 3)
        self.assertEqual(block["sessions"], 2)

    # ── build_tool_grades ─────────────────────────────────────────────────────

    def test_build_returns_none_when_csv_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(tg.build_tool_grades(os.path.join(tmp, "nope.csv"), "all", tmp))

    def test_build_returns_none_when_no_data_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_csv(os.path.join(tmp, "g.csv"), HEADER, [])
            self.assertIsNone(tg.build_tool_grades(path, "all", tmp))

    def test_build_returns_none_when_scope_matches_no_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_csv(
                os.path.join(tmp, "g.csv"),
                HEADER,
                [row(project="Other/proj", grades={"mcp:signoz": 5})],
            )
            self.assertIsNone(tg.build_tool_grades(path, "current", tmp))

    def test_build_lists_every_column_even_when_unused_in_scope(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_csv(
                os.path.join(tmp, "g.csv"), HEADER, [row(grades={"mcp:signoz": 5})]
            )
            block = tg.build_tool_grades(path, "all", tmp)
        assert block is not None
        self.assertEqual(self._tool(block, "mcp:datasources")["uses"], 0)
        self.assertIn("datasources", [t["name"] for t in block["tools"]])

    def test_build_warns_and_returns_none_on_bad_header(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "g.csv")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write("foo,bar\n1,2\n")
            warnings: list[str] = []
            block = tg.build_tool_grades(path, "all", tmp, warn=warnings.append)
        self.assertIsNone(block)
        self.assertEqual(len(warnings), 1)
        self.assertTrue(warnings[0].startswith("WARN:"))

    def test_build_warns_on_bad_header_even_without_data_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "g.csv")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write("this is not,a grades csv at all\n")
            warnings: list[str] = []
            block = tg.build_tool_grades(path, "all", tmp, warn=warnings.append)
        self.assertIsNone(block)
        self.assertEqual(len(warnings), 1)
        self.assertTrue(warnings[0].startswith("WARN:"))

    def test_build_warns_and_returns_none_on_non_utf8(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "g.csv")
            with open(path, "wb") as fh:
                fh.write(b"session_id,datetime,project,notes\n\xff\xfe,,\n")
            warnings: list[str] = []
            block = tg.build_tool_grades(path, "all", tmp, warn=warnings.append)
        self.assertIsNone(block)
        self.assertEqual(len(warnings), 1)
        self.assertTrue(warnings[0].startswith("WARN:"))

    def test_build_parses_multiline_and_escaped_quote_notes(self):
        header = BASE + ["mcp:devbot-tools:reindex-memories", "skill:devbot:makefile"]
        notes = (
            'reindex-memories: "prune" launched a full build.\n\n'
            "makefile (3): covered elsewhere.\n"
        )
        rows = [
            row(
                notes=notes,
                grades={"mcp:devbot-tools:reindex-memories": 2, "skill:devbot:makefile": 3},
            )
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = write_csv(os.path.join(tmp, "g.csv"), header, rows)
            block = tg.build_tool_grades(path, "all", tmp)
        assert block is not None
        reindex = self._tool(block, "mcp:devbot-tools:reindex-memories")
        self.assertEqual(reindex["reasons"][0]["text"], '"prune" launched a full build.')

    # ── derived metrics ───────────────────────────────────────────────────────

    def test_min_is_the_worst_grade_recorded(self):
        rows = [
            row(grades={"mcp:signoz": 5}),
            row(grades={"mcp:signoz": 3}),
            row(grades={"mcp:signoz": 4}),
        ]
        signoz = self._tool(tg.aggregate(HEADER, rows), "mcp:signoz")
        self.assertEqual(signoz["min"], 3)

    def test_min_is_none_for_an_unused_tool(self):
        signoz = self._tool(tg.aggregate(HEADER, [row(grades={"mcp:signoz": 0})]), "mcp:signoz")
        self.assertIsNone(signoz["min"])

    def test_stdev_is_none_below_the_minimum_uses(self):
        rows = [row(grades={"mcp:signoz": 5}), row(grades={"mcp:signoz": 1})]
        signoz = self._tool(tg.aggregate(HEADER, rows), "mcp:signoz")
        self.assertEqual(signoz["uses"], 2)
        self.assertIsNone(signoz["stdev"])

    def test_stdev_is_none_for_an_unused_tool(self):
        signoz = self._tool(tg.aggregate(HEADER, [row(grades={"mcp:signoz": 0})]), "mcp:signoz")
        self.assertIsNone(signoz["stdev"])

    def test_stdev_is_zero_when_every_use_scored_the_same(self):
        rows = [row(grades={"mcp:signoz": 4}) for _ in range(3)]
        signoz = self._tool(tg.aggregate(HEADER, rows), "mcp:signoz")
        self.assertEqual(signoz["stdev"], 0.0)

    def test_stdev_is_the_population_spread_not_the_sample_spread(self):
        # Grades [1, 3, 5]: population stdev 1.63, sample stdev 2.00.
        rows = [
            row(grades={"mcp:signoz": 1}),
            row(grades={"mcp:signoz": 3}),
            row(grades={"mcp:signoz": 5}),
        ]
        signoz = self._tool(tg.aggregate(HEADER, rows), "mcp:signoz")
        self.assertEqual(signoz["stdev"], 1.63)

    # ── demand bar ────────────────────────────────────────────────────────────

    def test_demand_bar_never_drops_below_the_floor(self):
        self.assertEqual(tg.demand_bar([1, 1, 2, 7]), tg.MIN_MANY_USES)

    def test_demand_bar_ignores_unused_tools(self):
        self.assertEqual(tg.demand_bar([0, 0, 1, 1, 2, 7]), tg.MIN_MANY_USES)

    def test_demand_bar_falls_back_to_the_floor_when_nothing_was_used(self):
        self.assertEqual(tg.demand_bar([]), tg.MIN_MANY_USES)
        self.assertEqual(tg.demand_bar([0, 0]), tg.MIN_MANY_USES)

    def test_demand_bar_accepts_a_median_equal_to_the_floor(self):
        self.assertEqual(tg.demand_bar([3, 3]), tg.MIN_MANY_USES)

    def test_demand_bar_uses_the_median_once_it_exceeds_the_floor(self):
        self.assertEqual(tg.demand_bar([4, 5, 6, 7]), 6)

    def test_demand_bar_rounds_an_even_median_up(self):
        self.assertEqual(tg.demand_bar([6, 7]), 7)

    # ── buckets ───────────────────────────────────────────────────────────────

    def test_bucket_is_unused_when_the_tool_was_never_used(self):
        self.assertEqual(tg.classify_bucket(None, 0, 3), "unused")

    def test_bucket_workhorse_needs_an_average_above_the_quality_threshold(self):
        self.assertEqual(tg.classify_bucket(tg.QUALITY_THRESHOLD + 0.01, 5, 3), "workhorse")

    def test_bucket_treats_an_exactly_neutral_average_as_poor(self):
        self.assertEqual(tg.classify_bucket(tg.QUALITY_THRESHOLD, 5, 3), "improve")

    def test_bucket_quality_bar_sits_between_the_rubric_poor_and_good(self):
        # 3 is "poor" per POOR_GRADES and 4 is "good", so the bar is their midpoint.
        self.assertEqual(tg.QUALITY_THRESHOLD, 3.5)
        self.assertEqual(tg.classify_bucket(3.4, 5, 3), "improve")

    def test_bucket_workhorse_needs_at_least_the_demand_bar(self):
        self.assertEqual(tg.classify_bucket(4.0, 3, 3), "workhorse")
        self.assertEqual(tg.classify_bucket(4.0, 2, 3), "specialist")

    def test_bucket_improve_needs_at_least_the_demand_bar(self):
        self.assertEqual(tg.classify_bucket(2.5, 3, 3), "improve")
        self.assertEqual(tg.classify_bucket(2.5, 2, 3), "unproven")

    def test_block_emits_the_resolved_bar_and_the_quality_threshold(self):
        block = tg.aggregate(HEADER, [row(grades={"mcp:signoz": 5})])
        self.assertEqual(block["demand_bar"], tg.MIN_MANY_USES)
        self.assertEqual(block["quality_threshold"], tg.QUALITY_THRESHOLD)

    def test_block_places_every_tool_in_exactly_one_bucket(self):
        # Uses 5/4/2/1/0/3 give a median of 3, so the bar resolves to 3.
        rows = [
            row(
                grades={
                    "mcp:datasources": 5,
                    "mcp:devbot-tools:search-memories": 1,
                    "mcp:signoz": 5,
                    "skill:devbot:makefile": 1,
                    "skill:test-driven-development": 3,
                }
            ),
            row(
                grades={
                    "mcp:datasources": 5,
                    "mcp:devbot-tools:search-memories": 1,
                    "mcp:signoz": 5,
                    "skill:test-driven-development": 3,
                }
            ),
            row(
                grades={
                    "mcp:datasources": 5,
                    "mcp:devbot-tools:search-memories": 1,
                    "skill:test-driven-development": 3,
                }
            ),
            row(grades={"mcp:datasources": 5, "mcp:devbot-tools:search-memories": 1}),
            row(grades={"mcp:datasources": 5}),
        ]
        block = tg.aggregate(HEADER, rows)
        self.assertEqual(block["demand_bar"], 3)
        self.assertEqual(
            {t["name"]: t["bucket"] for t in block["tools"]},
            {
                "datasources": "workhorse",
                "devbot-tools:search-memories": "improve",
                "signoz": "specialist",
                "devbot:makefile": "unproven",
                "devbot:agent-communication": "unused",
                "test-driven-development": "improve",
            },
        )

    # ── window ────────────────────────────────────────────────────────────────

    def test_window_keeps_only_rows_inside_the_window(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        rows = [
            dated("2026-09-19 11:00:00"),
            dated("2026-09-10 12:00:00"),
            dated("2026-08-01 12:00:00"),
        ]
        kept = [r["datetime"] for r in tg.window_rows(rows, 30, now)]
        self.assertEqual(kept, ["2026-09-19 11:00:00", "2026-09-10 12:00:00"])

    def test_window_includes_a_row_exactly_on_the_cutoff(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        rows = [dated("2026-08-20 12:00:00"), dated("2026-08-20 11:59:59")]
        kept = [r["datetime"] for r in tg.window_rows(rows, 30, now)]
        self.assertEqual(kept, ["2026-08-20 12:00:00"])

    def test_window_keeps_an_undated_row_between_two_rows_inside(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        rows = [dated("2026-09-18 12:00:00"), dated(""), dated("2026-09-17 12:00:00")]
        self.assertEqual(len(tg.window_rows(rows, 30, now)), 3)

    def test_window_drops_an_undated_row_whose_preceding_row_is_outside(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        rows = [dated("2026-01-01 12:00:00"), dated(""), dated("2026-09-17 12:00:00")]
        self.assertEqual(len(tg.window_rows(rows, 30, now)), 1)

    def test_window_drops_an_undated_row_whose_following_row_is_outside(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        # The window's bound is a lower one, so with the matrix in append order
        # a following row is inside whenever the preceding one is. Only an
        # out-of-order stamp can push it out — which is what this pins.
        rows = [dated("2026-09-18 12:00:00"), dated(""), dated("2026-01-01 12:00:00")]
        kept = [r["datetime"] for r in tg.window_rows(rows, 30, now)]
        self.assertEqual(kept, ["2026-09-18 12:00:00"])

    def test_window_treats_an_unparseable_datetime_as_undated(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        rows = [dated("2026-09-18 12:00:00"), dated("whenever"), dated("2026-09-17 12:00:00")]
        self.assertEqual(len(tg.window_rows(rows, 30, now)), 3)

    def test_window_keeps_a_run_of_undated_rows_between_rows_inside(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        rows = [
            dated("2026-09-18 12:00:00"),
            dated(""),
            dated(""),
            dated("2026-09-17 12:00:00"),
        ]
        self.assertEqual(len(tg.window_rows(rows, 30, now)), 4)

    def test_window_drops_an_undated_row_at_the_head(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        rows = [dated(""), dated("2026-09-18 12:00:00")]
        kept = [r["datetime"] for r in tg.window_rows(rows, 30, now)]
        self.assertEqual(kept, ["2026-09-18 12:00:00"])

    def test_window_drops_an_undated_row_at_the_tail(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        rows = [dated("2026-09-18 12:00:00"), dated("")]
        kept = [r["datetime"] for r in tg.window_rows(rows, 30, now)]
        self.assertEqual(kept, ["2026-09-18 12:00:00"])

    def test_window_drops_every_row_when_none_is_dated(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        self.assertEqual(tg.window_rows([dated(""), dated("")], 30, now), [])

    def test_aggregate_windows_the_rows_but_keeps_the_all_time_total(self):
        now = datetime(2026, 9, 19, 12, 0, 0)
        rows = [
            dated("2026-09-18 12:00:00", grades={"mcp:signoz": 5}),
            dated("2026-01-01 12:00:00", grades={"mcp:signoz": 1}),
        ]
        block = tg.aggregate(HEADER, rows, days=30, now=now)
        self.assertEqual(block["rows"], 1)
        self.assertEqual(block["total_rows"], 2)
        signoz = self._tool(block, "mcp:signoz")
        self.assertEqual(signoz["avg"], 5.0)
        self.assertEqual(signoz["uses"], 1)

    def test_aggregate_emits_the_window_it_applied(self):
        rows = [dated("2026-09-18 12:00:00", grades={"mcp:signoz": 5})]
        self.assertEqual(tg.aggregate(HEADER, rows, days=7, now=datetime(2026, 9, 19))["days"], 7)

    def test_aggregate_reports_no_window_when_none_is_applied(self):
        rows = [dated("2026-09-18 12:00:00", grades={"mcp:signoz": 5})]
        self.assertIsNone(tg.aggregate(HEADER, rows)["days"])

    def test_build_windows_the_csv_rows_when_days_is_given(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_csv(
                os.path.join(tmp, "g.csv"),
                HEADER,
                [
                    dated("2026-09-18 12:00:00", grades={"mcp:signoz": 5}),
                    dated("2026-01-01 12:00:00", grades={"mcp:signoz": 1}),
                ],
            )
            block = tg.build_tool_grades(path, "all", tmp, days=30, now=datetime(2026, 9, 19, 12, 0, 0))
        assert block is not None
        self.assertEqual(block["rows"], 1)
        self.assertEqual(block["total_rows"], 2)
        self.assertEqual(self._tool(block, "mcp:signoz")["uses"], 1)

    # ── CLI ──────────────────────────────────────────────────────────────────

    def _run_cli(self, *argv, stdin: str):
        return subprocess.run(
            [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tool_grades.py"), *argv],
            input=stdin,
            capture_output=True,
            text=True,
        )

    def test_cli_attaches_tool_grades_and_preserves_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_csv(
                os.path.join(tmp, "g.csv"),
                HEADER,
                [row(notes="signoz: flaky.\n", grades={"mcp:signoz": 2})],
            )
            proc = self._run_cli(
                "--csv", path, "--scope", "all", stdin='{"schema": 1, "harness": "opencode"}'
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        merged = json.loads(proc.stdout)
        self.assertEqual(merged["harness"], "opencode")
        self.assertEqual(merged["tool_grades"]["tools"][0]["name"], "signoz")

    def test_cli_passes_through_when_csv_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            proc = self._run_cli(
                "--csv", os.path.join(tmp, "nope.csv"), "--scope", "all", stdin='{"schema": 1}'
            )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout), {"schema": 1})


if __name__ == "__main__":
    unittest.main()
