import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ensure_autobot_block import find_top_level_object, inject, main  # noqa: E402
from read_jsonc import load_jsonc  # noqa: E402


def write_temp(text):
    handle = tempfile.NamedTemporaryFile("w", suffix=".jsonc", delete=False, encoding="utf-8")
    handle.write(text)
    handle.close()
    return handle.name


class TestFindTopLevelObject(unittest.TestCase):
    def test_finds_the_object(self):
        self.assertEqual(find_top_level_object('{"a": 1}'), (0, 7))

    def test_ignores_braces_in_strings(self):
        start, end = find_top_level_object('{"a": "}"}')
        self.assertEqual((start, end), (0, 9))

    def test_ignores_braces_in_comments(self):
        start, end = find_top_level_object('// }\n{"a": 1}')
        self.assertNotEqual(start, -1)
        self.assertEqual(end, 12)

    def test_reports_missing_object(self):
        self.assertEqual(find_top_level_object("// nothing here"), (-1, -1))


class TestInject(unittest.TestCase):
    def test_adds_the_block_to_a_populated_object(self):
        result = load_jsonc_text(inject('{\n  "harness": "opencode"\n}'))
        self.assertEqual(result["harness"], "opencode")
        self.assertEqual(
            result["autobot"], {"poll_jira": False, "poll_github": False, "prompts": []}
        )

    def test_adds_the_block_to_an_empty_object(self):
        result = load_jsonc_text(inject("{}"))
        self.assertIn("autobot", result)

    def test_does_not_double_a_trailing_comma(self):
        text = inject('{\n  "harness": "opencode",\n}')
        self.assertNotIn(",,\n", text)
        self.assertIn("autobot", load_jsonc_text(text))

    def test_handles_a_trailing_comma_before_a_comment(self):
        text = inject('{\n  "harness": "opencode", // keep me\n}')
        self.assertIn("// keep me", text)
        self.assertIn("autobot", load_jsonc_text(text))

    def test_preserves_comments(self):
        text = inject('{\n  // keep me\n  "harness": "opencode"\n}')
        self.assertIn("// keep me", text)

    def test_returns_none_without_an_object(self):
        self.assertIsNone(inject("// nothing"))


class TestMain(unittest.TestCase):
    def test_injects_into_a_file_without_the_key(self):
        path = write_temp('{\n  "harness": "opencode"\n}')
        try:
            self.assertEqual(main(["tool", path]), 0)
            self.assertIn("autobot", load_jsonc(path))
        finally:
            os.unlink(path)

    def test_leaves_a_file_that_already_has_the_key(self):
        original = '{\n  "autobot": {"poll_jira": true}\n}'
        path = write_temp(original)
        try:
            self.assertEqual(main(["tool", path]), 0)
            with open(path, encoding="utf-8") as handle:
                self.assertEqual(handle.read(), original)
        finally:
            os.unlink(path)

    def test_respects_an_explicit_null(self):
        original = '{\n  "autobot": null\n}'
        path = write_temp(original)
        try:
            self.assertEqual(main(["tool", path]), 0)
            with open(path, encoding="utf-8") as handle:
                self.assertEqual(handle.read(), original)
        finally:
            os.unlink(path)

    def test_fails_on_a_missing_file(self):
        self.assertEqual(main(["tool", "/nonexistent/config.jsonc"]), 1)

    def test_fails_without_a_top_level_object(self):
        path = write_temp("null")
        try:
            self.assertEqual(main(["tool", path]), 1)
        finally:
            os.unlink(path)


def load_jsonc_text(text):
    handle = tempfile.NamedTemporaryFile("w", suffix=".jsonc", delete=False, encoding="utf-8")
    handle.write(text)
    handle.close()
    try:
        return load_jsonc(handle.name)
    finally:
        os.unlink(handle.name)


if __name__ == "__main__":
    unittest.main()
