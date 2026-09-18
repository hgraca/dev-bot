#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/validate_catalogue.py
# Validate a candidate catalogue against the REAL gateway.
#
# dev-bot does not open database connections: the pinned toolbox is the only DB
# client, and it is the oracle. This runs the toolbox image once against the
# rendered candidate config and reports what it does:
#
#   * it reaches readiness  -> every source initialized, keep the candidate;
#   * it exits non-zero     -> it names the source it could not initialize
#                              (`unable to initialize source "X"`), so drop X
#                              and try again, bounded by the catalogue size.
#
# That is what makes the filter's invariant true: "usable" now means exactly
# "toolbox can initialize it", and the connections spent deciding are real
# authenticated ones — the only kind that do not advance MariaDB's per-host
# error counter (a successful one resets it), so validating cannot poison a
# database the way the old bare TCP dial did.
#
# Readiness is `/healthz` (toolbox >= 1.8), not a timed guess: a good config
# serves within a second, a bad one exits in about the same time. If neither
# happens within the timeout the result is INCONCLUSIVE and no config is
# published.
#
# A source the oracle rejects is parked in quarantine.json and retried on a
# backoff rather than on every poll — see quarantine.py.
#
# Usage:
#     validate_catalogue.py [--timeout SECONDS] [--state FILE] < catalogue.json
#
# The accepted subset is written as JSON on stdout; each dropped source, with
# the reason toolbox gave, is written to stderr.
# =============================================================================

import http.client
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from typing import Callable, List, Optional, Tuple

import quarantine
from render_tools_yaml import effective_env_names, load_catalogue, render

MODULE_DIR = os.path.dirname(os.path.abspath(__file__))
DEV_BOT_ROOT = os.environ.get("DEV_BOT_ROOT") or os.path.dirname(
    os.path.dirname(os.path.dirname(MODULE_DIR))
)
VERSIONS_FILE = os.path.join(MODULE_DIR, "versions.env")

DEFAULT_TIMEOUT = 10.0
POLL_INTERVAL = 0.25
# Every docker invocation is bounded, so an unresponsive daemon cannot hang the
# render (and with it `devbot up` or the poller).
DOCKER_TIMEOUT = 30.0

# toolbox fails fast on the first source it cannot initialize and names it.
# It appears twice in the logs — escaped inside the logger line
#   ERROR "toolbox failed to initialize: ... unable to initialize source
#   \"bad-mysql\": unable to connect successfully: ..."
# and plain on the CLI error line — so tolerate the optional backslashes.
CULPRIT_RE = re.compile(r'unable to initialize source \\?"([^"\\]+)\\?"')

EXIT_OK = 0
EXIT_INPUT = 1
EXIT_INFRA = 2
EXIT_CONFIG = 3
EXIT_INCONCLUSIVE = 4


class ValidationError(Exception):
    """The candidate could not be validated; `code` says why."""

    def __init__(self, message: str, code: int = EXIT_CONFIG):
        super().__init__(message)
        self.code = code


@dataclass
class CanaryResult:
    """What one toolbox run against a candidate config did."""

    accepted: bool
    culprit: Optional[str] = None
    error: Optional[str] = None
    output: str = ""


def parse_culprit(output: str) -> Optional[str]:
    """The source toolbox named as uninitializable, or None."""
    match = CULPRIT_RE.search(output or "")
    return match.group(1) if match else None


def culprit_reason(output: str) -> str:
    """The message toolbox gave for the named source, for the poller log."""
    for line in (output or "").splitlines():
        match = CULPRIT_RE.search(line)
        if match:
            reason = line[match.end() :].strip().lstrip(": ").rstrip('"\\').strip()
            if reason:
                return reason
    return ""


