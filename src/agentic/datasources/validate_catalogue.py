#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/validate_catalogue.py
# Validate a candidate catalogue against the REAL gateway.
#
# dev-bot does not open database connections: the pinned toolbox is the only DB
# client, and it is the oracle. Each declared source is run against the image ON
# ITS OWN, in parallel with the others, and what that run does is the verdict:
#
#   * it reaches readiness  -> keep the source;
#   * it exits non-zero     -> drop it, with the reason toolbox gave.
#
# Sources are independent — a source toolbox cannot initialize alone is not one
# the merged config can serve — so a per-source run is equivalent to the
# combined run it replaces, and it makes every verdict attributable without
# parsing `unable to initialize source "X"` out of somebody else's failure.
# Validating all of them at once is what keeps the cost at max(one source)
# rather than sum(N): with a single failing source the combined form burned its
# whole deadline once per source it had to eliminate.
#
# That is what makes the filter's invariant true: "usable" now means exactly
# "toolbox can initialize it", and the connections spent deciding are real
# authenticated ones — the only kind that do not advance MariaDB's per-host
# error counter (a successful one resets it), so validating cannot poison a
# database the way the old bare TCP dial did.
#
# Readiness is `/healthz` (toolbox >= 1.8), not a timed guess: a good config
# serves within a second, a bad one exits in about the same time. A source that
# does neither — a driver with no dial timeout of its own, which is redis
# always and mongodb unless its URI bounds it — has no verdict, but it is
# still only that source's problem: it is dropped and named like any other.
#
# A source the oracle rejects is dropped and named on stderr. There is no
# retry state: the catalogue is evaluated once, at startup, so a rejected
# source is simply not loaded until the next `devbot up`.
#
# Usage:
#     validate_catalogue.py [--timeout SECONDS] < catalogue.json
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
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Tuple

from render_tools_yaml import effective_env_names, load_catalogue, render

MODULE_DIR = os.path.dirname(os.path.abspath(__file__))
DEV_BOT_ROOT = os.environ.get("DEV_BOT_ROOT") or os.path.dirname(
    os.path.dirname(os.path.dirname(MODULE_DIR))
)
VERSIONS_FILE = os.path.join(MODULE_DIR, "versions.env")

# How long one source has to reach readiness. A good config serves within a
# second; a host that blackholes the dial does not, and waiting longer than this
# only delays the boot. Kept deliberately tight — a source that needs longer
# than this is dropped for the session and returns on the next `devbot up`.
DEFAULT_TIMEOUT = 2.0
POLL_INTERVAL = 0.25
# Every docker invocation is bounded, so an unresponsive daemon cannot hang the
# render (and with it `devbot up`).
DOCKER_TIMEOUT = 30.0
# One canary container per source, all at once. Capped so a large catalogue
# cannot turn a boot into a container stampede; the sources beyond the cap run
# in a second wave.
MAX_PARALLEL_CANARIES = 8

# toolbox names the source it could not initialize. It appears twice in the
# logs — escaped inside the logger line
#   ERROR "toolbox failed to initialize: ... unable to initialize source
#   \"bad-mysql\": unable to connect successfully: ..."
# and plain on the CLI error line — so tolerate the optional backslashes. The
# verdict no longer depends on this (every source is asked about on its own);
# it is how the REASON shown to the operator is extracted.
CULPRIT_RE = re.compile(r'unable to initialize source \\?"([^"\\]+)\\?"')

# toolbox refuses a config it cannot read at all — a renderer bug, or a spec
# this image does not accept. That is never a source to blame, and conflating
# the two would publish a broken render as "every datasource is unusable".
CONFIG_ERROR_RE = re.compile(r"unable to parse config file")

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
    # The oracle itself could not run (docker unreachable, the canary would not
    # start). That is a fact about this machine, not about any source, so it
    # must never be read as "the source is unusable".
    infra: bool = False
    # toolbox could not READ the rendered config — a renderer bug. Also never a
    # source to blame.
    config_error: bool = False


def parse_culprit(output: str) -> Optional[str]:
    """The source toolbox named as uninitializable, or None."""
    match = CULPRIT_RE.search(output or "")
    return match.group(1) if match else None


