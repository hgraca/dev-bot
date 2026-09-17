#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/available_catalogue.py
# Filter the datasources catalogue down to what is usable RIGHT NOW.
#
# A datasource is usable when every required env var is set and its server is
# reachable. The gateway's config may contain only usable datasources, because
# toolbox initialises sources eagerly and treats an env-incomplete or
# unreachable source as a FATAL startup error — which would take the whole
# shared gateway, and with it every project's database access, down.
#
# Filtering at render time is what makes activation lazy. The gateway starts
# with whatever is up; when a database comes up later the refresh poller
# re-renders and toolbox hot-reloads the new source into the running server.
# A reload that still turns out unavailable is rejected by toolbox while the
# previous config keeps serving, so this filter can never break the gateway:
# the worst case is a stale tool list.
#
# Usage:
#     available_catalogue.py [--timeout SECONDS] < catalogue.json
#
# The usable subset is written as JSON on stdout; each rejection, with its
# reason, is written to stderr so the poller's log shows why a datasource is
# missing.
# =============================================================================

import json
import os
import socket
import sys
from typing import NoReturn

from render_tools_yaml import load_catalogue, validated_items

DEFAULT_TIMEOUT = 1.0


def fail(message: str) -> NoReturn:
    sys.stderr.write(f"ERROR: {message}\n")
    sys.exit(1)


def _effective_values(spec: dict, engine: dict, environ) -> dict:
    """Each engine field resolved to its value, falling back to the field's
    own default. Mirrors how the tools.yaml renderer resolves variables."""
    declared = spec.get("env", {})
    values = {}
    for _field, engine_var, default in engine["fields"]:
        raw = environ.get(declared.get(engine_var, engine_var))
        values[engine_var] = raw if raw else default
    return values


def _missing_required(spec: dict, engine: dict, environ) -> list:
    """The operator's variable names for required fields that are unset or
    empty — toolbox fails to start on any of these, so they gate inclusion."""
    declared = spec.get("env", {})
    missing = []
    for _field, engine_var, default in engine["fields"]:
        if default is None and not environ.get(declared.get(engine_var, engine_var)):
            missing.append(declared.get(engine_var, engine_var))
    return missing


def _tcp_reachable(host: str, port: str, timeout: float) -> bool:
    # The gateway shares the host's network namespace (compose.tpl.yml), so a
    # host-side connect tests exactly what the container can reach. No
    # address translation is needed — or wanted: a translation would let the
    # probe and the container disagree about reachability.
    try:
        port_number = int(port)
    except (TypeError, ValueError):
        return False
    try:
        with socket.create_connection((host, port_number), timeout=timeout):
            return True
    except OSError:
        return False


def probe(name: str, spec: dict, engine: dict, timeout: float, environ) -> tuple:
    """Returns (usable, reason)."""
    missing = _missing_required(spec, engine, environ)
    if missing:
        return False, f"required env not set: {', '.join(sorted(missing))}"

    probe_spec = engine.get("probe", {"kind": "none"})
    if probe_spec["kind"] != "tcp":
        # No server to reach (sqlite): being env-complete is enough.
        return True, "usable"

    values = _effective_values(spec, engine, environ)
    host = str(values.get(probe_spec["host"]) or "")
    port = str(values.get(probe_spec["port"]) or "")
    if _tcp_reachable(host, port, timeout):
        return True, "usable"
    return False, f"unreachable: {host}:{port}"


def main():
    timeout = DEFAULT_TIMEOUT
    argv = sys.argv[1:]
    if argv:
        if argv[0] != "--timeout" or len(argv) < 2:
            fail("usage: available_catalogue.py [--timeout SECONDS]")
        try:
            timeout = float(argv[1])
        except ValueError:
            fail(f"invalid timeout: {argv[1]}")

    catalogue = load_catalogue(sys.stdin.read())

    usable = {}
    for name, spec, engine in validated_items(catalogue):
        is_usable, reason = probe(name, spec, engine, timeout, os.environ)
        if is_usable:
            usable[name] = spec
        else:
            sys.stderr.write(f"INFO: datasource '{name}' is not usable — {reason}\n")

    sys.stdout.write(json.dumps(usable, indent=2) + "\n")


if __name__ == "__main__":
    main()