def validate(
    catalogue: dict, run_canary: Callable[[dict], CanaryResult]
) -> Tuple[dict, List[Tuple[str, str]]]:
    """Return (accepted catalogue, [(rejected name, reason), ...]).

    `run_canary(candidate)` must run the oracle against a candidate and report
    the result; injecting it is what makes this unit-testable without docker.
    Each round drops exactly one source, so the loop is bounded by the
    catalogue size — it can never spin.
    """
    candidate = dict(catalogue)
    rejected: List[Tuple[str, str]] = []
    max_rounds = len(catalogue) + 1

    for _ in range(max_rounds):
        if not candidate:
            return {}, rejected

        result = run_canary(candidate)
        if result.accepted:
            return candidate, rejected

        if result.culprit is None:
            raise ValidationError(
                result.error or "toolbox refused the config without naming a source"
            )
        if result.culprit not in candidate:
            raise ValidationError(
                f"toolbox named '{result.culprit}', which is not in the catalogue"
            )

        reason = result.error or "toolbox could not initialize it"
        del candidate[result.culprit]
        rejected.append((result.culprit, reason))

    raise ValidationError("toolbox kept rejecting the config; giving up")


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _is_ready(port: int, timeout: float = 0.5) -> bool:
    """True when the canary answers /healthz with 200.

    Uses http.client rather than urllib on purpose: urllib honours the ambient
    http_proxy / no_proxy, and render.sh exports .env into this process. A
    proxy without 127.0.0.1 in no_proxy would send the loopback check to the
    proxy, time every canary out, and abort every render.
    """
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        connection.request("GET", "/healthz")
        return connection.getresponse().status == 200
    except (OSError, http.client.HTTPException):
        return False
    finally:
        connection.close()


def _run(args: List[str], timeout: float = DOCKER_TIMEOUT) -> Optional[subprocess.CompletedProcess]:
    """Run a docker command, returning None if it does not finish in time.

    Every call is bounded: a wedged daemon must not hang `devbot up` or stall
    the refresh poller.
    """
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


def docker_canary(
    tools_yaml: str,
    *,
    image: str,
    version: str,
    env_names: List[str],
    timeout: float,
    data_dir: Optional[str] = None,
    docker: str = "docker",
) -> CanaryResult:
    """Run the pinned toolbox against `tools_yaml` and report the outcome.

    The container is started detached, then polled: `/healthz` 200 means the
    server came up, a stopped container means it refused the config. The name
    is unique and the container is always removed, so a timeout cannot leave an
    orphan behind.
    """
    work_dir = tempfile.mkdtemp(prefix="datasources-canary-")
    name = f"dev-bot-datasources-canary-{os.getpid()}"
    port = _free_port()

    try:
        with open(os.path.join(work_dir, "tools.yaml"), "w", encoding="utf-8") as handle:
            handle.write(tools_yaml)

        # Mirror the gateway's own mounts and identity, so the canary's verdict
        # matches what the real container will do (notably sqlite's /data).
        args = [
            docker, "run", "-d", "--name", name, "--network", "host",
            "-v", f"{work_dir}:/app/conf:ro",
        ]
        if data_dir:
            args += ["-v", f"{data_dir}:/data"]
        if hasattr(os, "getuid"):
            args += ["--user", f"{os.getuid()}:{os.getgid()}"]
        for var in env_names:
            if var in os.environ:
                args += ["-e", var]
        args += [
            f"{image}:{version}",
            "--config-folder", "/app/conf",
            "--address", "127.0.0.1",
            "--port", str(port),
            "--allowed-hosts", "127.0.0.1",
            "--allowed-origins", f"http://127.0.0.1:{port}",
            "--disable-version-check",
        ]

        started = _run(args)
        if started is None:
            return CanaryResult(
                accepted=False,
                error=f"docker run did not return within {DOCKER_TIMEOUT:.0f}s",
            )
        if started.returncode != 0:
            return CanaryResult(
                accepted=False,
                error=f"could not start the toolbox canary: {started.stderr.strip()}",
            )

        deadline = time.monotonic() + timeout
        exited = False
        while time.monotonic() < deadline:
            if _is_ready(port):
                return CanaryResult(accepted=True)
            state = _run([docker, "inspect", "-f", "{{.State.Running}}", name])
            if state is None:
                return CanaryResult(
                    accepted=False,
                    error="docker inspect did not return; the daemon may be unresponsive",
                )
            if state.returncode != 0 or state.stdout.strip() != "true":
                exited = True
                break
            time.sleep(POLL_INTERVAL)

        if not exited:
            return CanaryResult(
                accepted=False,
                error=f"toolbox did not become ready within {timeout:.0f}s",
            )

        logs = _run([docker, "logs", name])
        output = "" if logs is None else (logs.stdout or "") + (logs.stderr or "")
        culprit = parse_culprit(output)
        if culprit:
            return CanaryResult(
                accepted=False,
                culprit=culprit,
                error=culprit_reason(output),
                output=output,
            )
        return CanaryResult(
            accepted=False,
            error=output.strip()[-2000:] or "toolbox exited without a reason",
            output=output,
        )
    finally:
        _run([docker, "rm", "-f", name])
        shutil.rmtree(work_dir, ignore_errors=True)