def culprit_reason(output: str) -> str:
    """The message toolbox gave for the named source, for the operator."""
    for line in (output or "").splitlines():
        match = CULPRIT_RE.search(line)
        if match:
            reason = line[match.end() :].strip().lstrip(": ").rstrip('"\\').strip()
            if reason:
                return reason
    return ""


# A rejection reason is driver text copied out of the toolbox log and then
# printed. MongoDB carries its credentials inside the URI, so mask
# credential-shaped fragments before anything is surfaced.
_URI_CREDENTIALS_RE = re.compile(
    r"(?P<scheme>[a-zA-Z][a-zA-Z0-9+.-]*://)(?P<user>[^:/@\s]+):(?P<secret>[^@/\s]+)@"
)
_PASSWORD_PARAM_RE = re.compile(r"(?i)\b(password|passwd|pwd)=\S+")


def redact(text: str) -> str:
    """Mask credentials a driver error may have echoed."""
    if not text:
        return ""
    text = _URI_CREDENTIALS_RE.sub(r"\g<scheme>\g<user>:***@", text)
    return _PASSWORD_PARAM_RE.sub(lambda match: f"{match.group(1)}=***", text)


def validate(
    catalogue: dict, run_canary: Callable[[dict], CanaryResult]
) -> Tuple[dict, List[Tuple[str, str]]]:
    """Return (accepted catalogue, [(rejected name, reason), ...]).

    Every source is judged ON ITS OWN, and all of them at once. Sources are
    independent — one toolbox cannot initialize alone is not one the merged
    config can serve — so a single-source run per source is equivalent to the
    combined run it replaces, and it makes every verdict attributable without
    parsing a culprit out of somebody else's failure. Running them concurrently
    keeps the cost at max(one source) instead of sum(N).

    `run_canary(candidate)` must run the oracle against a candidate and report
    the result; injecting it is what makes this unit-testable without docker.
    """
    if not catalogue:
        return {}, []

    results: Dict[str, CanaryResult] = {}
    with ThreadPoolExecutor(
        max_workers=min(len(catalogue), MAX_PARALLEL_CANARIES)
    ) as pool:
        pending = {
            pool.submit(run_canary, {name: spec}): name
            for name, spec in catalogue.items()
        }
        for future in as_completed(pending):
            results[pending[future]] = future.result()

    # Read the verdicts back in catalogue order, so the reported order is stable
    # however the threads happened to finish.
    accepted: dict = {}
    rejected: List[Tuple[str, str]] = []
    for name, spec in catalogue.items():
        result = results[name]
        if result.accepted:
            accepted[name] = spec
        elif result.infra or result.config_error:
            # No evidence about any source — the oracle could not run, or
            # toolbox could not read the config we rendered. Dropping sources
            # here would mask either as "unusable".
            raise ValidationError(result.error or "the oracle could not run")
        else:
            rejected.append((name, result.error or "toolbox could not initialize it"))
    return accepted, rejected


# Ports handed out so far in this process. `_free_port` closes the socket before
# docker binds the port, so two canaries starting at once could otherwise be
# handed the same one — one of them would fail to start, and a start failure is
# infra, which aborts the whole render. Never reused; the set is bounded by the
# number of canaries one process runs.
_PORT_LOCK = threading.Lock()
_PORTS_TAKEN: set = set()


