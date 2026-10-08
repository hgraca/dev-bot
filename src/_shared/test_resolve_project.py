#!/usr/bin/env python3
"""Unit tests for resolve_project.py."""

import io
import json
import os
import sys
import tempfile
import unittest
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


if __name__ == "__main__":
    unittest.main()
