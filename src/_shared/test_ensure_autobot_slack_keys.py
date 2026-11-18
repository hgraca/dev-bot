import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ensure_autobot_slack_keys import (  # noqa: E402
    find_autobot_object,
    insertion_lines,
    main,
    mentioned_keys,
    splice,
)
from read_jsonc import load_jsonc  # noqa: E402


def write_temp(text):
    handle = tempfile.NamedTemporaryFile("w", suffix=".jsonc", delete=False, encoding="utf-8")
    handle.write(text)
    handle.close()
    return handle.name


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def load_text(text):
    path = write_temp(text)
    try:
        return load_jsonc(path)
    finally:
        os.unlink(path)


class TestFindAutobotObject(unittest.TestCase):
    def test_finds_the_block(self):
        open_index, close_index = find_autobot_object('{\n  "autobot": {"poll_jira": true}\n}')
        self.assertEqual(open_index, 15)
        self.assertEqual(close_index, 33)

    def test_ignores_a_modules_boolean(self):
        text = '{\n  "modules": {"autobot": false},\n  "autobot": {"poll_jira": true}\n}'
        open_index, close_index = find_autobot_object(text)
        self.assertNotEqual(open_index, -1)
        self.assertEqual(text[open_index : close_index + 1], '{"poll_jira": true}')

    def test_ignores_braces_in_strings_and_comments(self):
        text = '{\n  // } not a brace\n  "autobot": {"prompt": "}"}\n}'
        open_index, close_index = find_autobot_object(text)
        self.assertEqual(text[open_index : close_index + 1], '{"prompt": "}"}')

    def test_reports_a_profile_name(self):
        self.assertEqual(find_autobot_object('{\n  "autobot": "gete-jira"\n}'), (-1, -1))

    def test_reports_an_explicit_null(self):
        self.assertEqual(find_autobot_object('{\n  "autobot": null\n}'), (-1, -1))


class TestMentionedKeys(unittest.TestCase):
    def test_counts_a_real_property(self):
        self.assertEqual(mentioned_keys('{"poll_slack": true}'), {"poll_slack"})

    def test_counts_a_commented_key_line(self):
        region = '{\n  // "slack_user_email": "a@b.c",\n}'
        self.assertEqual(mentioned_keys(region), {"slack_user_email"})

    def test_counts_a_block_comment_key_line(self):
        region = '{\n  /* "slack_bot_token": "${X}" */\n}'
        self.assertEqual(mentioned_keys(region), {"slack_bot_token"})

    def test_counts_every_key_in_a_multiline_block_comment(self):
        region = (
            "{\n"
            "  /*\n"
            '   * "poll_slack": false,\n'
            '   * "slack_user_email": "a@b.c",\n'
            '   * "slack_bot_token": "${X}",\n'
            "   */\n"
            "}"
        )
        self.assertEqual(mentioned_keys(region), set(("poll_slack", "slack_user_email", "slack_bot_token")))

    def test_counts_every_key_on_one_block_comment_line(self):
        region = '{\n  /* "poll_slack": false, "slack_user_email": "a@b.c", "slack_bot_token": "${X}" */\n}'
        self.assertEqual(mentioned_keys(region), set(("poll_slack", "slack_user_email", "slack_bot_token")))

    def test_ignores_a_key_used_as_a_string_value(self):
        region = '{"jira_assignees": ["poll_slack", "slack_user_email", "slack_bot_token"]}'
        self.assertEqual(mentioned_keys(region), set())

    def test_ignores_a_comment_that_mentions_a_key_mid_sentence(self):
        self.assertEqual(mentioned_keys('// we may add "poll_slack" later'), set())

    def test_ignores_a_key_without_a_colon(self):
        self.assertEqual(mentioned_keys('{"note": "poll_slack"}'), set())

    def test_ignores_a_nested_property(self):
        self.assertEqual(mentioned_keys('{"connection": {"poll_slack": true}}'), set())

    def test_counts_a_direct_property_beside_a_nested_one(self):
        region = '{"connection": {"poll_slack": true}, "slack_user_email": "a@b.c"}'
        self.assertEqual(mentioned_keys(region), {"slack_user_email"})

    def test_ignores_a_key_nested_in_an_array(self):
        self.assertEqual(mentioned_keys('{"prompts": [{"poll_slack": true}]}'), set())

    def test_ignores_a_commented_key_inside_a_nested_object(self):
        region = '{"connection": {\n    // "poll_slack": false,\n    "jira_base_url": "x"\n  }}'
        self.assertEqual(mentioned_keys(region), set())

    def test_skips_a_comment_between_the_key_and_its_colon(self):
        self.assertEqual(mentioned_keys('{"poll_slack" /* why */: true}'), {"poll_slack"})

    def test_does_not_re_add_a_key_commented_before_its_colon(self):
        original = '{\n  "autobot": {\n    "slack_user_email" // who\n    : "a@b.c"\n  }\n}\n'
        path = write_temp(original)
        try:
            self.assertEqual(main(["tool", path]), 0)
            self.assertEqual(read(path).count('"slack_user_email"'), 1)
        finally:
            os.unlink(path)


