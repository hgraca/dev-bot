#!/usr/bin/env python3
"""Tests for set_module_flags.py — the comment-preserving module-default writer.

Run: python3 -m unittest src/_shared/test_set_module_flags.py
"""

import json
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "set_module_flags.py")

import sys

sys.path.insert(0, HERE)
from read_jsonc import load_jsonc  # noqa: E402


class SetModuleFlagsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="module-flags-")
        self.path = os.path.join(self.dir, "config.jsonc")

    def write(self, text):
        with open(self.path, "w", encoding="utf-8") as fh:
            fh.write(text)
        return self.path

    def read(self):
        with open(self.path, encoding="utf-8") as fh:
            return fh.read()

    def run_flags(self, *flags):
        return subprocess.run(
            ["python3", SCRIPT, self.path, *flags],
            capture_output=True,
            text=True,
        )

    def modules(self):
        return load_jsonc(self.path)["modules"]

    # ── the normal shapes ────────────────────────────────────────────────────

    def test_flips_an_existing_true_to_false(self):
        self.write('{\n  "modules": {\n    "herdr": true,\n    "other": false\n  }\n}\n')

        result = self.run_flags("herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SET herdr=false", result.stdout)
        self.assertEqual(self.modules()["herdr"], False)
        self.assertEqual(self.modules()["other"], False)

    def test_inserts_a_missing_flag_and_keeps_order(self):
        self.write('{\n  "modules": {\n    "atlassian": false\n  }\n}\n')

        result = self.run_flags("herdr=false", "ghostty=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.modules(), {"ghostty": False, "atlassian": False, "herdr": False}
        )

    def test_keeps_the_trailing_comment_of_a_rewritten_flag(self):
        self.write(
            '{\n  "modules": {\n    "herdr": true, // on trial\n    "x": false\n  }\n}\n'
        )

        self.run_flags("herdr=false")

        self.assertIn("// on trial", self.read())
        self.assertEqual(self.modules()["herdr"], False)

    def test_creates_the_modules_map_when_absent(self):
        self.write('{\n  "auto_update": true\n}\n')

        result = self.run_flags("herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.modules(), {"herdr": False})
        self.assertEqual(load_jsonc(self.path)["auto_update"], True)

    def test_expands_an_empty_modules_map(self):
        self.write('{\n  "modules": {},\n  "x": 1\n}\n')

        result = self.run_flags("herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.modules(), {"herdr": False})
        self.assertNotIn("{,", self.read())

    def test_creates_the_map_in_an_empty_config(self):
        self.write("{}\n")

        result = self.run_flags("herdr=false", "ghostty=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.modules(), {"herdr": False, "ghostty": False})

    # ── idempotency and preservation ─────────────────────────────────────────

    def test_creates_the_map_after_a_root_trailing_comma(self):
        # Legal JSONC that the reconciler accepts too: appending after the comma
        # would produce two commas in a row and abort the whole migration phase.
        self.write('{\n  "version": "1.24.0",\n}\n')

        result = self.run_flags("herdr=false", "ghostty=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.modules(), {"herdr": False, "ghostty": False})
        self.assertEqual(load_jsonc(self.path)["version"], "1.24.0")

    def test_adds_to_a_map_that_ends_with_a_trailing_comma(self):
        self.write('{\n  "modules": {\n    "x": false,\n  }\n}\n')

        result = self.run_flags("herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.modules(), {"x": False, "herdr": False})

    def test_writes_through_a_symlinked_config(self):
        self.write('{\n  "modules": {}\n}\n')
        link = os.path.join(self.dir, "linked.jsonc")
        os.symlink(self.path, link)

        result = subprocess.run(
            ["python3", SCRIPT, link, "herdr=false"],
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.path.islink(link))
        self.assertEqual(self.modules(), {"herdr": False})

    def test_adds_after_a_member_that_ends_with_a_line_comment(self):
        # The separator must land after the VALUE, not after the comment, or the
        # new member is commented out and the rewrite cannot parse.
        self.write(
            '{\n  "modules": {\n    "other": false // kept\n  }\n}\n'
        )

        result = self.run_flags("herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.modules(), {"other": False, "herdr": False})
        self.assertIn("// kept", self.read())

    def test_adds_after_the_last_member_of_the_root_with_a_line_comment(self):
        self.write('{\n  "auto_update": true // keep\n}\n')

        result = self.run_flags("herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.modules(), {"herdr": False})
        self.assertEqual(load_jsonc(self.path)["auto_update"], True)
        self.assertIn("// keep", self.read())

    def test_second_run_is_unchanged_and_writes_nothing(self):
        self.write('{\n  "modules": {\n    "herdr": false\n  }\n}\n')
        before = os.stat(self.path).st_mtime_ns

        result = self.run_flags("herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("UNCHANGED herdr=false", result.stdout)
        self.assertEqual(os.stat(self.path).st_mtime_ns, before)

    def test_preserves_comments_elsewhere_in_the_file(self):
        self.write(
            "{\n  // keep me\n  \"modules\": { \"x\": false },\n"
            "  /* and me */\n  \"y\": 1\n}\n"
        )

        self.run_flags("herdr=false")

        text = self.read()
        self.assertIn("// keep me", text)
        self.assertIn("/* and me */", text)
        self.assertEqual(load_jsonc(self.path)["y"], 1)

    def test_does_not_match_a_nested_same_named_key(self):
        self.write(
            '{\n  "modules": {\n    "other": false\n  },\n'
            '  "nested": {\n    "herdr": true\n  }\n}\n'
        )

        self.run_flags("herdr=false")

        data = load_jsonc(self.path)
        self.assertEqual(data["modules"]["herdr"], False)
        self.assertEqual(data["nested"]["herdr"], True)

    def test_preserves_the_file_mode(self):
        self.write('{\n  "modules": {}\n}\n')
        os.chmod(self.path, 0o600)

        self.run_flags("herdr=false")

        self.assertEqual(os.stat(self.path).st_mode & 0o777, 0o600)

    # ── --if-absent: a release default never overrides a machine's choice ────

    def test_if_absent_writes_a_key_the_config_does_not_name(self):
        self.write('{\n  "modules": {\n    "other": false\n  }\n}\n')

        result = self.run_flags("--if-absent", "herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SET herdr=false", result.stdout)
        self.assertEqual(self.modules(), {"other": False, "herdr": False})

    def test_if_absent_keeps_a_value_the_machine_set(self):
        self.write('{\n  "modules": {\n    "herdr": true\n  }\n}\n')
        before = self.read()

        result = self.run_flags("--if-absent", "herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PRESENT herdr=true", result.stdout)
        self.assertEqual(self.read(), before)

    def test_if_absent_keeps_a_present_value_that_is_not_a_boolean(self):
        # Present is not the same as "a boolean we understand": the key exists,
        # so it is the machine's setting and the release default leaves it alone.
        self.write('{\n  "modules": {\n    "herdr": "manual"\n  }\n}\n')
        before = self.read()

        result = self.run_flags("--if-absent", "herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PRESENT herdr=", result.stdout)
        self.assertIn("manual", result.stdout)
        self.assertEqual(self.read(), before)

    def test_if_absent_reports_an_already_matching_key_as_present(self):
        self.write('{\n  "modules": {\n    "herdr": false\n  }\n}\n')

        result = self.run_flags("--if-absent", "herdr=false")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PRESENT herdr=false", result.stdout)

    # ── refusals ─────────────────────────────────────────────────────────────

    def test_refuses_a_flag_that_is_not_boolean(self):
        self.write('{\n  "modules": {}\n}\n')

        result = self.run_flags("herdr=yes")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected <name>=true|false", result.stderr)
        self.assertEqual(self.modules(), {})

    def test_refuses_a_config_that_does_not_parse_and_leaves_it_alone(self):
        broken = '{\n  "modules": {\n'
        self.write(broken)

        result = self.run_flags("herdr=false")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.read(), broken)

    def test_refuses_a_missing_file(self):
        result = subprocess.run(
            ["python3", SCRIPT, os.path.join(self.dir, "absent.jsonc"), "herdr=false"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot read", result.stderr)


if __name__ == "__main__":
    unittest.main()
