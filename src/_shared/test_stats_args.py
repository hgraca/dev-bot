#!/usr/bin/env python3
"""Unit tests for the shared stats argument normalisation helpers."""
import unittest

from stats_args import (
    bash_value,
    is_sensitive_name,
    mask_argv,
    redact_secrets,
    strip_leading_cd,
    tool_arg_value,
)


class BashValueTest(unittest.TestCase):
    def test_plain_command_keeps_first_two_tokens(self):
        self.assertEqual(bash_value("make test 2>&1 | tail -40"), "make test")

    def test_cd_ampersand_prefix_is_stripped(self):
        self.assertEqual(bash_value("cd /x && git status --short"), "git status")

    def test_cd_newline_prefix_is_stripped(self):
        self.assertEqual(bash_value("cd /x\ngit status --short"), "git status")

    def test_repeated_cd_is_stripped(self):
        self.assertEqual(bash_value("cd /a && cd /b && make test"), "make test")

    def test_cd_semicolon_prefix_is_stripped(self):
        self.assertEqual(bash_value("cd /x; git status"), "git status")

    def test_leading_comment_lines_are_skipped(self):
        self.assertEqual(bash_value("# Check things\ngit status"), "git status")

    def test_leading_blank_lines_are_skipped(self):
        self.assertEqual(bash_value("\n\n  git status"), "git status")

    def test_bare_cd_only_yields_empty(self):
        self.assertEqual(bash_value("cd /x"), "")

    def test_empty_and_none_yield_empty(self):
        self.assertEqual(bash_value(""), "")
        self.assertEqual(bash_value(None), "")


class StripLeadingCdTest(unittest.TestCase):
    def test_no_cd_is_unchanged(self):
        self.assertEqual(strip_leading_cd("git status"), "git status")

    def test_cd_ampersand_is_stripped(self):
        self.assertEqual(strip_leading_cd("cd /x && git status"), "git status")

    def test_bare_cd_is_unchanged(self):
        self.assertEqual(strip_leading_cd("cd /x"), "cd /x")


class RedactSecretsTest(unittest.TestCase):
    def test_key_value_credential_is_masked(self):
        self.assertNotIn("supersecret", redact_secrets("export TOKEN=supersecret"))
        self.assertIn("TOKEN=***", redact_secrets("export TOKEN=supersecret"))

    def test_quoted_password_is_masked(self):
        out = redact_secrets('connect password="hunter2" now')
        self.assertNotIn("hunter2", out)

    def test_bearer_token_is_masked_with_its_scheme(self):
        out = redact_secrets('curl -H "Authorization: Bearer abc123" http://x')
        self.assertNotIn("abc123", out)
        self.assertIn("Bearer ***", out)

    def test_a_single_hyphen_header_key_is_masked(self):
        # `X-Api-Key` follows a hyphen but is a header, not a CLI flag — the
        # `--`-only guard must not skip it.
        out = redact_secrets('curl -H "X-Api-Key: abc123" http://x')
        self.assertNotIn("abc123", out)

    def test_basic_credentials_are_masked(self):
        out = redact_secrets('authorization: Basic dXNlcjpwYXNz')
        self.assertNotIn("dXNlcjpwYXNz", out)
        self.assertIn("Basic ***", out)

    def test_a_bare_bearer_token_is_masked(self):
        self.assertNotIn("abc123", redact_secrets("Bearer abc123"))

    def test_url_credentials_are_masked(self):
        out = redact_secrets("psql postgres://admin:hunter2@db.local/x")
        self.assertNotIn("hunter2", out)
        self.assertIn("postgres://***@", out)

    def test_long_opaque_blob_is_masked(self):
        blob = "AKIAIOSFODNN7EXAMPLEabcdefghijklmnop"
        self.assertNotIn(blob, redact_secrets("key " + blob))

    def test_separate_token_option_value_is_masked(self):
        out = redact_secrets("deploy --token supersecret --region eu")
        self.assertNotIn("supersecret", out)
        self.assertIn("--token ***", out)
        self.assertIn("--region eu", out)

    def test_a_harmless_key_option_is_left_alone(self):
        text = "project-for-path /home/x --key modules"
        self.assertEqual(redact_secrets(text), text)

    def test_ordinary_text_is_untouched(self):
        text = "SELECT id FROM users WHERE email = 'a@b.c'"
        self.assertEqual(redact_secrets(text), text)

    def test_tool_arg_value_redacts_before_capping(self):
        self.assertNotIn("supersecret", tool_arg_value("deploy --token=supersecret"))


class SensitiveNamesTest(unittest.TestCase):
    def test_credential_names_are_sensitive(self):
        for name in ("password", "api_key", "apiKey", "client-secret", "Authorization"):
            self.assertTrue(is_sensitive_name(name), name)

    def test_ordinary_names_are_not(self):
        for name in ("query", "sql", "path", "metricName", ""):
            self.assertFalse(is_sensitive_name(name), name)


class MaskArgvTest(unittest.TestCase):
    def test_the_value_after_a_secret_option_is_masked(self):
        self.assertEqual(
            mask_argv(["--token", "supersecret", "--region", "eu"]),
            "--token *** --region eu",
        )

    def test_an_equals_form_is_left_to_the_pattern(self):
        self.assertEqual(mask_argv(["--token=abc"]), "--token=abc")

    def test_harmless_options_keep_their_values(self):
        self.assertEqual(mask_argv(["--key", "modules"]), "--key modules")

    def test_non_list_yields_empty(self):
        self.assertEqual(mask_argv(None), "")


class ToolArgValueTest(unittest.TestCase):
    def test_whitespace_is_collapsed(self):
        self.assertEqual(tool_arg_value("a  b\n\tc"), "a b c")

    def test_short_value_is_unchanged(self):
        self.assertEqual(tool_arg_value("project = ARC"), "project = ARC")

    def test_long_value_is_capped_with_ellipsis(self):
        result = tool_arg_value("x" * 200)
        self.assertEqual(len(result), 80)
        self.assertTrue(result.endswith("…"))

    def test_cap_boundary_is_exact(self):
        self.assertEqual(tool_arg_value("x" * 80), "x" * 80)

    def test_non_string_yields_empty(self):
        self.assertEqual(tool_arg_value(None), "")
        self.assertEqual(tool_arg_value(["a"]), "")
        self.assertEqual(tool_arg_value({"a": 1}), "")


if __name__ == "__main__":
    unittest.main()