class TestInsertionLines(unittest.TestCase):
    def test_adds_the_header_and_all_three_keys(self):
        lines = insertion_lines('{"poll_jira": true}', "    ")
        self.assertEqual(len(lines), 4)
        self.assertIn("Talk to one person over Slack", lines[0])
        self.assertEqual(lines[1], '    // "poll_slack": false,')

    def test_omits_the_header_when_poll_slack_is_mentioned(self):
        region = '{"poll_slack": true, "poll_jira": true}'
        lines = insertion_lines(region, "  ")
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[0].strip().startswith('// "slack_user_email"'))

    def test_adds_nothing_when_every_key_is_mentioned(self):
        region = '{"poll_slack": true,\n  "slack_user_email": "a@b.c",\n  "slack_bot_token": "${X}"}'
        self.assertEqual(insertion_lines(region, "  "), [])

    def test_counts_a_commented_key_as_mentioned(self):
        region = '{\n  // "poll_slack": false,\n}'
        self.assertNotIn('poll_slack', insertion_lines(region, "  ")[0])

    def test_still_adds_the_keys_when_values_spell_their_names(self):
        region = '{"jira_assignees": ["poll_slack", "slack_user_email", "slack_bot_token"]}'
        self.assertEqual(len(insertion_lines(region, "  ")), 4)


class TestSplice(unittest.TestCase):
    def test_keeps_a_comment_after_the_last_value(self):
        text = '{\n  "autobot": {\n    "poll_jira": true\n    // keep me\n  }\n}'
        open_index, close_index = find_autobot_object(text)
        result = splice(text, open_index, close_index, ["    // ours"], "  ")
        self.assertIn("// keep me", result)
        self.assertIn("// ours", result)
        self.assertIn('"poll_jira": true,', result)

    def test_does_not_double_a_trailing_comma(self):
        text = '{\n  "autobot": {\n    "poll_jira": true,\n  }\n}'
        open_index, close_index = find_autobot_object(text)
        result = splice(text, open_index, close_index, ["    // ours"], "  ")
        self.assertNotIn(",,", result)


