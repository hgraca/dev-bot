#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/tests/test_validate_catalogue.py
# Unit tests for the oracle validator.
#
# The toolbox image is never run here: validate() takes the canary as a
# parameter, so a scripted fake drives every branch deterministically. The
# container itself is exercised by the committed e2e.
# =============================================================================

import io
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
    _parse_args,
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
    """A scripted canary: rejects the named sources, accepts every other one.

    Rejection is keyed on the source NAME, never on call order — validate()
    asks about every source at once, so the order the calls arrive in is not
    deterministic. `calls` is locked for the same reason.
    """

    def __init__(self, reject=None):
        self.reject = set(reject or [])
        self.calls = []
        self._lock = threading.Lock()

    def __call__(self, candidate):
        with self._lock:
            self.calls.append(sorted(candidate))
        name = next(iter(candidate))
        if name in self.reject:
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

    def test_each_source_is_judged_on_its_own(self):
        # Sources are independent, so every one of them gets its own
        # single-source canary — that is what makes each verdict attributable,
        # with no culprit to parse out of a combined failure.
        canary = FakeCanary()
        catalogue = {"a": {}, "b": {}, "c": {}}

        validate(catalogue, canary)

        self.assertEqual(sorted(canary.calls), [["a"], ["b"], ["c"]])

    def test_drops_the_sources_the_oracle_rejects(self):
        catalogue = {"a": {}, "bad": {}, "b": {}}
        canary = FakeCanary(reject=["bad"])

        accepted, rejected = validate(catalogue, canary)

        self.assertEqual(sorted(accepted), ["a", "b"])
        self.assertEqual([name for name, _ in rejected], ["bad"])
        self.assertEqual(rejected[0][1], "refused")

    def test_drops_several_sources(self):
        catalogue = {"a": {}, "b": {}, "c": {}}
        canary = FakeCanary(reject=["a", "c"])

        accepted, rejected = validate(catalogue, canary)

        self.assertEqual(list(accepted), ["b"])
        self.assertEqual([name for name, _ in rejected], ["a", "c"])

    def test_a_source_that_never_becomes_ready_is_dropped(self):
        # A driver with no dial timeout of its own never reaches readiness and
        # names nobody — that is still only that source's problem, and it does
        # not take the render down with it.
        def canary(candidate):
            if "hang" in candidate:
                return CanaryResult(
                    accepted=False, error="toolbox did not become ready within 2s"
                )
            return CanaryResult(accepted=True)

        accepted, rejected = validate({"hang": {}, "good": {}}, canary)

        self.assertEqual(list(accepted), ["good"])
        self.assertEqual([name for name, _ in rejected], ["hang"])

    def test_verdicts_are_reported_in_catalogue_order(self):
        # The canaries finish in whatever order the threads do; the report must
        # not, or the boot output would reorder itself run to run.
        def canary(candidate):
            name = next(iter(candidate))
            return CanaryResult(accepted=False, error=f"{name} refused")

        _, rejected = validate({"a": {}, "b": {}, "c": {}}, canary)

        self.assertEqual([name for name, _ in rejected], ["a", "b", "c"])

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

    def test_masks_a_password_in_a_dumped_config(self):
        # toolbox pretty-prints the offending document when it cannot parse a
        # config, which echoes a LITERAL password from the catalogue. That dump
        # becomes the render's error message, so it has to be masked here.
        masked = redact("  6 | password: hunter2\n  7 | queryParams: timeout=1s")

        self.assertNotIn("hunter2", masked)
        self.assertIn("password: ***", masked)
        # The rest of the dump is diagnostics, and stays.
        self.assertIn("queryParams: timeout=1s", masked)

    def test_leaves_a_reference_visible(self):
        # A ${VAR} is a reference, not a secret — and seeing it says the render
        # did the right thing.
        self.assertEqual(
            redact("password: ${MYSQL_PASSWORD}"), "password: ${MYSQL_PASSWORD}"
        )

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
        # The sweep is a separate step now, run once before the canaries start:
        # per-canary it would remove a concurrently-running sibling's container
        # the moment that sibling exited, before it had read its own logs.
        fake = FakeDocker(ps_output="dev-bot-datasources-canary-999-deadbeef\n")

        validate_catalogue._sweep_stale_canaries(fake, "docker")

        swept = [
            c for c in fake.commands if len(c) > 1 and c[1] == "rm" and c[-1].endswith("deadbeef")
        ]
        self.assertEqual(len(swept), 1)

    def test_the_canary_itself_never_sweeps(self):
        # A canary must not touch its siblings' containers.
        fake = FakeDocker(inspect="false", logs="nothing useful")

        self._canary(fake)

        self.assertEqual([c for c in fake.commands if c[:2] == ["docker", "ps"]], [])

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