def _free_port() -> int:
    while True:
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        with _PORT_LOCK:
            if port not in _PORTS_TAKEN:
                _PORTS_TAKEN.add(port)
                return port


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

    Every call is bounded: a wedged daemon must not hang `devbot up`.
    """
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


CANARY_PREFIX = "dev-bot-datasources-canary-"


def _sweep_stale_canaries(runner, docker: str) -> None:
    """Best-effort removal of canaries an earlier run left behind.

    Only STOPPED containers are swept. Called ONCE before the sources are
    validated, never per canary: with the canaries running concurrently, a
    sweep from one of them would remove a sibling that had just exited, before
    that sibling had read its own logs.
    """
    listing = runner(
        [
            docker, "ps", "-a",
            "--filter", f"name={CANARY_PREFIX}",
            "--filter", "status=exited",
            "--format", "{{.Names}}",
        ]
    )
    if listing is None or listing.returncode != 0:
        return
    for stale in (listing.stdout or "").split():
        runner([docker, "rm", "-f", stale])


def docker_canary(
    tools_yaml: str,
    *,
    image: str,
    version: str,
    env_names: List[str],
    timeout: float,
    data_dir: Optional[str] = None,
    docker: str = "docker",
    runner: Callable[[List[str]], Optional[subprocess.CompletedProcess]] = _run,
) -> CanaryResult:
    """Run the pinned toolbox against `tools_yaml` and report the outcome.

    The container is started detached, then polled: `/healthz` 200 means the
    server came up, a stopped container means it refused the config. The name
    is unique and the container is always removed, so a timeout cannot leave an
    orphan behind. `runner` is injected so the lifecycle is unit-testable
    without docker.
    """
    work_dir = tempfile.mkdtemp(prefix="datasources-canary-")
    # A random suffix, not the PID alone: a recycled PID would otherwise make
    # `docker run` fail with "name already in use" and abort every render.
    name = f"{CANARY_PREFIX}{os.getpid()}-{uuid.uuid4().hex[:8]}"
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

        started = runner(args)
        if started is None:
            return CanaryResult(
                accepted=False,
                error=f"docker run did not return within {DOCKER_TIMEOUT:.0f}s",
                infra=True,
            )
        if started.returncode != 0:
            return CanaryResult(
                accepted=False,
                error=f"could not start the toolbox canary: {started.stderr.strip()}",
                infra=True,
            )

        deadline = time.monotonic() + timeout
        exited = False
        while time.monotonic() < deadline:
            state = runner([docker, "inspect", "-f", "{{.State.Running}}", name])
            if state is None:
                return CanaryResult(
                    accepted=False,
                    error="docker inspect did not return; the daemon may be unresponsive",
                    infra=True,
                )
            if state.returncode != 0 or state.stdout.strip() != "true":
                exited = True
                break
            # Only trust /healthz once the container is confirmed running: the
            # freed scratch port could otherwise be answered by an unrelated
            # local process.
            if _is_ready(port):
                return CanaryResult(accepted=True)
            time.sleep(POLL_INTERVAL)

        if not exited:
            return CanaryResult(
                accepted=False,
                error=f"toolbox did not become ready within {timeout:.0f}s",
            )

        logs = runner([docker, "logs", name])
        output = "" if logs is None else (logs.stdout or "") + (logs.stderr or "")
        culprit = parse_culprit(output)
        if culprit:
            return CanaryResult(
                accepted=False,
                culprit=culprit,
                error=redact(culprit_reason(output)),
                output=output,
            )
        return CanaryResult(
            accepted=False,
            error=redact(output.strip()[-2000:]) or "toolbox exited without a reason",
            output=output,
            config_error=CONFIG_ERROR_RE.search(output) is not None,
        )
    finally:
        runner([docker, "rm", "-f", name])
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


def _parse_args(argv: List[str]) -> float:
    """The canary timeout. Fails loudly on anything unexpected."""
    timeout = DEFAULT_TIMEOUT
    index = 0
    while index < len(argv):
        flag = argv[index]
        if flag == "--timeout" and index + 1 < len(argv):
            value = argv[index + 1]
            try:
                timeout = float(value)
            except ValueError:
                raise ValidationError(f"invalid timeout: {value}", EXIT_INPUT)
            index += 2
        else:
            raise ValidationError(
                "usage: validate_catalogue.py [--timeout SECONDS]", EXIT_INPUT
            )
    return timeout


def main() -> int:
    try:
        timeout = _parse_args(sys.argv[1:])
    except ValidationError as exc:
        sys.stderr.write(f"ERROR: {exc}\n")
        return exc.code

    catalogue = load_catalogue(sys.stdin.read())

    # Nothing declared, or nothing survived the env filter: emit the empty
    # catalogue so the render settles on "no toolsets".
    if not catalogue:
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

    data_dir = os.path.join(DEV_BOT_ROOT, "storage", "datasources", "data")

    # Clear leftovers from a run that was killed, once, before the canaries
    # start — see _sweep_stale_canaries for why this cannot be per canary.
    _sweep_stale_canaries(_run, "docker")

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
        accepted, rejected = validate(catalogue, run_canary)
    except ValidationError as exc:
        sys.stderr.write(f"ERROR: {exc}\n")
        return exc.code

    for name, reason in rejected:
        sys.stderr.write(f"INFO: datasource '{name}' is not usable — {reason}\n")
    sys.stdout.write(json.dumps(accepted, indent=2) + "\n")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
