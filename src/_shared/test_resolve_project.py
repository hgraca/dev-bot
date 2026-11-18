#!/usr/bin/env python3
"""Unit tests for resolve_project.py."""

import io
import json
import os
import sys
import tempfile
import unittest
import contextlib  # noqa: E402
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import resolve_project  # noqa: E402


class ResolveProjectTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = os.path.realpath(self.tmp.name)
        self.a = os.path.join(self.base, "a")
        self.b = os.path.join(self.base, "ab")
        self.nested = os.path.join(self.a, "service")
        for d in (self.a, self.b, self.nested):
            os.makedirs(d, exist_ok=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_exact_match(self):
        self.assertEqual(resolve_project.resolve_project(self.a, [self.a]), self.a)

    def test_child_path_matches_project(self):
        path = os.path.join(self.a, "src", "main.py")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.assertEqual(resolve_project.resolve_project(path, [self.a]), self.a)

    def test_longest_prefix_wins(self):
        path = os.path.join(self.nested, "file.py")
        result = resolve_project.resolve_project(path, [self.a, self.nested])
        self.assertEqual(result, self.nested)

    def test_component_boundary_no_false_match(self):
        # /ab must not match a file under /a (a naive startswith would).
        self.assertEqual(resolve_project.resolve_project(self.b, [self.a]), "")

    def test_no_match_returns_empty(self):
        self.assertEqual(resolve_project.resolve_project(self.b, [self.a]), "")

    def test_ignores_non_string_entries(self):
        self.assertEqual(resolve_project.resolve_project(self.a, [None, 42, self.a]), self.a)

    def test_load_projects_missing_config(self):
        self.assertEqual(resolve_project.load_projects(os.path.join(self.base, "nope.jsonc")), [])

    def test_load_projects_non_list(self):
        cfg = os.path.join(self.base, "cfg.jsonc")
        with open(cfg, "w") as f:
            f.write('{"projects": "oops"}')
        self.assertEqual(resolve_project.load_projects(cfg), [])

    def _write_config(self, projects):
        cfg = os.path.join(self.base, "global.jsonc")
        with open(cfg, "w") as f:
            f.write(json.dumps({"projects": projects}))
        return cfg

    def _run_main(self, argv):
        buf = io.StringIO()
        with redirect_stdout(buf):
            resolve_project.main(argv)
        return buf.getvalue().strip()

    def test_main_prints_match(self):
        cfg = self._write_config([self.a, self.nested])
        path = os.path.join(self.nested, "x.py")
        self.assertEqual(self._run_main([path, "--config", cfg]), self.nested)

    def test_main_prints_default_when_no_match(self):
        cfg = self._write_config([self.a])
        self.assertEqual(
            self._run_main([self.b, "--config", cfg, "--default", self.b]), self.b
        )

    def test_main_prints_empty_when_no_match_no_default(self):
        cfg = self._write_config([self.a])
        self.assertEqual(self._run_main([self.b, "--config", cfg]), "")

    def test_main_fails_open_on_missing_config(self):
        missing = os.path.join(self.base, "missing.jsonc")
        self.assertEqual(
            self._run_main([self.a, "--config", missing, "--default", self.a]), self.a
        )


class ResolveSettingTest(unittest.TestCase):
    """The one implementation of project-first → global → default.

    The rule used to be copied into several readers (the bash getters,
    project-for-path, project-memory, search-memories). These pin the
    behaviours those callers depend on, so a change here cannot silently
    change what the shell reads.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = os.path.realpath(self.tmp.name)
        self.project = os.path.join(self.base, "project")
        os.makedirs(self.project, exist_ok=True)
        self.project_config = os.path.join(self.project, ".devbot.project.jsonc")
        self.global_config = os.path.join(self.base, "global.jsonc")

    def tearDown(self):
        self.tmp.cleanup()

    def _write(self, path, body):
        with open(path, "w", encoding="utf-8") as f:
            f.write(body)

    def test_project_value_wins_over_global(self):
        self._write(self.project_config, '{"devbot_dir": ".state"}')
        self._write(self.global_config, '{"devbot_dir": ".agents"}')
        self.assertEqual(
            resolve_project.resolve_setting(
                self.global_config, self.project, "devbot_dir"
            ),
            ".state",
        )

    def test_empty_project_value_falls_through_to_global(self):
        # Matches the `-z` test the bash getter has always used: an empty string
        # is "not stated", not "stated as empty".
        self._write(self.project_config, '{"devbot_dir": ""}')
        self._write(self.global_config, '{"devbot_dir": ".state"}')
        self.assertEqual(
            resolve_project.resolve_setting(
                self.global_config, self.project, "devbot_dir"
            ),
            ".state",
        )

    def test_explicit_project_false_does_not_fall_through(self):
        # The commit_memory bug: an explicit project `false` must beat a global
        # `true`, so the value comes back as a bool, not as text and not as the
        # global value.
        self._write(self.project_config, '{"commit_memory": false}')
        self._write(self.global_config, '{"commit_memory": true}')
        self.assertIs(
            resolve_project.resolve_setting(
                self.global_config, self.project, "commit_memory"
            ),
            False,
        )

    def test_missing_key_returns_the_default(self):
        self._write(self.project_config, '{"devbot_dir": ".state"}')
        self._write(self.global_config, '{"devbot_dir": ".agents"}')
        self.assertEqual(
            resolve_project.resolve_setting(
                self.global_config, self.project, "harness", "opencode"
            ),
            "opencode",
        )

    def test_missing_configs_return_the_default(self):
        self.assertEqual(
            resolve_project.resolve_setting(
                os.path.join(self.base, "nope.jsonc"), self.project, "x", "d"
            ),
            "d",
        )

    def test_workspace_section_is_read(self):
        self._write(self.project_config, '{"workspace": {"workflow": "trunk"}}')
        self._write(self.global_config, '{"workspace": {"workflow": "worktrees"}}')
        self.assertEqual(
            resolve_project.resolve_setting(
                self.global_config, self.project, "workflow", "", "workspace"
            ),
            "trunk",
        )

    def test_malformed_config_is_reported_and_skipped(self):
        # A parse error must not read as "no value": it goes to stderr (the MCP
        # log) and the global config still answers.
        self._write(self.project_config, "{ not json")
        self._write(self.global_config, '{"devbot_dir": ".state"}')
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            value = resolve_project.resolve_setting(
                self.global_config, self.project, "devbot_dir"
            )
        self.assertEqual(value, ".state")
        self.assertIn("WARNING", stderr.getvalue())

    def test_as_text_matches_the_read_jsonc_encoding(self):
        # _devbot_get_config compares this text in bash (`== "false"`).
        self.assertEqual(resolve_project.as_text("x"), "x")
        self.assertEqual(resolve_project.as_text(False), "false")
        self.assertEqual(resolve_project.as_text(True), "true")
        self.assertEqual(resolve_project.as_text(["a"]), '["a"]')
        self.assertEqual(resolve_project.as_text(None), "")

    def test_cli_setting_mode_prints_the_value(self):
        self._write(self.project_config, '{"devbot_dir": ".state"}')
        buf = io.StringIO()
        with redirect_stdout(buf):
            resolve_project.main(
                [
                    "--setting",
                    "devbot_dir",
                    "--project-root",
                    self.project,
                    "--config",
                    self.global_config,
                ]
            )
        self.assertEqual(buf.getvalue().strip(), ".state")


if __name__ == "__main__":
    unittest.main()
