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

from render_tools_yaml import env_ref, field_parts, load_catalogue, validated_items

DEFAULT_TIMEOUT = 1.0


def fail(message: str) -> NoReturn:
    sys.stderr.write(f"ERROR: {message}\n")
    sys.exit(1)


def _resolve_field(declared_value, default, environ) -> tuple:
    """(value, missing_var).

    A literal is always present, whatever the environment says. A `${VAR}`
    reference is missing when the variable is unset or empty and the field has
    no default — which is exactly when toolbox would refuse to start.
    """
    ref = env_ref(declared_value)
    if ref is None:
        return declared_value, None
    value = environ.get(ref)
    if value:
        return value, None
    if default is not None:
        return default, None
    return None, ref


def _field_values(spec: dict, engine: dict, environ) -> tuple:
    """(field -> value, missing var names).

    An undeclared field is treated as a reference to the engine's own variable
    name, which is what the renderer emits for it.
    """
    declared = spec.get("env", {})
    values, missing = {}, []
    for field in engine["fields"]:
        _yaml_field, engine_var, default, _where = field_parts(field)
        source = declared[engine_var] if engine_var in declared else "${" + engine_var + "}"
        value, absent = _resolve_field(source, default, environ)
        values[engine_var] = value
        if absent:
            missing.append(absent)
    return values, missing


def _uri_host_port(uri: str) -> tuple:
    """(host, port) from a connection URI — `mongodb://user:pw@h1:27017,h2/db?opts`.

    Only what a reachability probe needs: credentials, further replica-set
    hosts and options are dropped, and the first host is used. An SRV URI
    carries no port, so 27017 is assumed — which is where SRV records resolve
    in practice.
    """
    if not isinstance(uri, str) or "://" not in uri:
        return None, None
    rest = uri.split("://", 1)[1].split("/", 1)[0].split("?", 1)[0]
    if "@" in rest:
        rest = rest.rsplit("@", 1)[1]
    host, _, port = rest.split(",", 1)[0].partition(":")
    return (host or None), (port or "27017")


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
    values, missing = _field_values(spec, engine, environ)
    if missing:
        return False, f"required env not set: {', '.join(sorted(missing))}"

    probe_spec = engine.get("probe", {"kind": "none"})
    kind = probe_spec["kind"]
    if kind == "none":
        # No server to reach (sqlite): being resolvable is enough.
        return True, "usable"

    if kind == "tcp-uri":
        uri_field = probe_spec["field"]
        host, port = _uri_host_port(values.get(uri_field))
        if not host:
            return False, f"no host in '{uri_field}'"
    else:
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
