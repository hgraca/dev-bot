#!/usr/bin/env python3
"""Unit tests for record-grades.py.

Covers the CSV contract the grade-tools skill relies on: canonical column
order, the project column, session-scoped -NN ids, column union with 0
backfill, notes quoting and line-break preservation, grade validation, the
rule that a 1-3 grade must be explained in the notes, devbot-root resolution,
and session-id resolution.

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

# The reader keeps its own copy of the CSV contract. Loaded here so the two
# copies can be compared rather than trusted to a source comment.
_SHARED_PATH = Path(__file__).resolve().parents[5] / "_shared" / "tool_grades.py"
_shared_spec = importlib.util.spec_from_file_location("tool_grades_shared", _SHARED_PATH)
assert _shared_spec is not None and _shared_spec.loader is not None, f"cannot load {_SHARED_PATH}"
tool_grades_shared = importlib.util.module_from_spec(_shared_spec)
_shared_spec.loader.exec_module(tool_grades_shared)

NOW = "2026-01-02 03:04:05"
PROJECT = "Get-e/positioning-activities"


class RecordGradesTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = self._tmp.name
        # A project root two levels deep, so the derived name is deterministic.
        self.project_root = os.path.join(self.root, "Get-e", "positioning-activities")
        os.makedirs(self.project_root, exist_ok=True)
        self.csv_path = os.path.join(self.root, ".agents", "logs", "tools-grades.csv")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def run_main(
        self, *args: str, session: str = "ses_test", now: str = NOW, actor: str | None = "DevBot"
    ) -> int:
        argv = [
            "--devbot-root", self.root,
            "--project-root", self.project_root,
            "--now", now,
            "--session-id", session,
            *args,
        ]
        # Most tests do not care who wrote the row, so pin it rather than let
        # them depend on the ambient DEV_BOT_AGENT_NAME (or trip its WARN). Pass
        # actor=None to exercise the env-var fallback instead.
        if actor is not None:
            argv += ["--actor", actor]
        return record_grades.main(argv)

    def read_rows(self) -> list[list[str]]:
        with open(self.csv_path, newline="", encoding="utf-8") as fh:
            return list(csv.reader(fh))

    # ── file creation and row identity ───────────────────────────────────────

    def test_csv_lives_under_the_devbot_root_not_the_calling_project(self) -> None:
        self.run_main("--skill", "git-report=5")

        self.assertTrue(os.path.isfile(self.csv_path), self.csv_path)
        self.assertEqual(
            os.path.relpath(self.csv_path, self.root),
            os.path.join(".agents", "logs", "tools-grades.csv"),
        )
        # The calling project must not be where the row lands any more.
        self.assertFalse(os.path.exists(os.path.join(self.project_root, ".agents")))

    def test_column_order_puts_the_project_after_the_datetime(self) -> None:
        self.run_main("--notes", "graphify: marginal here", "--mcp", "graphify=2")

        header = self.read_rows()[0]
        self.assertEqual(header[:4], ["session_id", "datetime", "project", "notes"])
        self.assertEqual(header[5:], ["mcp:graphify"])

    def test_fresh_run_creates_header_and_first_row(self) -> None:
        self.run_main(
            "--notes", "graphify: marginal, grep covered it",
            "--mcp", "graphify=2",
            "--skill", "git-report=4",
        )

        header, first = self.read_rows()
        self.assertEqual(
            header,
            ["session_id", "datetime", "project", "notes", "actor", "mcp:graphify", "skill:git-report"],
        )
        self.assertEqual(
            first,
            ["ses_test-01", NOW, PROJECT, "graphify: marginal, grep covered it", "DevBot", "2", "4"],
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

    # ── the actor column ─────────────────────────────────────────────────────

    def test_actor_is_appended_to_the_base_columns(self) -> None:
        self.assertEqual(
            record_grades.BASE_COLUMNS,
            ["session_id", "datetime", "project", "notes", "actor"],
        )

    def test_actor_comes_from_the_flag(self) -> None:
        self.run_main("--notes", "", actor="scout")
        self.assertEqual(self.read_rows()[1][4], "scout")

    def test_actor_falls_back_to_the_env_var(self) -> None:
        with patch.dict(os.environ, {"DEV_BOT_AGENT_NAME": "developer"}):
            self.run_main("--notes", "", actor=None)
        self.assertEqual(self.read_rows()[1][4], "developer")

    def test_actor_flag_wins_over_the_env_var(self) -> None:
        with patch.dict(os.environ, {"DEV_BOT_AGENT_NAME": "developer"}):
            self.run_main("--notes", "", actor="reviewer")
        self.assertEqual(self.read_rows()[1][4], "reviewer")

    def test_actor_warns_and_uses_unknown_when_unset(self) -> None:
        stderr = io.StringIO()
        with patch.dict(os.environ, {}, clear=True), contextlib.redirect_stderr(stderr):
            self.run_main("--notes", "", actor=None)

        self.assertEqual(self.read_rows()[1][4], "unknown")
        self.assertIn("DEV_BOT_AGENT_NAME", stderr.getvalue())

    def test_blank_actor_never_reaches_the_csv(self) -> None:
        # A blank cell reads as "written before the column existed", so writing
        # one now would get the row backfilled and mislabelled later.
        with patch.dict(os.environ, {}, clear=True):
            self.run_main("--notes", "", actor="   ")
        self.assertEqual(self.read_rows()[1][4], "unknown")

    def test_blank_actor_falls_through_to_the_env_var(self) -> None:
        with patch.dict(os.environ, {"DEV_BOT_AGENT_NAME": "architect"}):
            self.run_main("--notes", "", actor="")
        self.assertEqual(self.read_rows()[1][4], "architect")

    def test_a_row_written_before_the_actor_column_is_backfilled_with_devbot(self) -> None:
        os.makedirs(os.path.dirname(self.csv_path), exist_ok=True)
        with open(self.csv_path, "w", newline="", encoding="utf-8") as fh:
            fh.write("session_id,datetime,project,notes,skill:git-report\n")
            fh.write(f"ses_old-01,{NOW},{PROJECT},legacy row,4\n")

        # A pre-column row cannot say who wrote it — and every one of them came
        # from the primary agent, so that is what it is stamped.
        self.run_main("--notes", "", actor="scout")

        rows = self.read_rows()
        self.assertEqual(rows[0][4], "actor")
        self.assertEqual(rows[1][4], "DevBot")
        self.assertEqual(rows[2][4], "scout")

    def test_a_named_actor_is_never_rewritten(self) -> None:
        os.makedirs(os.path.dirname(self.csv_path), exist_ok=True)
        with open(self.csv_path, "w", newline="", encoding="utf-8") as fh:
            fh.write("session_id,datetime,project,notes,actor,skill:git-report\n")
            fh.write(f"ses_old-01,{NOW},{PROJECT},already named,devbot,4\n")

        self.run_main("--notes", "", actor="scout")

        self.assertEqual(self.read_rows()[1][4], "devbot")

    def test_a_blank_actor_on_a_matrix_that_has_the_column_is_left_blank(self) -> None:
        # The backfill is a one-time migration keyed on the header, not a rule
        # about empty cells. Once the column exists, a blank actor means "not
        # known" — stamping it DevBot would mislabel whoever actually wrote it.
        os.makedirs(os.path.dirname(self.csv_path), exist_ok=True)
        with open(self.csv_path, "w", newline="", encoding="utf-8") as fh:
            fh.write("session_id,datetime,project,notes,actor,skill:git-report\n")
            fh.write(f"ses_old-01,{NOW},{PROJECT},unnamed row,,4\n")

        self.run_main("--notes", "", actor="scout")

        self.assertEqual(self.read_rows()[1][4], "")

    # ── the project column ───────────────────────────────────────────────────

    def test_project_name_is_the_project_parent_folder_and_folder(self) -> None:
        self.assertEqual(
            record_grades.project_name("/home/herberto/Development/Get-e/positioning-activities"),
            PROJECT,
        )

    def test_project_name_handles_a_single_segment_path(self) -> None:
        self.assertEqual(record_grades.project_name("/solo"), "solo")

    def test_project_root_defaults_to_the_current_directory(self) -> None:
        with patch("os.getcwd", return_value=self.project_root):
            record_grades.main(
                ["--devbot-root", self.root, "--now", NOW, "--session-id", "ses_cwd",
                 "--actor", "DevBot", "--skill", "git-report=5"]
            )

        self.assertEqual(self.read_rows()[1][2], PROJECT)

    def test_explicit_project_root_wins_over_the_current_directory(self) -> None:
        with patch("os.getcwd", return_value="/somewhere/else/entirely"):
            self.run_main("--skill", "git-report=5")

        self.assertEqual(self.read_rows()[1][2], PROJECT)

    def test_rows_written_without_the_project_column_keep_an_empty_value(self) -> None:
        os.makedirs(os.path.dirname(self.csv_path), exist_ok=True)
        with open(self.csv_path, "w", newline="", encoding="utf-8") as fh:
            fh.write("session_id,datetime,notes,skill:git-report\nlegacy-01,2026-01-01 00:00:00,old,3\n")

        self.run_main("--skill", "git-report=5")

        header, legacy, fresh = self.read_rows()
        self.assertEqual(header[:4], ["session_id", "datetime", "project", "notes"])
        self.assertEqual(legacy[2], "")  # the script cannot invent a project
        self.assertEqual(fresh[2], PROJECT)

    # ── column union and canonical order ─────────────────────────────────────

    def test_new_tool_column_backfills_prior_rows_with_zero(self) -> None:
        self.run_main("--skill", "git-report=5")
        self.run_main("--notes", "graphify: marginal here", "--mcp", "graphify=1")

        header, first, second = self.read_rows()
        self.assertEqual(
            header,
            ["session_id", "datetime", "project", "notes", "actor", "mcp:graphify", "skill:git-report"],
        )
        self.assertEqual(first[5:], ["0", "5"])  # graphify column backfilled
        self.assertEqual(second[5:], ["1", "0"])  # git-report untouched by the new row

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
                "project",
                "notes",
                "actor",
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
                "project",
                "notes",
                "actor",
                "mcp:devbot-tools:git-report",
                "mcp:devbot-tools:search-memories",
            ],
        )

    def test_unused_tool_without_a_column_is_not_materialised(self) -> None:
        self.run_main("--mcp", "graphify=0")

        header = self.read_rows()[0]
        self.assertEqual(header, ["session_id", "datetime", "project", "notes", "actor"])

    # ── notes: quoting and line breaks ───────────────────────────────────────

    def test_notes_with_separators_round_trip(self) -> None:
        note = 'grade 3: a "substitute", e.g. codebase-memory'
        self.run_main("--notes", note)

        self.assertEqual(self.read_rows()[1][3], note)

    def test_notes_keep_their_line_breaks(self) -> None:
        self.run_main("--notes", "line one\nline two\nline three")

        self.assertEqual(self.read_rows()[1][3], "line one\nline two\nline three")

    def test_notes_line_breaks_survive_a_second_append(self) -> None:
        self.run_main("--notes", "first\nsecond")
        self.run_main("--notes", "third")

        rows = self.read_rows()
        self.assertEqual(rows[1][3], "first\nsecond")
        self.assertEqual(rows[2][3], "third")

    def test_notes_trailing_whitespace_and_blank_edges_are_trimmed(self) -> None:
        self.run_main("--notes", "\nline one   \nline two\t\n\n")

        self.assertEqual(self.read_rows()[1][3], "line one\nline two")

    def test_notes_carriage_returns_are_normalised_to_line_feeds(self) -> None:
        self.run_main("--notes", "line one\r\nline two\rline three")

        self.assertEqual(self.read_rows()[1][3], "line one\nline two\nline three")

    def test_empty_notes_are_allowed(self) -> None:
        self.run_main()

        self.assertEqual(self.read_rows()[1][3], "")

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

        self.assertEqual(self.read_rows()[1][5], "2")

    def test_naming_a_namespaced_skill_by_its_last_segment_is_enough(self) -> None:
        self.run_main(
            "--notes", "makefile: raw docker exec substituted",
            "--skill", "devbot:makefile=3",
        )

        self.assertEqual(self.read_rows()[1][5], "3")

    def test_grade_explanation_matching_is_case_insensitive(self) -> None:
        self.run_main("--notes", "Graphify: marginal here", "--mcp", "graphify=2")

        self.assertEqual(self.read_rows()[1][5], "2")

    def test_grades_0_4_and_5_need_no_explanation(self) -> None:
        self.run_main(
            "--notes", "",
            "--mcp", "graphify=0",
            "--mcp", "codebase-memory=4",
            "--skill", "git-report=5",
        )

        self.assertEqual(self.read_rows()[1][3], "")

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

    # ── the shared CSV contract ──────────────────────────────────────────────

    def test_the_reader_agrees_on_the_csv_contract(self) -> None:
        # tool_grades.py holds its own copy of the column order and the timestamp
        # format, kept in sync by a source comment alone. A drift between the two
        # would silently mis-read the matrix, so compare them instead of trusting
        # the comment.
        self.assertEqual(list(tool_grades_shared.BASE_COLUMNS), record_grades.BASE_COLUMNS)
        self.assertEqual(tool_grades_shared.DATETIME_FORMAT, record_grades.DATETIME_FORMAT)


if __name__ == "__main__":
    unittest.main()
