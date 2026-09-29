#!/usr/bin/env python3
"""Unit tests for lib/commitparse.py — Conventional Commits and ticket parsing."""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))

import commitparse  # noqa: E402


class TicketTests(unittest.TestCase):
    def test_ticket_in_the_subject_is_extracted(self):
        parsed = commitparse.parse_message("fix TP-7041: trips with 100 and more change requests (#4816)")
        self.assertEqual(parsed["ticket"], "TP-7041")

    def test_ticket_in_the_scope_is_still_extracted(self):
        parsed = commitparse.parse_message("feat(TP-12): add thing")
        self.assertEqual(parsed["ticket"], "TP-12")

    def test_scope_ticket_wins_over_a_subject_ticket(self):
        parsed = commitparse.parse_message("feat(TP-1): follow up on TP-2")
        self.assertEqual(parsed["ticket"], "TP-1")

    def test_no_ticket_leaves_it_empty(self):
        parsed = commitparse.parse_message("feat(route-prediction): name the endpoints")
        self.assertEqual(parsed["ticket"], "")

    def test_pr_number_is_not_a_ticket(self):
        parsed = commitparse.parse_message("feat: migration fix (#4817)")
        self.assertEqual(parsed["ticket"], "")

    def test_standards_tokens_are_not_tickets(self):
        for subject in (
            "fix: normalise UTF-8 in the parser",
            "chore(deps): bump SHA-256 handling",
            "docs: mention ISO-8601 timestamps",
            "fix: handle HTTP-2 upgrade",
            "fix: patch CVE-2021-44228",
        ):
            self.assertEqual(commitparse.parse_message(subject)["ticket"], "", subject)

    def test_a_real_ticket_after_a_denied_token_is_still_found(self):
        parsed = commitparse.parse_message("fix: use SHA-256 for TP-7041")
        self.assertEqual(parsed["ticket"], "TP-7041")


class ConventionalTests(unittest.TestCase):
    def test_type_ticket_colon_is_conventional(self):
        parsed = commitparse.parse_message("fix TP-7041: trips with 100 and more change requests (#4816)")
        self.assertTrue(parsed["conventional"])
        self.assertEqual(parsed["type"], "fix")
        self.assertEqual(parsed["ticket"], "TP-7041")
        self.assertEqual(parsed["scope"], "")

    def test_scope_then_ticket_then_breaking(self):
        parsed = commitparse.parse_message("feat(api) TP-1!: drop the v1 endpoint")
        self.assertTrue(parsed["conventional"])
        self.assertEqual(parsed["type"], "feat")
        self.assertEqual(parsed["scope"], "api")
        self.assertEqual(parsed["ticket"], "TP-1")
        self.assertEqual(parsed["breaking"], 1)

    def test_a_missing_colon_stays_non_conventional(self):
        parsed = commitparse.parse_message("feat TP-7040 Add Mexican Peso to supplier currencies")
        self.assertFalse(parsed["conventional"])
        self.assertEqual(parsed["type"], "")
        self.assertEqual(parsed["ticket"], "TP-7040")

    def test_plain_conventional_still_parses(self):
        parsed = commitparse.parse_message("feat(route-prediction): name the endpoints")
        self.assertTrue(parsed["conventional"])
        self.assertEqual(parsed["scope"], "route-prediction")
        self.assertEqual(parsed["ticket"], "")

    def test_unknown_type_is_not_conventional(self):
        parsed = commitparse.parse_message("Booking com genuis ff (#4810)")
        self.assertFalse(parsed["conventional"])


if __name__ == "__main__":
    unittest.main()
