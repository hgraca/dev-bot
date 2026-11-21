#!/usr/bin/env python3
"""Unit tests for mine-commands.py.

Covers the parts whose failure is silent: the tokeniser (quote-aware splitting,
subshell blanking, pipeline handling, heredoc and loop collapse), run splitting
at tool boundaries, support counting, redundancy pruning, and the session
selection rule — v2 roots first, legacy table topping up the shortfall.

Usage:
    python3 -m unittest test_mine_commands.py -v
"""

import importlib.util
import sqlite3
import unittest
from pathlib import Path

_MODULE_PATH = Path(__file__).resolve().parent / "mine-commands.py"
_spec = importlib.util.spec_from_file_location("mine_commands", _MODULE_PATH)
mine = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mine)


class SplitCommandsTest(unittest.TestCase):
    def test_splits_on_operators(self):
        self.assertEqual(
            mine.split_commands("git add x && git commit -m 'a' ; git log"),
            ["git add x ", " git commit -m 'a' ", " git log"],
        )

    def test_ignores_operators_inside_quotes(self):
        command = "python3 -c \"import sys; print(1)\" && echo ok"
        self.assertEqual(len(mine.split_commands(command)), 2)


class StripSubshellsTest(unittest.TestCase):
    def test_removes_nested_parens(self):
        stripped = mine.strip_subshells("since=\"$(gh api x --jq 'select(.a == 1)')\"")
        self.assertIn("<sub>", stripped)
        self.assertNotIn("gh api", stripped)

    def test_removes_backticks(self):
        self.assertEqual(mine.strip_subshells("echo `date` x"), "echo <sub> x")


class ShellSymbolsTest(unittest.TestCase):
    def test_drops_cd_and_echo_noise(self):
        self.assertEqual(mine.shell_symbols("cd /repo && git status --porcelain"), ["git status"])

    def test_pipeline_tail_is_not_a_second_symbol(self):
        self.assertEqual(mine.shell_symbols("gh api repos/x --jq .state | head -3"), ["gh api"])

    def test_heredoc_is_one_symbol(self):
        self.assertEqual(mine.shell_symbols("cat > f.md <<'EOF'\n; api and prose\nEOF"), ["heredoc"])

    def test_control_structure_is_one_symbol(self):
        self.assertEqual(mine.shell_symbols("for f in a b; do echo $f; done"), ["loop"])

    def test_flag_value_is_not_a_verb(self):
        self.assertEqual(mine.shell_symbols("kubectl -n transfers get pods"), ["kubectl get pods"])

    def test_subshell_content_never_becomes_a_program(self):
        symbols = mine.shell_symbols('x="$(npm root -g)" && npx bats x.bats')
        self.assertNotIn("root", symbols)

    def test_assignment_only_command_yields_nothing(self):
        self.assertEqual(mine.shell_symbols("W=/tmp/x"), [])


class RunRecordsTest(unittest.TestCase):
    def test_a_tool_call_ends_the_run(self):
        records = [("git status", 10), ("edit", 5), ("git diff", 8)]
        runs = mine.run_records(records, {"edit"})
        self.assertEqual([[s for s, _ in run] for run in runs], [["git status"], ["git diff"]])

    def test_raw_chars_survive_the_split(self):
        records = [("git status", 10), ("read", 4), ("git diff", 8)]
        runs = mine.run_records(records, {"read"})
        self.assertEqual([raw for run in runs for _, raw in run], [10, 8])


class MineTest(unittest.TestCase):
    def test_support_counts_sessions_not_runs(self):
        runsets = {"a": [["x", "y"], ["x", "y"]], "b": [["x", "y"]]}
        grams = mine.mine(runsets, 2, 2)
        self.assertEqual(grams[("x", "y")][0], 3)  # occurrences
        self.assertEqual(len(grams[("x", "y")][1]), 2)  # sessions

    def test_prune_drops_a_covered_subgram(self):
        runsets = {"a": [["x", "y", "z"]], "b": [["x", "y", "z"]], "c": [["x", "y", "z"]]}
        pruned = mine.prune(mine.mine(runsets, 2, 3), 3)
        self.assertIn(("x", "y", "z"), pruned)
        self.assertNotIn(("x", "y"), pruned)

    def test_prune_keeps_a_subgram_that_also_stands_alone(self):
        runsets = {
            "a": [["x", "y", "z"]],
            "b": [["x", "y", "z"]],
            "c": [["x", "y"]],
            "d": [["x", "y"]],
        }
        pruned = mine.prune(mine.mine(runsets, 2, 3), 2)
        self.assertIn(("x", "y"), pruned)


def session_row(sid, parent, created, src):
    return {
        "id": sid,
        "parent": parent,
        "title": sid,
        "directory": "/tmp",
        "created": created,
        "src": src,
    }


class SelectRootsTest(unittest.TestCase):
    def test_v2_first_and_complete_means_no_v1(self):
        by_id = {row["id"]: row for row in [
            session_row("v2a", None, 300, "v2"),
            session_row("v2b", None, 200, "v2"),
            session_row("v1a", None, 400, "v1"),
        ]}
        selected = mine.select_roots(by_id, 2)
        self.assertEqual([row["id"] for row in selected], ["v2a", "v2b"])

    def test_legacy_tops_up_the_shortfall_newest_first(self):
        by_id = {row["id"]: row for row in [
            session_row("v2a", None, 300, "v2"),
            session_row("v1a", None, 400, "v1"),
            session_row("v1b", None, 100, "v1"),
        ]}
        selected = mine.select_roots(by_id, 2)
        self.assertEqual([row["id"] for row in selected], ["v2a", "v1a"])

    def test_children_are_never_selected_as_roots(self):
        by_id = {row["id"]: row for row in [
            session_row("root", None, 100, "v2"),
            session_row("child", "root", 200, "v2"),
        ]}
        self.assertEqual([row["id"] for row in mine.select_roots(by_id, 10)], ["root"])


class LoadSessionsTest(unittest.TestCase):
    """A migrated 1.x session is in both tables; the v2 row must win."""

    def setUp(self):
        self.con = sqlite3.connect(":memory:")
        self.con.execute(
            "create table session (id text, parent_id text, title text, directory text, time_created integer)"
        )
        self.con.execute(
            "create table session_v2 (id text, parent_id text, title text, directory text, time_created integer)"
        )

    def tearDown(self):
        self.con.close()

    def test_v2_row_wins_for_a_shared_id(self):
        self.con.execute("insert into session values ('ses_x', null, 'old', '/tmp', 1)")
        self.con.execute("insert into session_v2 values ('ses_x', null, 'new', '/tmp', 1)")
        by_id = mine.load_sessions(self.con)
        self.assertEqual(by_id["ses_x"]["src"], "v2")
        self.assertEqual(by_id["ses_x"]["title"], "new")

    def test_legacy_only_session_is_kept(self):
        self.con.execute("insert into session values ('ses_y', null, 'legacy', '/tmp', 1)")
        by_id = mine.load_sessions(self.con)
        self.assertEqual(by_id["ses_y"]["src"], "v1")


if __name__ == "__main__":
    unittest.main()