class TestMain(unittest.TestCase):
    def test_adds_the_keys_to_an_existing_block(self):
        original = (
            "{\n"
            '  "harness": "opencode",\n'
            '  "autobot": {\n'
            '    "poll_jira": true,\n'
            '    "jira_assignees": ["you@example.com"]\n'
            "  }\n"
            "}\n"
        )
        path = write_temp(original)
        try:
            self.assertEqual(main(["tool", path]), 0)
            text = read(path)
            self.assertIn('// "poll_slack": false,', text)
            self.assertIn('// "slack_user_email": "you@example.com",', text)
            self.assertIn('// "slack_bot_token": "${SLACK_BOT_TOKEN}",', text)
            # The existing configuration is untouched and the file still parses.
            config = load_jsonc(path)
            self.assertTrue(config["autobot"]["poll_jira"])
            self.assertEqual(config["autobot"]["jira_assignees"], ["you@example.com"])
            self.assertIsNone(config["autobot"].get("slack_bot_token"))
        finally:
            os.unlink(path)

    def test_is_idempotent(self):
        path = write_temp('{\n  "autobot": {"poll_jira": true}\n}\n')
        try:
            self.assertEqual(main(["tool", path]), 0)
            once = read(path)
            self.assertEqual(main(["tool", path]), 0)
            self.assertEqual(read(path), once)
            self.assertEqual(once.count('// "poll_slack"'), 1)
        finally:
            os.unlink(path)

    def test_leaves_a_project_that_names_a_profile(self):
        original = '{\n  "autobot": "gete-jira"\n}\n'
        path = write_temp(original)
        try:
            self.assertEqual(main(["tool", path]), 0)
            self.assertEqual(read(path), original)
        finally:
            os.unlink(path)

    def test_leaves_an_explicit_null(self):
        original = '{\n  "autobot": null\n}\n'
        path = write_temp(original)
        try:
            self.assertEqual(main(["tool", path]), 0)
            self.assertEqual(read(path), original)
        finally:
            os.unlink(path)

    def test_seeds_the_whole_block_when_the_key_is_absent(self):
        path = write_temp('{\n  "harness": "opencode"\n}\n')
        try:
            self.assertEqual(main(["tool", path]), 0)
            text = read(path)
            self.assertIn('// "slack_bot_token": "${SLACK_BOT_TOKEN}",', text)
            self.assertIn("autobot", load_jsonc(path))
        finally:
            os.unlink(path)

    def test_preserves_comments_and_key_order(self):
        original = (
            "{\n"
            "  // the harness\n"
            '  "harness": "opencode",\n'
            '  "autobot": {\n'
            "    // what to poll\n"
            '    "poll_jira": true,\n'
            '    "prompts": []\n'
            "  }\n"
            "}\n"
        )
        path = write_temp(original)
        try:
            self.assertEqual(main(["tool", path]), 0)
            text = read(path)
            self.assertIn("// the harness", text)
            self.assertIn("// what to poll", text)
            self.assertLess(text.index("// what to poll"), text.index('// "poll_slack"'))
        finally:
            os.unlink(path)

    def test_adds_the_keys_when_a_value_carries_their_names(self):
        original = (
            "{\n"
            '  "autobot": {\n'
            '    "jira_assignees": ["poll_slack", "slack_user_email", "slack_bot_token"]\n'
            "  }\n"
            "}\n"
        )
        path = write_temp(original)
        try:
            self.assertEqual(main(["tool", path]), 0)
            text = read(path)
            self.assertIn('// "poll_slack": false,', text)
            self.assertIn('// "slack_bot_token": "${SLACK_BOT_TOKEN}",', text)
            self.assertEqual(
                load_jsonc(path)["autobot"]["jira_assignees"],
                ["poll_slack", "slack_user_email", "slack_bot_token"],
            )
        finally:
            os.unlink(path)

    def test_leaves_a_multiline_commented_key_list_alone(self):
        original = (
            "{\n"
            '  "autobot": {\n'
            "    /*\n"
            '     * "poll_slack": false,\n'
            '     * "slack_user_email": "a@b.c",\n'
            '     * "slack_bot_token": "${X}",\n'
            "     */\n"
            '    "poll_jira": true\n'
            "  }\n"
            "}\n"
        )
        path = write_temp(original)
        try:
            self.assertEqual(main(["tool", path]), 0)
            self.assertEqual(read(path), original)
        finally:
            os.unlink(path)

    def test_preserves_the_file_mode(self):
        path = write_temp('{\n  "autobot": {"poll_jira": true}\n}\n')
        try:
            os.chmod(path, 0o644)
            self.assertEqual(main(["tool", path]), 0)
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o644)
        finally:
            os.unlink(path)

    def test_keeps_a_shared_mode(self):
        path = write_temp('{\n  "autobot": {"poll_jira": true}\n}\n')
        try:
            os.chmod(path, 0o664)
            self.assertEqual(main(["tool", path]), 0)
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o664)
        finally:
            os.unlink(path)

    def test_refuses_a_read_only_config(self):
        original = '{\n  "autobot": {"poll_jira": true}\n}\n'
        path = write_temp(original)
        try:
            os.chmod(path, 0o444)
            self.assertEqual(main(["tool", path]), 1)
            self.assertEqual(read(path), original)
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o444)
        finally:
            os.chmod(path, 0o644)
            os.unlink(path)

    def test_fails_on_a_missing_file(self):
        self.assertEqual(main(["tool", "/nonexistent/config.jsonc"]), 1)

    def test_fails_without_a_top_level_object(self):
        path = write_temp("null")
        try:
            self.assertEqual(main(["tool", path]), 1)
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()
