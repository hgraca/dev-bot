#!/usr/bin/env python3
"""Unit tests for the shared stats argument normalisation helpers."""
import unittest

from stats_args import bash_value, strip_leading_cd


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


if __name__ == "__main__":
    unittest.main()