class TestDockerCanaryNetworking(unittest.TestCase):
    """The canary's network mode follows the platform: host networking on
    Linux, a published loopback port on macOS, where Docker Desktop cannot do
    host networking."""

    def _run_args(self, platform):
        fake = FakeDocker(run_rc=1)
        with mock.patch.dict(os.environ, {"DATASOURCES_PLATFORM": platform}):
            docker_canary(
                "x", image="img", version="1", env_names=[], timeout=0.4, runner=fake
            )
        return next(c for c in fake.commands if len(c) > 1 and c[1] == "run")

    def test_linux_uses_host_networking(self):
        run = self._run_args("linux")

        self.assertIn("--network", run)
        self.assertIn("host", run)
        self.assertIn("127.0.0.1", run)

    def test_macos_publishes_a_loopback_port(self):
        run = self._run_args("darwin")

        self.assertNotIn("--network", run)
        self.assertTrue(any(a.startswith("-p") for a in run), run)
        self.assertIn("0.0.0.0", run)


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


class TestSidecarPassthrough(unittest.TestCase):
    """A sidecar never reaches the toolbox oracle."""

    def test_a_sidecar_only_catalogue_passes_through_without_docker(self):
        # A sidecar runs in its own container, so a broken one cannot take the
        # shared gateway down — the canary's reason does not apply. With no
        # engines, main() must not consult docker at all.
        import json

        catalogue = {"search": {"type": "opensearch", "env": {}}}
        proc = subprocess.run(
            [sys.executable, os.path.join(MODULE_DIR, "validate_catalogue.py")],
            input=json.dumps(catalogue),
            capture_output=True,
            text=True,
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout), catalogue)


class TestAnnounceImagePull(unittest.TestCase):
    """The canary's `docker run` pulls a missing image; say so before it starts."""

    def _stderr_of(self, daemon, probe):
        # Both probes go through the module's bounded _run; None means it hit
        # DOCKER_TIMEOUT, which the announcement must treat as inconclusive.
        with mock.patch("validate_catalogue._run", side_effect=[daemon, probe]):
            buffer = io.StringIO()
            with mock.patch("sys.stderr", new=buffer):
                validate_catalogue._announce_image_pull("toolbox", "1.2.3")
        return buffer.getvalue()

    @staticmethod
    def _proc(returncode):
        return subprocess.CompletedProcess([], returncode)

    def test_warns_when_the_image_is_absent(self):
        output = self._stderr_of(self._proc(0), self._proc(1))

        self.assertIn("toolbox:1.2.3 not present locally", output)
        self.assertIn("downloading now", output)

    def test_is_silent_when_the_image_is_present(self):
        self.assertEqual(self._stderr_of(self._proc(0), self._proc(0)), "")

    def test_is_silent_when_the_daemon_is_unreachable(self):
        # `image inspect` fails for a dead daemon just as for a missing image,
        # but nothing can be downloaded — announcing one would hide the real
        # infra failure the canary reports.
        self.assertEqual(self._stderr_of(self._proc(1), self._proc(1)), "")

    def test_is_silent_when_the_daemon_probe_times_out(self):
        self.assertEqual(self._stderr_of(None, None), "")

    def test_is_silent_when_the_image_probe_times_out(self):
        # A wedged socket is inconclusive, not "absent": compose reports it.
        self.assertEqual(self._stderr_of(self._proc(0), None), "")


