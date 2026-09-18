#!/usr/bin/env python3
"""Unit tests for record-grades.py.

Covers the CSV contract the grade-tools skill relies on: canonical column
order, session-scoped -NN ids, column union with 0 backfill, notes quoting and
line-break preservation, grade validation, the rule that a 1-3 grade must be
explained in the notes, devbot-root resolution, and session-id resolution.

Usage:
    python3 -m unittest test_record_grades.py -v
"""

import contextlib
import csv
import importlib.util
import io
import os
import stat
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
        self.csv_path = os.path.join(self.root, "storage", "logs", "tools-grades.csv")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_main(self, *args: str, session: str = "ses_test", now: str = NOW) -> int:
        return record_grades.main(
            ["--devbot-root", self.root, "--now", now, "--session-id", session, *args]
        )

    def read_rows(self) -> list[list[str]]:
        with open(self.csv_path, newline="", encoding="utf-8") as fh:
            return list(csv.reader(fh))

    # ── file creation and row identity ───────────────────────────────────────

    def test_csv_lives_under_the_devbot_root_not_the_calling_project(self) -> None:
        self.run_main("--skill", "git-report=5")

        self.assertTrue(os.path.isfile(self.csv_path), self.csv_path)
        self.assertEqual(
            os.path.relpath(self.csv_path, self.root),
            os.path.join("storage", "logs", "tools-grades.csv"),
        )
        # The calling project must not be where the row lands any more.
        self.assertFalse(os.path.exists(os.path.join(self.root, ".agents", "logs")))

    def test_fresh_run_creates_header_and_first_row(self) -> None:
        self.run_main(
            "--notes", "graphify: marginal, grep covered it",
            "--mcp", "graphify=2",
            "--skill", "git-report=4",
        )

        header, first = self.read_rows()
        self.assertEqual(
            header, ["session_id", "datetime", "notes", "mcp:graphify", "skill:git-report"]
        )
        self.assertEqual(
            first, ["ses_test-01", NOW, "graphify: marginal, grep covered it", "2", "4"]
        )

    def test_second_run_in_same_session_increments_the_suffix(self) -> None:
        self.run_main("--notes", "git-report: glob substituted", "--skill", "git-report=3")
        self.run_main("--notes", "git-report: glob substituted", "--skill", "git-report=3")

        rows = self.read_rows()
        self.assertEqual(rows[1][0], "ses_test-01")
        self.assertEqual(rows[2][0], "ses_test-02")

    def test_a_different_session_starts_its_own_sequence(self) -> None:
        self.run_main("--notes", "git-report: glob substituted", "--skill", "git-report=3")
        self.run_main(
            "--notes", "git-report: glob substituted", "--skill", "git-report=3",
            session="ses_other",
        )

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
        self.run_main("--notes", "graphify: marginal here", "--mcp", "graphify=1")

        header, first, second = self.read_rows()
        self.assertEqual(header, ["session_id", "datetime", "notes", "mcp:graphify", "skill:git-report"])
        self.assertEqual(first[3:], ["0", "5"])  # graphify column backfilled
        self.assertEqual(second[3:], ["1", "0"])  # git-report untouched by the new row

    def test_columns_are_regrouped_mcp_before_skill(self) -> None:
        # Skill arrives first; MCP must still be ordered before it.
        self.run_main(
            "--notes", "remember-session: redundant here",
            "--skill", "remember-session=2",
        )
        self.run_main(
            "--notes", "codebase-memory: grep substituted",
            "--mcp", "codebase-memory=3",
        )

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
        self.run_main(
            "--notes", "git-report: marginal here",
            "--mcp-tool", "search-memories=5",
            "--mcp-tool", "git-report=1",
        )

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

    # ── notes: quoting and line breaks ───────────────────────────────────────

    def test_notes_with_separators_round_trip(self) -> None:
        note = 'grade 3: a "substitute", e.g. codebase-memory'
        self.run_main("--notes", note)

        self.assertEqual(self.read_rows()[1][2], note)

    def test_notes_keep_their_line_breaks(self) -> None:
        self.run_main("--notes", "line one\nline two\nline three")

        self.assertEqual(self.read_rows()[1][2], "line one\nline two\nline three")

    def test_notes_line_breaks_survive_a_second_append(self) -> None:
        self.run_main("--notes", "first\nsecond")
        self.run_main("--notes", "third")

        rows = self.read_rows()
        self.assertEqual(rows[1][2], "first\nsecond")
        self.assertEqual(rows[2][2], "third")

    def test_notes_trailing_whitespace_and_blank_edges_are_trimmed(self) -> None:
        self.run_main("--notes", "\nline one   \nline two\t\n\n")

        self.assertEqual(self.read_rows()[1][2], "line one\nline two")

    def test_notes_carriage_returns_are_normalised_to_line_feeds(self) -> None:
        self.run_main("--notes", "line one\r\nline two\rline three")

        self.assertEqual(self.read_rows()[1][2], "line one\nline two\nline three")

    def test_empty_notes_are_allowed(self) -> None:
        self.run_main()

        self.assertEqual(self.read_rows()[1][2], "")

    # ── a 1-3 grade must be explained in the notes ───────────────────────────

    def test_grade_1_without_naming_the_tool_is_rejected(self) -> None:
        stderr = io.StringIO()
        with self.assertRaises(SystemExit) as ctx, contextlib.redirect_stderr(stderr):
            self.run_main("--notes", "nothing to say", "--mcp", "graphify=1")

        self.assertEqual(ctx.exception.code, 2)
        self.assertIn("graphify", stderr.getvalue())

    def test_grade_2_without_naming_the_tool_is_rejected(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            self.run_main("--notes", "nothing to say", "--skill", "git-report=2")
        self.assertEqual(ctx.exception.code, 2)

    def test_grade_3_without_naming_the_tool_is_rejected(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            self.run_main("--notes", "nothing to say", "--skill", "git-report=3")
        self.assertEqual(ctx.exception.code, 2)

    def test_every_1_3_grade_in_a_multi_tool_row_must_be_named(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            self.run_main(
                "--notes", "graphify: marginal here",
                "--mcp", "graphify=2",
                "--skill", "git-report=3",
            )
        self.assertEqual(ctx.exception.code, 2)

    def test_naming_the_short_name_of_a_devbot_tool_is_enough(self) -> None:
        self.run_main(
            "--notes", "format-md: prettier unavailable in the container",
            "--mcp-tool", "format-md=2",
        )

        self.assertEqual(self.read_rows()[1][3], "2")

    def test_naming_a_namespaced_skill_by_its_last_segment_is_enough(self) -> None:
        self.run_main(
            "--notes", "makefile: raw docker exec substituted",
            "--skill", "devbot:makefile=3",
        )

        self.assertEqual(self.read_rows()[1][3], "3")

    def test_grade_explanation_matching_is_case_insensitive(self) -> None:
        self.run_main("--notes", "Graphify: marginal here", "--mcp", "graphify=2")

        self.assertEqual(self.read_rows()[1][3], "2")

    def test_grades_0_4_and_5_need_no_explanation(self) -> None:
        self.run_main(
            "--notes", "",
            "--mcp", "graphify=0",
            "--mcp", "codebase-memory=4",
            "--skill", "git-report=5",
        )

        self.assertEqual(self.read_rows()[1][2], "")

    # ── file permissions ─────────────────────────────────────────────────────

    def test_new_csv_permissions_follow_umask_not_mkstemp(self) -> None:
        self.run_main("--notes", "git-report: marginal", "--skill", "git-report=1")

        umask = os.umask(0)
        os.umask(umask)
        mode = stat.S_IMODE(os.stat(self.csv_path).st_mode)
        self.assertEqual(mode, 0o644 & ~umask)

    def test_existing_file_permissions_are_preserved(self) -> None:
        os.makedirs(os.path.dirname(self.csv_path), exist_ok=True)
        with open(self.csv_path, "w", encoding="utf-8") as fh:
            fh.write("session_id,datetime,notes\n")
        os.chmod(self.csv_path, 0o640)

        self.run_main("--notes", "git-report: marginal", "--skill", "git-report=1")

        self.assertEqual(stat.S_IMODE(os.stat(self.csv_path).st_mode), 0o640)

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

    # ── devbot root resolution ───────────────────────────────────────────────

    def test_explicit_root_wins_over_the_environment(self) -> None:
        resolved = record_grades.resolve_devbot_root(
            "/explicit/root", {"DEV_BOT_ROOT": "/env/root"}, _MODULE_PATH
        )

        self.assertEqual(resolved, "/explicit/root")

    def test_environment_root_is_used_when_no_flag_is_given(self) -> None:
        resolved = record_grades.resolve_devbot_root(
            None, {"DEV_BOT_ROOT": "/env/root"}, _MODULE_PATH
        )

        self.assertEqual(resolved, "/env/root")

    def test_blank_environment_root_falls_through_to_the_walk_up(self) -> None:
        with tempfile.TemporaryDirectory() as install:
            os.makedirs(os.path.join(install, "src", "agentic", "self-improvement"))
            script = os.path.join(install, "src", "agentic", "self-improvement", "record-grades.py")

            resolved = record_grades.resolve_devbot_root(
                None, {"DEV_BOT_ROOT": "   "}, Path(script)
            )

            # realpath both sides: the walk-up resolves the script path, and a
            # temp dir can itself sit behind a symlink (macOS /tmp).
            self.assertEqual(os.path.realpath(resolved), os.path.realpath(install))

    def test_walk_up_from_the_script_location_finds_the_install_root(self) -> None:
        with tempfile.TemporaryDirectory() as install:
            os.makedirs(os.path.join(install, "src", "agentic"))
            script = os.path.join(install, "src", "agentic", "skills", "grade-tools", "record-grades.py")

            resolved = record_grades.resolve_devbot_root(None, {}, Path(script))

            self.assertEqual(os.path.realpath(resolved), os.path.realpath(install))

    def test_unresolvable_root_is_a_fatal_error(self) -> None:
        with tempfile.TemporaryDirectory() as nowhere:
            stderr = io.StringIO()
            with self.assertRaises(SystemExit) as ctx, contextlib.redirect_stderr(stderr):
                record_grades.resolve_devbot_root(
                    None, {}, Path(nowhere) / "src" / "record-grades.py"
                )

            self.assertEqual(ctx.exception.code, 3)
            self.assertIn("DEV_BOT_ROOT", stderr.getvalue())

    # ── session id resolution ────────────────────────────────────────────────

    def test_explicit_session_id_wins(self) -> None:
        with patch.dict(os.environ, {"DEV_BOT_SESSION_ID": "ses_env"}):
            self.assertEqual(record_grades.resolve_session_id("ses_explicit"), "ses_explicit")

    def test_env_session_id_is_used(self) -> None:
        with patch.dict(os.environ, {"DEV_BOT_SESSION_ID": "ses_env"}):
            self.assertEqual(record_grades.resolve_session_id(None), "ses_env")

    def test_missing_session_id_falls_back_with_a_warning(self) -> None:
        env = {k: v for k, v in os.environ.items() if k != "DEV_BOT_SESSION_ID"}
        stderr = io.StringIO()
        with patch.dict(os.environ, env, clear=True), contextlib.redirect_stderr(stderr):
            resolved = record_grades.resolve_session_id(None)

        self.assertEqual(resolved, "unknown")
        self.assertIn("WARN:", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
