#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/tests/test_quarantine.py
# Unit tests for the per-datasource failure state.
#
# Every function takes `now`, so backoff behaviour is exercised without
# sleeping.
# =============================================================================

import json
import os
import sys
import tempfile
import unittest
from unittest import mock

MODULE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, MODULE_DIR)

import quarantine  # noqa: E402


class TestQuarantine(unittest.TestCase):
    def setUp(self):
        self.state = quarantine.load("")
        self.now = 1_000_000.0

    # ── state file ───────────────────────────────────────────────────────────

    def test_a_missing_file_is_an_empty_state(self):
        self.assertEqual(self.state, {"sources": {}, "validated_at": 0.0})

    def test_a_corrupt_file_is_an_empty_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "quarantine.json")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("not json")

            state = quarantine.load(path)

        self.assertEqual(state["sources"], {})

    def test_save_then_load_round_trips(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "nested", "quarantine.json")
            quarantine.record_failure(self.state, "db", "boom", self.now)

            quarantine.save(path, self.state)
            reloaded = quarantine.load(path)

        self.assertEqual(sorted(reloaded["sources"]), ["db"])
        self.assertEqual(reloaded["sources"]["db"]["fails"], 1)

    def test_default_state_path_follows_dev_bot_root(self):
        with mock.patch.dict(os.environ, {"DEV_BOT_ROOT": "/tmp/root"}):
            path = quarantine.default_state_path()

        self.assertEqual(path, "/tmp/root/storage/datasources/quarantine.json")

    # ── parking ──────────────────────────────────────────────────────────────

    def test_a_future_retry_is_held_and_a_past_one_is_due(self):
        quarantine.record_failure(self.state, "db", "boom", self.now)

        self.assertTrue(quarantine.held(self.state, "db", self.now + 1))
        self.assertFalse(quarantine.held(self.state, "db", self.now + quarantine.BASE_DELAY + 1))
        self.assertEqual(quarantine.held_names(self.state, self.now), ["db"])
        self.assertEqual(
            quarantine.due_names(self.state, self.now + quarantine.BASE_DELAY + 1), ["db"]
        )

    def test_an_unknown_source_is_never_held(self):
        self.assertFalse(quarantine.held(self.state, "ghost", self.now))
        self.assertEqual(quarantine.held_names(self.state, self.now), [])

    # ── backoff ──────────────────────────────────────────────────────────────

    def test_the_first_failure_parks_for_the_base_delay(self):
        quarantine.record_failure(self.state, "db", "refused", self.now)

        entry = self.state["sources"]["db"]
        self.assertEqual(entry["fails"], 1)
        self.assertEqual(entry["next_retry"], self.now + quarantine.BASE_DELAY)
        self.assertFalse(entry["blocked"])

    def test_the_delay_doubles_with_each_failure(self):
        quarantine.record_failure(self.state, "db", "refused", self.now)
        quarantine.record_failure(self.state, "db", "refused", self.now)

        entry = self.state["sources"]["db"]
        self.assertEqual(entry["fails"], 2)
        self.assertEqual(entry["next_retry"], self.now + 2 * quarantine.BASE_DELAY)

    def test_the_delay_is_capped(self):
        for _ in range(10):
            quarantine.record_failure(self.state, "db", "refused", self.now)

        entry = self.state["sources"]["db"]
        self.assertEqual(entry["next_retry"], self.now + quarantine.MAX_DELAY)

    def test_a_blocked_host_is_parked_longest_and_labelled(self):
        quarantine.record_failure(
            self.state, "db", "Error 1129: Host 'x' is blocked because of many connection errors", self.now
        )

        entry = self.state["sources"]["db"]
        self.assertTrue(entry["blocked"])
        self.assertEqual(entry["next_retry"], self.now + quarantine.BLOCKED_DELAY)

    def test_an_explicit_blocked_flag_overrides_the_reason(self):
        # The caller holds the raw driver log, where a wrapped 1129 may sit on
        # another line than the extracted reason.
        quarantine.record_failure(self.state, "db", "refused", self.now, blocked=True)

        entry = self.state["sources"]["db"]
        self.assertTrue(entry["blocked"])
        self.assertEqual(entry["next_retry"], self.now + quarantine.BLOCKED_DELAY)

    def test_a_success_clears_the_entry(self):
        quarantine.record_failure(self.state, "db", "refused", self.now)

        self.assertTrue(quarantine.record_success(self.state, "db"))
        self.assertFalse(quarantine.record_success(self.state, "db"))
        self.assertEqual(self.state["sources"], {})

    def test_prune_forgets_an_undeclared_source(self):
        quarantine.record_failure(self.state, "gone", "refused", self.now)
        quarantine.record_failure(self.state, "kept", "refused", self.now)

        removed = quarantine.prune(self.state, ["kept"])

        self.assertEqual(removed, 1)
        self.assertEqual(sorted(self.state["sources"]), ["kept"])

    def test_pruning_a_stale_entry_stops_the_revalidation_loop(self):
        # The stale entry's retry is permanently due; without the prune the
        # poller would re-validate every cycle forever.
        self.state["validated_at"] = self.now
        quarantine.record_failure(self.state, "gone", "refused", self.now)
        later = self.now + quarantine.MAX_DELAY + 1
        # A far-away interval, so only the stale entry can make it due.
        self.assertTrue(quarantine.needs_revalidation(self.state, later, 3600))

        quarantine.prune(self.state, [])

        self.assertFalse(quarantine.needs_revalidation(self.state, later, 3600))

    # ── revalidation trigger ─────────────────────────────────────────────────

    def test_a_due_retry_triggers_revalidation(self):
        self.state["validated_at"] = self.now
        quarantine.record_failure(self.state, "db", "refused", self.now)

        self.assertFalse(quarantine.needs_revalidation(self.state, self.now, 300))
        self.assertTrue(
            quarantine.needs_revalidation(
                self.state, self.now + quarantine.BASE_DELAY + 1, 300
            )
        )

    def test_an_old_validation_triggers_revalidation(self):
        self.state["validated_at"] = self.now

        self.assertFalse(quarantine.needs_revalidation(self.state, self.now + 10, 300))
        self.assertTrue(quarantine.needs_revalidation(self.state, self.now + 301, 300))

    def test_the_cli_reports_due_as_exit_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "quarantine.json")
            state = quarantine.load("")
            state["validated_at"] = self.now
            quarantine.save(path, state)

            with mock.patch.object(sys, "argv", ["quarantine.py", "needs-revalidation", path, "300"]):
                with mock.patch.object(quarantine.time, "time", return_value=self.now + 10):
                    not_due = quarantine.main()
                with mock.patch.object(quarantine.time, "time", return_value=self.now + 301):
                    due = quarantine.main()

        self.assertEqual(not_due, 1)
        self.assertEqual(due, 0)


if __name__ == "__main__":
    unittest.main()