def load_versions(path: str) -> dict:
    values = {}
    if not os.path.isfile(path):
        return values
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


def _parse_args(argv: List[str]) -> Tuple[float, str]:
    """(timeout, state path). Fails loudly on anything unexpected."""
    timeout = DEFAULT_TIMEOUT
    state_path = quarantine.default_state_path()
    index = 0
    while index < len(argv):
        flag = argv[index]
        if flag in ("--timeout", "--state") and index + 1 < len(argv):
            value = argv[index + 1]
            if flag == "--timeout":
                try:
                    timeout = float(value)
                except ValueError:
                    raise ValidationError(f"invalid timeout: {value}", EXIT_INPUT)
            else:
                state_path = value
            index += 2
        else:
            raise ValidationError(
                "usage: validate_catalogue.py [--timeout SECONDS] [--state FILE]",
                EXIT_INPUT,
            )
    return timeout, state_path


def main() -> int:
    try:
        timeout, state_path = _parse_args(sys.argv[1:])
    except ValidationError as exc:
        sys.stderr.write(f"ERROR: {exc}\n")
        return exc.code

    catalogue = load_catalogue(sys.stdin.read())
    state = quarantine.load(state_path)
    now = time.time()

    # A source removed or renamed in the config must not keep its old entry: the
    # entry's retry is permanently due, which would peg the poller to a
    # re-validation every cycle.
    quarantine.prune(state, catalogue)

    # Nothing declared, or nothing survived the env filter: record the
    # validation time so the poller settles, and emit the empty catalogue.
    if not catalogue:
        state["validated_at"] = now
        quarantine.save(state_path, state)
        sys.stdout.write("{}\n")
        return EXIT_OK

    versions = load_versions(VERSIONS_FILE)
    image = versions.get("TOOLBOX_IMAGE")
    version = versions.get("TOOLBOX_VERSION")
    if not image or not version:
        sys.stderr.write(
            f"ERROR: cannot read TOOLBOX_IMAGE/TOOLBOX_VERSION from {VERSIONS_FILE}\n"
        )
        return EXIT_INFRA

    if shutil.which("docker") is None:
        sys.stderr.write("ERROR: docker not found; cannot validate the catalogue\n")
        return EXIT_INFRA

    # A parked source is neither offered nor re-tested until its backoff
    # expires — that is what keeps a down database from costing a container run
    # on every poll.
    held = quarantine.held_names(state, now)
    for name in held:
        reason = state["sources"][name].get("reason", "")
        sys.stderr.write(f"INFO: datasource '{name}' is quarantined — {reason}\n")
    attempt = {name: spec for name, spec in catalogue.items() if name not in held}

    if not attempt:
        state["validated_at"] = now
        quarantine.save(state_path, state)
        sys.stdout.write("{}\n")
        return EXIT_OK

    data_dir = os.path.join(DEV_BOT_ROOT, "storage", "datasources", "data")

    def run_canary(candidate: dict) -> CanaryResult:
        return docker_canary(
            render(candidate),
            image=image,
            version=version,
            env_names=effective_env_names(candidate),
            timeout=timeout,
            data_dir=data_dir if os.path.isdir(data_dir) else None,
        )

    try:
        accepted, rejected = validate(attempt, run_canary)
    except ValidationError as exc:
        sys.stderr.write(f"ERROR: {exc}\n")
        return exc.code

    for name, reason in rejected:
        quarantine.record_failure(state, name, reason, now)
    for name in accepted:
        quarantine.record_success(state, name)
    state["validated_at"] = now
    quarantine.save(state_path, state)

    for name, reason in rejected:
        sys.stderr.write(f"INFO: datasource '{name}' is not usable — {reason}\n")
    sys.stdout.write(json.dumps(accepted, indent=2) + "\n")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
