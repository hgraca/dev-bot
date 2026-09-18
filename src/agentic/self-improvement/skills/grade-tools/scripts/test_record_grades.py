#!/usr/bin/env python3
"""Unit tests for record-grades.py.

Covers the CSV contract the grade-tools skill relies on: canonical column
order, session-scoped -NN ids, column union with 0 backfill, notes quoting,
grade validation, and session-id resolution.

Usage:
    python3 -m unittest test_record_grades.py -v
"""

import contextlib
import csv
import importlib.util
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_MODULE_PATH = Path(__file__).resolve().parent / "record-grades.py"
_spec = importlib.util.spec_from_file_location("record_grades", _MODULE_PATH)
assert _spec is not None and _spec.loader is not None, f"cannot load {_MODULE_PATH}"
record_grades = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(record_grades)

NOW = "2026-01-02 03:04:05"


class RecordGradesTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = self._tmp.name
        os.makedirs(os.path.join(self.root, ".agents"))
        self.csv_path = os.path.join(self.root, ".agents", "logs", "tools-grades.csv")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_main(self, *args: str, session: str = "ses_test", now: str = NOW) -> int:
        return record_grades.main(
            ["--project-root", self.root, "--now", now, "--session-id", session, *args]
        )

    def read_rows(self) -> list[list[str]]:
        with open(self.csv_path, newline="", encoding="utf-8") as fh:
            return list(csv.reader(fh))

    # ── file creation and row identity ───────────────────────────────────────

    def test_fresh_run_creates_header_and_first_row(self) -> None:
        self.run_main("--notes", "fine", "--mcp", "graphify=2", "--skill", "git-report=4")

        header, first = self.read_rows()
        self.assertEqual(
            header, ["session_id", "datetime", "notes", "mcp:graphify", "skill:git-report"]
        )
        self.assertEqual(first, ["ses_test-01", NOW, "fine", "2", "4"])

    def test_second_run_in_same_session_increments_the_suffix(self) -> None:
        self.run_main("--skill", "git-report=3")
        self.run_main("--skill", "git-report=3")

        rows = self.read_rows()
        self.assertEqual(rows[1][0], "ses_test-01")
        self.assertEqual(rows[2][0], "ses_test-02")

    def test_a_different_session_starts_its_own_sequence(self) -> None:
        self.run_main("--skill", "git-report=3")
        self.run_main("--skill", "git-report=3", session="ses_other")

        rows = self.read_rows()
        self.assertEqual(rows[1][0], "ses_test-01")
        self.assertEqual(rows[2][0], "ses_other-01")

    def test_suffix_only_matches_its_own_session_prefix(self) -> None:
        # ses_a must not consume ses_a2's counter.
        self.run_main("--notes", "", session="ses_a2")
        self.run_main("--notes", "", session="ses_a")

        rows = self.read_rows()
        self.assertEqual(rows[1][0], "ses_a2-01")
        self.assertEqual(rows[2][0], "ses_a-01")

    # ── column union and canonical order ─────────────────────────────────────

    def test_new_tool_column_backfills_prior_rows_with_zero(self) -> None:
        self.run_main("--skill", "git-report=5")
        self.run_main("--mcp", "graphify=1")

        header, first, second = self.read_rows()
        self.assertEqual(header, ["session_id", "datetime", "notes", "mcp:graphify", "skill:git-report"])
        self.assertEqual(first[3:], ["0", "5"])  # graphify column backfilled
        self.assertEqual(second[3:], ["1", "0"])  # git-report untouched by the new row

    def test_columns_are_regrouped_mcp_before_skill(self) -> None:
        # Skill arrives first; MCP must still be ordered before it.
        self.run_main("--skill", "remember-session=2")
        self.run_main("--mcp", "codebase-memory=3")

        header = self.read_rows()[0]
        self.assertEqual(
            header,
            [
                "session_id",
                "datetime",
                "notes",
                "mcp:codebase-memory",
                "skill:remember-session",
            ],
        )

    def test_devbot_tools_get_one_column_per_tool(self) -> None:
        self.run_main("--mcp-tool", "search-memories=5", "--mcp-tool", "git-report=1")

        header = self.read_rows()[0]
        self.assertEqual(
            header,
            [
                "session_id",
                "datetime",
                "notes",
                "mcp:devbot-tools:git-report",
                "mcp:devbot-tools:search-memories",
            ],
        )

    def test_unused_tool_without_a_column_is_not_materialised(self) -> None:
        self.run_main("--mcp", "graphify=0")

        header = self.read_rows()[0]
        self.assertEqual(header, ["session_id", "datetime", "notes"])

    # ── notes ────────────────────────────────────────────────────────────────

    def test_notes_with_separators_round_trip(self) -> None:
        note = 'grade 3: a "substitute", e.g. codebase-memory'
        self.run_main("--notes", note)

        self.assertEqual(self.read_rows()[1][2], note)

    def test_notes_newlines_are_normalised_to_spaces(self) -> None:
        self.run_main("--notes", "line one\nline two")

        self.assertEqual(self.read_rows()[1][2], "line one line two")

    def test_empty_notes_are_allowed(self) -> None:
        self.run_main()

        self.assertEqual(self.read_rows()[1][2], "")

    # ── validation ───────────────────────────────────────────────────────────

    def test_out_of_range_grade_is_rejected(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            self.run_main("--skill", "git-report=6")
        self.assertEqual(ctx.exception.code, 2)

    def test_non_integer_grade_is_rejected(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            self.run_main("--skill", "git-report=high")
        self.assertEqual(ctx.exception.code, 2)

    def test_malformed_pair_is_rejected(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            self.run_main("--skill", "git-report")
        self.assertEqual(ctx.exception.code, 2)

    def test_grading_devbot_tools_as_a_server_is_rejected(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            self.run_main("--mcp", "devbot-tools=5")
        self.assertEqual(ctx.exception.code, 2)

    def test_duplicate_tool_is_rejected(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            self.run_main("--skill", "git-report=1", "--skill", "git-report=2")
        self.assertEqual(ctx.exception.code, 2)

    def test_project_without_agents_directory_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as bare:
            with self.assertRaises(SystemExit) as ctx:
                record_grades.main(["--project-root", bare, "--session-id", "s"])
            self.assertEqual(ctx.exception.code, 2)

    # ── session id resolution ────────────────────────────────────────────────

    def test_explicit_session_id_wins(self) -> None:
        with patch.dict(os.environ, {"DEVBOT_SESSION_ID": "ses_env"}):
            self.assertEqual(record_grades.resolve_session_id("ses_explicit"), "ses_explicit")

    def test_env_session_id_is_used(self) -> None:
        with patch.dict(os.environ, {"DEVBOT_SESSION_ID": "ses_env"}):
            self.assertEqual(record_grades.resolve_session_id(None), "ses_env")

    def test_missing_session_id_falls_back_with_a_warning(self) -> None:
        env = {k: v for k, v in os.environ.items() if k != "DEVBOT_SESSION_ID"}
        stderr = io.StringIO()
        with patch.dict(os.environ, env, clear=True), contextlib.redirect_stderr(stderr):
            resolved = record_grades.resolve_session_id(None)

        self.assertEqual(resolved, "unknown")
        self.assertIn("WARN:", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
