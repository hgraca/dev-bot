#!/usr/bin/env python3
"""Unit tests for read_jsonc.py — the canonical JSONC reader.

The failure mode these cover: a malformed config used to surface as a bare
``Expecting value: line 1 column 1`` traceback (or, worse, as "no project"),
which is indistinguishable from a missing file or a BOM.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import read_jsonc  # noqa: E402

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "read_jsonc.py")


class LoadJsoncTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, content, encoding="utf-8"):
        path = os.path.join(self.dir, name)
        with open(path, "w", encoding=encoding) as f:
            f.write(content)
        return path

    def test_plain_json(self):
        path = self.write("a.json", '{"a": 1}')
        self.assertEqual(read_jsonc.load_jsonc(path), {"a": 1})

    def test_comments_and_trailing_commas(self):
        path = self.write("b.json", '{\n  // note\n  "a": 1,\n}\n')
        self.assertEqual(read_jsonc.load_jsonc(path), {"a": 1})

    def test_utf8_bom_is_tolerated(self):
        path = self.write("c.json", '{"a": 1}', encoding="utf-8-sig")
        self.assertEqual(read_jsonc.load_jsonc(path), {"a": 1})

    def test_malformed_file_names_itself_in_the_error(self):
        path = self.write("d.json", '{"a": }')
        with self.assertRaises(json.JSONDecodeError) as ctx:
            read_jsonc.load_jsonc(path)
        self.assertIn(path, str(ctx.exception))

    def test_line_number_survives_a_multiline_comment(self):
        """The promised path:line:col must point at the real source line."""
        path = self.write(
            "f.jsonc",
            '{\n'
            '  /* a comment\n'
            '     spanning three\n'
            '     lines */\n'
            '  "a": 1,\n'
            '  "b": }\n'
            '}\n',
        )
        with self.assertRaises(json.JSONDecodeError) as ctx:
            read_jsonc.load_jsonc(path)
        self.assertIn("line 6", str(ctx.exception))

    def test_column_survives_an_inline_block_comment(self):
        """Same-line comments must not shift the reported column either."""
        line = '{"a": 1, /* note */ "b": }'
        path = self.write("g.jsonc", line + "\n")
        expected = line.index("}") + 1
        with self.assertRaises(json.JSONDecodeError) as ctx:
            read_jsonc.load_jsonc(path)
        self.assertIn(f"column {expected}", str(ctx.exception))

    def test_malformed_file_is_still_a_value_error(self):
        # Callers catch ValueError; enriching the message must not change the
        # exception type they rely on.
        path = self.write("e.json", '{"a": }')
        with self.assertRaises(ValueError):
            read_jsonc.load_jsonc(path)


class MainCliTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args):
        return subprocess.run(
            [sys.executable, SCRIPT, *args], capture_output=True, text=True
        )

    def test_field_lookup(self):
        path = os.path.join(self.dir, "ok.jsonc")
        with open(path, "w") as f:
            f.write('{"project_name": "demo"}\n')
        result = self.run_cli(path, "project_name")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "demo")

    def test_malformed_config_exits_2_with_located_error(self):
        path = os.path.join(self.dir, "bad.jsonc")
        with open(path, "w") as f:
            f.write('{"project_name": "demo"\n')
        result = self.run_cli(path, "project_name")
        self.assertEqual(result.returncode, 2)
        self.assertIn("ERROR:", result.stderr)
        self.assertIn(path, result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_invalid_utf8_exits_2_with_a_located_error(self):
        path = os.path.join(self.dir, "latin1.jsonc")
        with open(path, "wb") as f:
            f.write(b'{"name": "caf\xe9"}')
        result = self.run_cli(path, "name")
        self.assertEqual(result.returncode, 2)
        self.assertIn("ERROR:", result.stderr)
        self.assertIn(path, result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_missing_file_exits_2_with_located_error(self):
        result = self.run_cli(os.path.join(self.dir, "nope.jsonc"), "project_name")
        self.assertEqual(result.returncode, 2)
        self.assertIn("ERROR:", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_no_arguments_exits_2(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage", result.stderr)


if __name__ == "__main__":
    unittest.main()
