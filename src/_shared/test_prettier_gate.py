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
    find_prettier_ignore,
    has_prettier_config,
    in_agent_workspace,
    prettier_available,
    prettier_batch_config_args,
    prettier_config_args,
    prettier_ignore_args,
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
            [(
                targets,
                ["--config", prettier_gate.DEFAULT_CONFIG_PATH, "--ignore-path", os.devnull],
            )],
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
                ([configured], ["--ignore-path", os.devnull]),
                (
                    [unconfigured],
                    ["--config", prettier_gate.DEFAULT_CONFIG_PATH, "--ignore-path", os.devnull],
                ),
            ],
        )

    def test_a_wholly_configured_batch_passes_no_config(self) -> None:
        with open(os.path.join(self.root, ".prettierrc.json"), "w", encoding="utf-8") as handle:
            handle.write("{}")
        targets = [os.path.join(self.root, "a.json")]
        self.assertEqual(
            prettier_batch_config_args(targets), [(targets, ["--ignore-path", os.devnull])]
        )


class PrettierIgnoreTest(unittest.TestCase):
    """The project's formatter rules govern its files; the vault is exempt."""

    def setUp(self) -> None:
        self.root = tempfile.mkdtemp(prefix="prettier-ignore-")
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        # Isolate the install-wide config: the machine's own declares devbot_dir,
        # and a test inheriting it would pass or fail with that setup.
        self.devbot_root = tempfile.mkdtemp(prefix="prettier-devbot-root-")
        self.addCleanup(shutil.rmtree, self.devbot_root, ignore_errors=True)
        patcher = mock.patch.dict(os.environ, {"DEV_BOT_ROOT": self.devbot_root})
        patcher.start()
        self.addCleanup(patcher.stop)

    def _write_global(self, content: str) -> None:
        with open(
            os.path.join(self.devbot_root, ".devbot.global.jsonc"), "w", encoding="utf-8"
        ) as handle:
            handle.write(content)

    def _write(self, relative: str, content: str = "") -> str:
        path = os.path.join(self.root, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(content)
        return path

    def test_a_project_ignore_file_is_found_from_a_nested_file(self) -> None:
        ignore = self._write(".prettierignore", "/*\n!/src/\n")
        target = self._write(os.path.join("src", "deep", "a.yml"), "a: 1\n")
        self.assertEqual(find_prettier_ignore(target), ignore)

    def test_a_project_without_an_ignore_file_falls_back_to_dev_null(self) -> None:
        target = self._write("a.yml", "a: 1\n")
        self.assertEqual(prettier_ignore_args(target), ["--ignore-path", os.devnull])

    def test_a_project_ignore_file_is_pinned(self) -> None:
        ignore = self._write(".prettierignore", "/*\n")
        target = self._write("a.yml", "a: 1\n")
        self.assertEqual(prettier_ignore_args(target), ["--ignore-path", ignore])

    def test_the_agent_workspace_is_exempt_from_the_project_ignore(self) -> None:
        # The vault is dev-bot's own artifact: a project's ignore rules were not
        # written about it, and gitignoring it must not stop it being formatted.
        self._write(".prettierignore", "/*\n")
        self._write(".devbot.project.jsonc", '{"devbot_dir": ".agents"}')
        note = self._write(os.path.join(".agents", "memory", "n.md"), "# x\n")
        self.assertTrue(in_agent_workspace(note))
        self.assertEqual(prettier_ignore_args(note), ["--ignore-path", os.devnull])

    def test_a_configured_devbot_dir_is_what_counts(self) -> None:
        self._write(".prettierignore", "/*\n")
        self._write(".devbot.project.jsonc", '{"devbot_dir": ".devbot"}')
        inside = self._write(os.path.join(".devbot", "notes", "n.md"), "# x\n")
        outside = self._write(os.path.join(".agents", "notes", "n.md"), "# x\n")
        self.assertTrue(in_agent_workspace(inside))
        self.assertFalse(in_agent_workspace(outside))

    def test_a_globally_configured_devbot_dir_is_recognised(self) -> None:
        # devbot_dir is project-first / global-fallback: a project that declares
        # it only in the global config must still have its workspace exempt.
        self._write_global('{"devbot_dir": ".devbot"}')
        inside = self._write(os.path.join(".devbot", "notes", "n.md"), "# x\n")
        outside = self._write(os.path.join(".agents", "notes", "n.md"), "# x\n")
        self.assertTrue(in_agent_workspace(inside))
        self.assertFalse(in_agent_workspace(outside))

    def test_the_project_value_wins_over_the_global_one(self) -> None:
        self._write_global('{"devbot_dir": ".glob"}')
        self._write(".devbot.project.jsonc", '{"devbot_dir": ".proj"}')
        inside = self._write(os.path.join(".proj", "notes", "n.md"), "# x\n")
        self.assertFalse(in_agent_workspace(os.path.join(self.root, ".glob", "n.md")))
        self.assertTrue(in_agent_workspace(inside))

    def test_the_global_config_override_is_honoured(self) -> None:
        # DEV_BOT_GLOBAL_CONFIG is the supported redirect (functions.sh:
        # _devbot_global_config); ignoring it reads the developer's real config.
        override = os.path.join(self.devbot_root, "alt.global.jsonc")
        with open(override, "w", encoding="utf-8") as handle:
            handle.write('{"devbot_dir": ".alt"}')
        inside = self._write(os.path.join(".alt", "notes", "n.md"), "# x\n")
        outside = self._write(os.path.join(".agents", "notes", "n.md"), "# x\n")
        with mock.patch.dict(os.environ, {"DEV_BOT_GLOBAL_CONFIG": override}):
            self.assertTrue(in_agent_workspace(inside))
            self.assertFalse(in_agent_workspace(outside))

    def test_a_nested_devbot_dir_in_the_global_config_is_recognised(self) -> None:
        # devbot_dir is a relative path, not a single path segment.
        self._write_global('{"devbot_dir": ".config/devbot"}')
        inside = self._write(os.path.join(".config", "devbot", "notes", "n.md"), "# x\n")
        outside = self._write(os.path.join(".agents", "notes", "n.md"), "# x\n")
        self.assertTrue(in_agent_workspace(inside))
        self.assertFalse(in_agent_workspace(outside))

    def test_without_a_devbot_config_the_conventional_directory_decides(self) -> None:
        note = self._write(os.path.join(".agents", "memory", "n.md"), "# x\n")
        self.assertTrue(in_agent_workspace(note))

    def test_a_batch_splits_on_the_ignore_file_too(self) -> None:
        # One --ignore-path applies to the whole invocation, so two projects
        # with different ignore files cannot share a run.
        other = tempfile.mkdtemp(prefix="prettier-ignore-other-")
        self.addCleanup(shutil.rmtree, other, ignore_errors=True)
        self._write(".prettierrc.json", "{}")
        first_ignore = self._write(".prettierignore", "/*\n")
        other_ignore = os.path.join(other, ".prettierignore")
        with open(other_ignore, "w", encoding="utf-8") as handle:
            handle.write("/**\n")
        with open(os.path.join(other, ".prettierrc.json"), "w", encoding="utf-8") as handle:
            handle.write("{}")
        first = self._write(os.path.join("src", "a.yml"), "a: 1\n")
        second = os.path.join(other, "b.yml")
        self.assertEqual(
            prettier_batch_config_args([first, second]),
            [
                ([first], ["--ignore-path", first_ignore]),
                ([second], ["--ignore-path", other_ignore]),
            ],
        )


if __name__ == "__main__":
    unittest.main()
