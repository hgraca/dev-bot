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
