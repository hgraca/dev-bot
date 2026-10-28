"""Tests for the prettier availability/config resolution shared by the format-* tools.

The format-* hooks install into every project dev-bot scaffolds, but not every
project is a prettier project. These tests pin both halves: a project that
declares prettier keeps its own configuration, and one that declares none is
formatted with the defaults dev-bot ships instead of being skipped.
"""

from __future__ import annotations

import json
import os
import shutil
import tempfile
import unittest
from unittest import mock

import prettier_gate
from prettier_gate import (
    has_prettier_config,
    prettier_available,
    prettier_batch_config_args,
    prettier_config_args,
)


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
        # Mirrors prettier's own resolver (docs/configuration): this list drifting
        # from it silently overrides a prettier project with dev-bot's defaults.
        for name in (
            ".prettierrc",
            ".prettierrc.json",
            ".prettierrc.json5",
            ".prettierrc.yaml",
            ".prettierrc.yml",
            ".prettierrc.toml",
            ".prettierrc.js",
            ".prettierrc.cjs",
            ".prettierrc.mjs",
            ".prettierrc.ts",
            ".prettierrc.mts",
            ".prettierrc.cts",
            "prettier.config.js",
            "prettier.config.cjs",
            "prettier.config.mjs",
            "prettier.config.ts",
            "prettier.config.mts",
            "prettier.config.cts",
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


class PrettierConfigArgsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = tempfile.mkdtemp(prefix="prettier-args-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)

    def test_the_shipped_default_config_is_valid_json(self) -> None:
        # A malformed default would fail every run in a project without a config.
        with open(prettier_gate.DEFAULT_CONFIG_PATH, encoding="utf-8") as handle:
            self.assertIsInstance(json.load(handle), dict)

    def test_a_project_without_a_config_gets_the_dev_bot_default(self) -> None:
        self.assertEqual(
            prettier_config_args(self.root),
            ["--config", prettier_gate.DEFAULT_CONFIG_PATH],
        )

    def test_a_project_that_declares_prettier_resolves_its_own_config(self) -> None:
        with open(os.path.join(self.root, ".prettierrc.json"), "w", encoding="utf-8") as handle:
            handle.write("{}")
        self.assertEqual(prettier_config_args(self.root), [])

    def test_a_typescript_module_config_is_recognised(self) -> None:
        # Prettier 3 reads prettier.config.mts/.cts and .prettierrc.mts/.cts;
        # missing them would hand such a project dev-bot's defaults instead.
        with open(os.path.join(self.root, "prettier.config.mts"), "w", encoding="utf-8") as handle:
            handle.write("export default {};")
        self.assertEqual(prettier_config_args(self.root), [])

    def test_a_batch_without_any_config_gets_the_dev_bot_default(self) -> None:
        targets = [self.root, os.path.join(self.root, "a.json")]
        self.assertEqual(
            prettier_batch_config_args(targets),
            [(targets, ["--config", prettier_gate.DEFAULT_CONFIG_PATH])],
        )

    def test_a_mixed_batch_is_split_so_every_file_keeps_its_config(self) -> None:
        # One --config applies to the whole invocation: a single pass would
        # either override the nested project's settings or drop dev-bot's
        # defaults for the file that declares none.
        nested = os.path.join(self.root, "nested")
        os.makedirs(nested)
        with open(os.path.join(nested, ".prettierrc.json"), "w", encoding="utf-8") as handle:
            handle.write("{}")
        configured = os.path.join(nested, "a.json")
        unconfigured = os.path.join(self.root, "b.json")
        self.assertEqual(
            prettier_batch_config_args([configured, unconfigured]),
            [
                ([configured], []),
                ([unconfigured], ["--config", prettier_gate.DEFAULT_CONFIG_PATH]),
            ],
        )

    def test_a_wholly_configured_batch_passes_no_config(self) -> None:
        with open(os.path.join(self.root, ".prettierrc.json"), "w", encoding="utf-8") as handle:
            handle.write("{}")
        targets = [os.path.join(self.root, "a.json")]
        self.assertEqual(prettier_batch_config_args(targets), [(targets, [])])


if __name__ == "__main__":
    unittest.main()
