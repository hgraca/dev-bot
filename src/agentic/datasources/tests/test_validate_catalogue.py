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
import subprocess
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from unittest import mock

MODULE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, MODULE_DIR)

import validate_catalogue  # noqa: E402
from validate_catalogue import (  # noqa: E402
    CanaryResult,
    ValidationError,
    _is_ready,
    _run,
    culprit_reason,
    docker_canary,
    parse_culprit,
    redact,
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
        self.assertEqual([name for name, *_ in rejected], ["a", "c"])

    def test_an_inconclusive_run_probes_each_source_individually(self):
        # A driver with no dial timeout of its own never becomes ready and
        # names nobody. The run is inconclusive, but the sources are still
        # judged: the one that cannot initialize on its own is dropped and the
        # rest are kept — rather than aborting the render.
        calls = []

        def canary(candidate):
            calls.append(sorted(candidate))
            if len(candidate) > 1 or "hang" in candidate:
                return CanaryResult(accepted=False, error="did not become ready")
            return CanaryResult(accepted=True)

        accepted, rejected = validate({"hang": {}, "good": {}}, canary)

        self.assertEqual(list(accepted), ["good"])
        self.assertEqual([name for name, _ in rejected], ["hang"])
        self.assertEqual(calls[0], ["good", "hang"])
        self.assertEqual(sorted(calls[1:]), [["good"], ["hang"]])

    def test_a_single_unready_source_is_dropped(self):
        def canary(candidate):
            return CanaryResult(
                accepted=False,
                error="toolbox did not become ready within 10s",
            )

        accepted, rejected = validate({"hang": {}}, canary)

        self.assertEqual(accepted, {})
        self.assertEqual(rejected, [("hang", "toolbox did not become ready within 10s")])

    def test_an_infra_failure_is_never_attributed_to_a_source(self):
        # docker unreachable, or the canary would not start: no evidence about
        # any source, so nothing may be dropped and the render must abort.
        def canary(candidate):
            return CanaryResult(
                accepted=False,
                error="could not start the toolbox canary",
                infra=True,
            )

        with self.assertRaises(ValidationError):
            validate({"a": {}, "b": {}}, canary)

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

    def test_a_config_error_is_fatal(self):
        # A config toolbox cannot even parse is a renderer bug, not a source to
        # drop silently — including on a single-source candidate, where the
        # failure would otherwise look like that source being unusable.
        def canary(_candidate):
            return CanaryResult(
                accepted=False,
                error="unable to parse config file at /app/conf",
                config_error=True,
            )

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


class TestRedact(unittest.TestCase):
    def test_masks_uri_credentials(self):
        masked = redact("failed: mongodb://user:s3cr3t@db.example:27017/app")

        self.assertNotIn("s3cr3t", masked)
        self.assertIn("user:***@", masked)

    def test_masks_password_parameters(self):
        masked = redact("auth failed (password=hunter2 host=x)")

        self.assertNotIn("hunter2", masked)
        self.assertIn("password=***", masked)

    def test_leaves_a_clean_reason_alone(self):
        self.assertEqual(
            redact("dial tcp 127.0.0.1:1: connection refused"),
            "dial tcp 127.0.0.1:1: connection refused",
        )

    def test_empty_input(self):
        self.assertEqual(redact(""), "")


class TestRun(unittest.TestCase):
    def test_a_fast_command_returns_its_result(self):
        result = _run(["true"], timeout=5)

        assert result is not None
        self.assertEqual(result.returncode, 0)

    def test_a_hanging_command_times_out_to_none(self):
        # A wedged daemon must surface as a value, not hang the caller forever.
        self.assertIsNone(_run(["sleep", "5"], timeout=0.2))


class FakeDocker:
    """A scripted docker CLI, so the canary lifecycle is testable without one."""

    def __init__(
        self,
        *,
        run_rc=0,
        run_none=False,
        inspect="true",
        inspect_none=False,
        logs="",
        ps_output="",
    ):
        self.run_rc = run_rc
        self.run_none = run_none
        self.inspect = inspect
        self.inspect_none = inspect_none
        self.logs = logs
        self.ps_output = ps_output
        self.commands = []

    def __call__(self, args):
        self.commands.append(list(args))
        action = args[1] if len(args) > 1 else ""
        if action == "run":
            return None if self.run_none else subprocess.CompletedProcess(
                args, self.run_rc, "", "boom"
            )
        if action == "inspect":
            return None if self.inspect_none else subprocess.CompletedProcess(
                args, 0, self.inspect, ""
            )
        if action == "logs":
            return subprocess.CompletedProcess(args, 0, self.logs, "")
        if action == "ps":
            return subprocess.CompletedProcess(args, 0, self.ps_output, "")
        return subprocess.CompletedProcess(args, 0, "", "")


class TestDockerCanaryLifecycle(unittest.TestCase):
    def _canary(self, runner, timeout=0.4):
        return docker_canary(
            "x", image="img", version="1", env_names=[], timeout=timeout, runner=runner
        )

    def _removed(self, fake):
        return any(len(c) > 1 and c[1] == "rm" and "-f" in c for c in fake.commands)

    def test_a_failed_start_is_reported_and_cleaned_up(self):
        fake = FakeDocker(run_rc=1)

        result = self._canary(fake)

        self.assertFalse(result.accepted)
        self.assertIn("could not start", result.error or "")
        self.assertTrue(self._removed(fake), "docker rm -f was not called")

    def test_a_start_timeout_is_reported(self):
        fake = FakeDocker(run_none=True)

        result = self._canary(fake)

        self.assertFalse(result.accepted)
        self.assertIn("did not return", result.error or "")
        self.assertTrue(self._removed(fake))

    def test_a_culprit_is_named(self):
        fake = FakeDocker(
            inspect="false",
            logs='ERROR "unable to initialize source \\"bad\\": refused"',
        )

        result = self._canary(fake)

        self.assertFalse(result.accepted)
        self.assertEqual(result.culprit, "bad")
        self.assertTrue(self._removed(fake))

    def test_not_ready_within_the_timeout_is_cleaned_up(self):
        # inspect stays "running", so the canary runs out the clock.
        fake = FakeDocker(inspect="true")

        result = self._canary(fake)

        self.assertFalse(result.accepted)
        self.assertIn("did not become ready", result.error or "")
        self.assertTrue(self._removed(fake))

    def test_a_config_parse_error_is_flagged_not_blamed_on_a_source(self):
        # A config the image cannot read is a renderer bug; validate() must be
        # able to tell it apart from a source failure.
        fake = FakeDocker(
            inspect="false",
            logs='ERROR "unable to parse config file at \\"/app/conf\\": bad yaml"',
        )

        result = self._canary(fake)

        self.assertFalse(result.accepted)
        self.assertIsNone(result.culprit)
        self.assertTrue(result.config_error)

    def test_an_unresponsive_daemon_is_reported(self):
        fake = FakeDocker(inspect_none=True)

        result = self._canary(fake)

        self.assertFalse(result.accepted)
        self.assertIn("did not return", result.error or "")
        self.assertTrue(self._removed(fake))

    def test_stale_canaries_are_swept(self):
        fake = FakeDocker(
            ps_output="dev-bot-datasources-canary-999-deadbeef\n",
            inspect="false",
            logs='ERROR "unable to initialize source \\"x\\": refused"',
        )

        self._canary(fake)

        swept = [
            c for c in fake.commands if len(c) > 1 and c[1] == "rm" and c[-1].endswith("deadbeef")
        ]
        self.assertEqual(len(swept), 1)

    def test_canary_names_are_unique_per_run(self):
        names = []
        for _ in range(2):
            fake = FakeDocker(run_rc=1)
            self._canary(fake)
            run = next(c for c in fake.commands if len(c) > 1 and c[1] == "run")
            names.append(run[run.index("--name") + 1])

        self.assertNotEqual(names[0], names[1])

    def test_a_dead_container_is_not_accepted_even_when_readiness_answers(self):
        # The freed scratch port could be answered by another process; a
        # container that has exited must never be reported as accepted.
        fake = FakeDocker(
            inspect="false", logs='ERROR "unable to initialize source \\"x\\": refused"'
        )
        with mock.patch.object(validate_catalogue, "_is_ready", return_value=True):
            result = self._canary(fake)

        self.assertFalse(result.accepted)

    def test_the_culprit_comes_from_the_fatal_line_not_an_earlier_error(self):
        # Another error may precede the fatal one; the culprit must be taken
        # from `unable to initialize source "..."`, and the reason from that
        # same line, not from whatever the driver logged first.
        fake = FakeDocker(
            inspect="false",
            logs=(
                'WARN "earlier: Error 1129, host is blocked because of many connection errors"\n'
                'ERROR "unable to initialize source \\"prod\\": refused"'
            ),
        )

        result = self._canary(fake)

        self.assertEqual(result.culprit, "prod")
        self.assertIn("refused", result.error or "")
        self.assertNotIn("1129", result.error or "")


class TestIsReady(unittest.TestCase):
    def test_ignores_an_environment_proxy(self):
        # render.sh exports .env into this process, so a proxy set there must
        # not capture the loopback health check.
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200 if self.path == "/healthz" else 404)
                self.end_headers()

            def log_message(self, format, *args):  # noqa: A002 (base signature)
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            with mock.patch.dict(
                os.environ,
                {
                    "http_proxy": "http://127.0.0.1:1",
                    "HTTP_PROXY": "http://127.0.0.1:1",
                },
            ):
                self.assertTrue(_is_ready(server.server_address[1], timeout=2))
        finally:
            server.shutdown()

    def test_a_closed_port_is_not_ready(self):
        self.assertFalse(_is_ready(1, timeout=0.5))


if __name__ == "__main__":
    unittest.main()
