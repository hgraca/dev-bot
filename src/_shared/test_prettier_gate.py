"""Tests for the prettier availability/config gate shared by the format-* tools.

The format-* hooks install into every project dev-bot scaffolds, but prettier is
not every project's formatter. Running it anyway rewrites files to a standard the
project never adopted — and can fight the one it did adopt (a Biome project lost
its intentionally multi-line "files" array that way, and a README gained
semicolons in a JS sample). These tests pin both halves of the gate.
"""

from __future__ import annotations

import json
import os
import shutil
import tempfile
import unittest
from unittest import mock

import prettier_gate
from prettier_gate import has_prettier_config, prettier_available


class PrettierAvailableTest(unittest.TestCase):
    def test_requires_both_node_and_prettier(self) -> None:
        def which_returning(*wanted: str):
            return lambda name: f"/usr/bin/{name}" if name in wanted else None

        with mock.patch.object(prettier_gate.shutil, "which", which_returning("node", "prettier")):
            self.assertTrue(prettier_available())
        with mock.patch.object(prettier_gate.shutil, "which", which_returning("node")):
            self.assertFalse(prettier_available())
        with mock.patch.object(prettier_gate.shutil, "which", which_returning("prettier")):
            self.assertFalse(prettier_available())
        with mock.patch.object(prettier_gate.shutil, "which", which_returning()):
            self.assertFalse(prettier_available())


class HasPrettierConfigTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = tempfile.mkdtemp(prefix="prettier-gate-")

    def tearDown(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)

    def _write(self, name: str, content: str = "") -> str:
        path = os.path.join(self.root, name)
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(content)
        return path

    def _config_dir(self, name: str) -> str:
        root = tempfile.mkdtemp(prefix="prettier-gate-cfg-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        with open(os.path.join(root, name), "w", encoding="utf-8") as handle:
            handle.write("{}")
        return root

    def test_detects_each_config_filename(self) -> None:
        # Mirrors prettier's own resolver: this list drifting from it silently
        # leaves a prettier project unformatted.
        for name in (
            ".prettierrc",
            ".prettierrc.json",
            ".prettierrc.json5",
            ".prettierrc.yaml",
            ".prettierrc.yml",
            ".prettierrc.toml",
            "prettier.config.js",
            "prettier.config.cjs",
            "prettier.config.mjs",
            "prettier.config.ts",
        ):
            with self.subTest(name=name):
                self.assertTrue(has_prettier_config(self._config_dir(name)))

    def test_detects_a_prettier_key_in_package_json(self) -> None:
        self._write("package.json", json.dumps({"prettier": {}}))
        self.assertTrue(has_prettier_config(self.root))

    def test_package_json_without_the_key_does_not_count(self) -> None:
        self._write("package.json", json.dumps({"name": "x", "devDependencies": {}}))
        self.assertFalse(has_prettier_config(self.root))

    def test_malformed_package_json_is_not_a_crash(self) -> None:
        self._write("package.json", "{ not json")
        self.assertFalse(has_prettier_config(self.root))

    def test_finds_a_config_in_an_ancestor(self) -> None:
        self._write(".prettierrc.json", "{}")
        nested = os.path.join(self.root, "a", "b", "c")
        os.makedirs(nested, exist_ok=True)
        self.assertTrue(has_prettier_config(nested))

    def test_a_directory_with_nothing_declared_is_false(self) -> None:
        nested = os.path.join(self.root, "a", "b")
        os.makedirs(nested, exist_ok=True)
        self.assertFalse(has_prettier_config(nested))

    def test_accepts_a_file_path_starting_at_its_directory(self) -> None:
        # The file.edited hook passes a FILE, so the search must start beside it.
        self._write(".prettierrc.json", "{}")
        target = self._write(os.path.join("sub", "doc.md"), "# x\n")
        self.assertTrue(has_prettier_config(target))

    def test_a_file_in_an_undeclared_project_is_false(self) -> None:
        nested = os.path.join(self.root, "a")
        os.makedirs(nested, exist_ok=True)
        target = self._write(os.path.join("a", "doc.md"), "# x\n")
        self.assertFalse(has_prettier_config(target))


if __name__ == "__main__":
    unittest.main()
