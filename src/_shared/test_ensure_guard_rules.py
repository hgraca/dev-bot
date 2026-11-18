import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ensure_guard_rules import add_rules, main, remove_rules  # noqa: E402
from read_jsonc import load_jsonc  # noqa: E402

KUBECTL = r"(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*kubectl(?:\s|$)"
KCTL = r"devbot\s+kctl\s+(?:run|exec)\b"

DIST = """{
  "guards": [
    { "regex": "rm -rf", "message": "rm -rf is blocked" },
    { "regex": "%s", "message": "kubectl is blocked" },
    { "regex": "%s", "message": "devbot kctl run/exec is blocked" }
  ]
}
""" % (KUBECTL.replace("\\", "\\\\"), KCTL.replace("\\", "\\\\"))


def write_temp(text):
    handle = tempfile.NamedTemporaryFile("w", suffix=".jsonc", delete=False, encoding="utf-8")
    handle.write(text)
    handle.close()
    return handle.name


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def write(path, text):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def regexes(path):
    return [rule.get("regex") for rule in load_jsonc(path).get("guards", [])]


class TestAddRules(unittest.TestCase):
    def setUp(self):
        self.dist = write_temp(DIST)

    def tearDown(self):
        os.unlink(self.dist)

    def run_main(self, *args):
        return main(["ensure_guard_rules.py", *args])

    def test_appends_the_named_rule_and_keeps_the_rest(self):
        path = write_temp('{\n  "guards": [\n    { "regex": "rm -rf", "message": "x" }\n  ]\n}\n')
        self.assertEqual(self.run_main("--from", self.dist, "--only-regex", KUBECTL, path), 0)
        self.assertEqual(regexes(path), ["rm -rf", KUBECTL])
        os.unlink(path)

    def test_is_idempotent(self):
        path = write_temp('{\n  "guards": []\n}\n')
        self.run_main("--from", self.dist, "--only-regex", KUBECTL, path)
        first = read(path)
        self.assertEqual(self.run_main("--from", self.dist, "--only-regex", KUBECTL, path), 0)
        self.assertEqual(read(path), first)
        os.unlink(path)

    def test_creates_the_guards_key_when_absent(self):
        path = write_temp('{\n  "project_name": "demo"\n}\n')
        self.run_main("--from", self.dist, "--only-regex", KUBECTL, path)
        self.assertEqual(regexes(path), [KUBECTL])
        self.assertEqual(load_jsonc(path)["project_name"], "demo")
        os.unlink(path)

    def test_only_the_named_rules_are_considered(self):
        path = write_temp('{\n  "guards": []\n}\n')
        self.run_main("--from", self.dist, "--only-regex", KCTL, path)
        self.assertEqual(regexes(path), [KCTL])
        os.unlink(path)

    def test_preserves_comments_and_sibling_keys(self):
        path = write_temp(
            '{\n  "version": "1.18.0", // release\n  "guards": [\n'
            '    { "regex": "rm -rf", "message": "x" } // keep\n  ]\n}\n'
        )
        self.run_main("--from", self.dist, "--only-regex", KUBECTL, path)
        text = read(path)
        self.assertIn("// release", text)
        self.assertIn("// keep", text)
        self.assertIn('"version": "1.18.0"', text)
        # The added rule must be parseable — a comma inside the comment would not be.
        self.assertIn(KUBECTL, regexes(path))
        os.unlink(path)

    def test_a_message_comes_from_the_dist(self):
        path = write_temp('{\n  "guards": []\n}\n')
        self.run_main("--from", self.dist, "--only-regex", KUBECTL, path)
        rules = load_jsonc(path)["guards"]
        self.assertEqual(rules[0]["message"], "kubectl is blocked")
        os.unlink(path)


class TestRemoveRules(unittest.TestCase):
    def test_removes_the_named_rule_only(self):
        path = write_temp(
            '{\n  "guards": [\n    { "regex": "rm -rf", "message": "x" },\n'
            '    { "regex": "%s", "message": "y" }\n  ]\n}\n' % KUBECTL.replace("\\", "\\\\")
        )
        updated, count = remove_rules(read(path), {KUBECTL})
        self.assertEqual(count, 1)
        write(path, updated)
        self.assertEqual(regexes(path), ["rm -rf"])
        os.unlink(path)

    def test_is_a_round_trip_back_to_the_original(self):
        original = '{\n  "guards": [\n    { "regex": "rm -rf", "message": "x" },\n    { "regex": "sudo .*", "message": "y" }\n  ]\n}\n'
        path = write_temp(original)
        self.assertEqual(
            main(["ensure_guard_rules.py", "--remove-regex", KUBECTL, "--remove-regex", KCTL, path]), 0
        )
        self.assertEqual(read(path), original, "a config without the rule is untouched")
        os.unlink(path)

    def test_an_absent_rule_reports_absent_and_writes_nothing(self):
        path = write_temp('{\n  "guards": [\n    { "regex": "rm -rf", "message": "x" }\n  ]\n}\n')
        before = read(path)
        self.assertEqual(main(["ensure_guard_rules.py", "--remove-regex", KUBECTL, path]), 0)
        self.assertEqual(read(path), before)
        os.unlink(path)

    def test_an_empty_array_is_left_valid(self):
        path = write_temp(
            '{\n  "guards": [\n    { "regex": "%s", "message": "y" }\n  ]\n}\n'
            % KUBECTL.replace("\\", "\\\\")
        )
        updated, count = remove_rules(read(path), {KUBECTL})
        self.assertEqual(count, 1)
        write(path, updated)
        self.assertEqual(regexes(path), [])
        os.unlink(path)


class TestAddRulesDirect(unittest.TestCase):
    def test_keeps_a_trailing_array_comment(self):
        text = '{\n  "guards": [\n    { "regex": "rm -rf", "message": "x" } // keep\n  ]\n}\n'
        updated = add_rules(text, [{"regex": KUBECTL, "message": "m"}])
        self.assertIn("// keep", updated)
        path = write_temp(updated)
        self.assertEqual(regexes(path), ["rm -rf", KUBECTL])
        os.unlink(path)

    def test_a_one_line_array_gets_a_well_formed_result(self):
        updated = add_rules('{\n  "guards": [],\n  "other": 1\n}\n', [{"regex": KUBECTL, "message": "m"}])
        path = write_temp(updated)
        self.assertEqual(regexes(path), [KUBECTL])
        self.assertEqual(load_jsonc(path)["other"], 1)
        self.assertIn('"guards": [\n', updated)
        os.unlink(path)


if __name__ == "__main__":
    unittest.main()