class TestSkipCanary(unittest.TestCase):
    """--skip-canary renders without the toolbox, for install."""

    def test_engines_pass_through_without_docker(self):
        import json

        catalogue = {
            "scratch": {"type": "sqlite", "env": {"SQLITE_DATABASE": "/data/x.db"}}
        }
        # No docker on PATH: without the skip this is an infra error, because
        # install must never need a daemon or download the image.
        environment = dict(os.environ, PATH="/nonexistent")
        proc = subprocess.run(
            [
                sys.executable,
                os.path.join(MODULE_DIR, "validate_catalogue.py"),
                "--skip-canary",
            ],
            input=json.dumps(catalogue),
            capture_output=True,
            text=True,
            env=environment,
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout), catalogue)
        self.assertIn("validation skipped", proc.stderr)


class TestReadinessBudget(unittest.TestCase):
    """The default must stay far above every dial bound the render declares.

    A budget shorter than the dial bound pre-empts the driver, and the reason
    degrades from a named `i/o timeout` to "did not become ready within Ns" —
    which is the unattributable verdict the budget exists to avoid.
    """

    def _dial_bound_seconds(self):
        from render_tools_yaml import ENGINES

        found = []
        for engine in ENGINES.values():
            # The SQL engines declare it in queryParams — a Go duration for
            # MySQL, seconds for pgx. MongoDB's rides inside the URI, in ms.
            for key, value in (engine.get("query_params") or {}).items():
                if key in ("timeout", "connect_timeout"):
                    found.append(float(str(value).rstrip("s")))
            for key, value in (engine.get("uri_timeout_params") or {}).items():
                if key.endswith("MS"):
                    found.append(float(value) / 1000.0)
        return found

    def test_default_comfortably_exceeds_every_engine_dial_bound(self):
        dial = self._dial_bound_seconds()
        self.assertTrue(dial, "no dial bound found — the engine table changed")
        self.assertGreaterEqual(validate_catalogue.DEFAULT_TIMEOUT, 3 * max(dial))


class TestTimeoutArgument(unittest.TestCase):
    """An override cannot be allowed to defeat what the budget is for."""

    def test_an_override_above_the_default_is_accepted(self):
        self.assertEqual(_parse_args(["--timeout", "20"]), (20.0, False))

    def test_no_override_keeps_the_default(self):
        self.assertEqual(_parse_args([]), (validate_catalogue.DEFAULT_TIMEOUT, False))

    def test_a_non_numeric_value_is_rejected(self):
        for value in ("soon", ""):
            with self.subTest(value=value):
                with self.assertRaises(ValidationError):
                    _parse_args(["--timeout", value])

    def test_a_non_finite_or_non_positive_value_is_rejected(self):
        # `inf` would otherwise build a deadline the poll can never reach, and
        # the render would hang instead of failing.
        for value in ("inf", "-inf", "nan", "0", "-3", "1e400"):
            with self.subTest(value=value):
                with self.assertRaises(ValidationError):
                    _parse_args(["--timeout", value])

    def test_a_value_below_the_default_is_rejected(self):
        # Lowering the budget is the original regression. A datasource's own
        # URI can also declare a driver bound the engine table does not know
        # (mongodb keeps an operator-supplied serverSelectionTimeoutMS), so the
        # default is the only floor that is safe for every source.
        with self.assertRaises(ValidationError) as caught:
            _parse_args(["--timeout", str(validate_catalogue.DEFAULT_TIMEOUT - 1)])
        self.assertIn("may be raised, never lowered", str(caught.exception))

    def test_the_default_itself_is_accepted(self):
        self.assertEqual(
            _parse_args(["--timeout", str(int(validate_catalogue.DEFAULT_TIMEOUT))]),
            (validate_catalogue.DEFAULT_TIMEOUT, False),
        )


if __name__ == "__main__":
    unittest.main()
