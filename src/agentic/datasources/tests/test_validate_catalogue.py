#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/tests/test_validate_catalogue.py
# Unit tests for the oracle validator.
#
# The toolbox image is never run here: validate() takes the canary as a
# parameter, so a scripted fake drives every branch deterministically. The
# container itself is exercised by the committed e2e.
# =============================================================================

import os
import sys
import unittest

MODULE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, MODULE_DIR)

from validate_catalogue import (  # noqa: E402
    CanaryResult,
    ValidationError,
    culprit_reason,
    parse_culprit,
    validate,
)

# The source name appears escaped in the logger line and plain on the CLI error
# line; toolbox emits both, so the parser must read either.
ESCAPED = r'ERROR "toolbox failed to initialize: unable to initialize source \"bad-mysql\": unable to connect successfully"'
PLAIN = 'Error: toolbox failed to initialize: unable to initialize source "bad-mysql": unable to connect successfully'


class FakeCanary:
    """A scripted canary: rejects the given sources in order, then accepts."""

    def __init__(self, reject=None):
        self.reject = list(reject or [])
        self.calls = []

    def __call__(self, candidate):
        self.calls.append(sorted(candidate))
        if self.reject:
            name = self.reject.pop(0)
            return CanaryResult(accepted=False, culprit=name, error="refused")
        return CanaryResult(accepted=True)


class TestParseCulprit(unittest.TestCase):
    def test_reads_the_plain_cli_line(self):
        self.assertEqual(parse_culprit(PLAIN), "bad-mysql")

    def test_reads_the_escaped_logger_line(self):
        self.assertEqual(parse_culprit(ESCAPED), "bad-mysql")

    def test_returns_none_when_no_source_is_named(self):
        self.assertIsNone(parse_culprit("unable to parse config file at /app/conf"))
        self.assertIsNone(parse_culprit(""))

    def test_reason_is_the_message_after_the_source_name(self):
        self.assertEqual(
            culprit_reason(PLAIN), "unable to connect successfully"
        )

    def test_reason_strips_the_escaped_logger_wrapper(self):
        self.assertEqual(
            culprit_reason(ESCAPED), "unable to connect successfully"
        )

    def test_reason_is_empty_when_no_source_is_named(self):
        self.assertEqual(culprit_reason("unable to parse config file"), "")


class TestValidate(unittest.TestCase):
    def test_accepts_a_working_catalogue(self):
        catalogue = {"a": {}, "b": {}}

        accepted, rejected = validate(catalogue, FakeCanary())

        self.assertEqual(accepted, catalogue)
        self.assertEqual(rejected, [])

    def test_drops_a_named_source_and_retries(self):
        catalogue = {"a": {}, "bad": {}, "b": {}}
        canary = FakeCanary(reject=["bad"])

        accepted, rejected = validate(catalogue, canary)

        self.assertEqual(sorted(accepted), ["a", "b"])
        self.assertEqual([name for name, _ in rejected], ["bad"])
        self.assertEqual(rejected[0][1], "refused")
        # It re-validates the reduced candidate, never the original again.
        self.assertEqual(canary.calls, [["a", "b", "bad"], ["a", "b"]])

    def test_drops_several_sources_in_turn(self):
        catalogue = {"a": {}, "b": {}, "c": {}}
        canary = FakeCanary(reject=["a", "c"])

        accepted, rejected = validate(catalogue, canary)

        self.assertEqual(list(accepted), ["b"])
        self.assertEqual([name for name, _ in rejected], ["a", "c"])

    def test_returns_empty_when_every_source_fails(self):
        catalogue = {"a": {}, "b": {}}

        accepted, rejected = validate(catalogue, FakeCanary(reject=["a", "b"]))

        self.assertEqual(accepted, {})
        self.assertEqual(len(rejected), 2)

    def test_empty_catalogue_needs_no_canary(self):
        canary = FakeCanary()

        accepted, rejected = validate({}, canary)

        self.assertEqual(accepted, {})
        self.assertEqual(rejected, [])
        self.assertEqual(canary.calls, [])

    def test_the_reason_carries_the_toolbox_error(self):
        def canary(candidate):
            if "bad" in candidate:
                return CanaryResult(
                    accepted=False,
                    culprit="bad",
                    error="dial tcp: connect: connection refused",
                )
            return CanaryResult(accepted=True)

        _, rejected = validate({"bad": {}, "good": {}}, canary)

        self.assertIn("connection refused", rejected[0][1])

    def test_a_failure_without_a_culprit_is_fatal(self):
        # A config toolbox cannot even parse is a render bug, not a source to
        # drop silently.
        def canary(_candidate):
            return CanaryResult(accepted=False, error="unable to parse config file")

        with self.assertRaises(ValidationError):
            validate({"a": {}}, canary)

    def test_an_unknown_culprit_is_fatal(self):
        def canary(_candidate):
            return CanaryResult(accepted=False, culprit="ghost")

        with self.assertRaises(ValidationError):
            validate({"a": {}}, canary)

    def test_a_repeated_culprit_terminates(self):
        # Once every source is gone the loop ends; it can never spin.
        accepted, _ = validate({"a": {}}, FakeCanary(reject=["a"]))

        self.assertEqual(accepted, {})

    def test_does_not_mutate_the_input_catalogue(self):
        catalogue = {"a": {}, "b": {}}

        validate(catalogue, FakeCanary(reject=["a"]))

        self.assertEqual(sorted(catalogue), ["a", "b"])


if __name__ == "__main__":
    unittest.main()
