#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/available_catalogue.py
# Filter the datasources catalogue down to the ones complete enough to hand to
# the gateway.
#
# A datasource is a CANDIDATE when every required env var is set. That is a
# pure environment check — this script opens no connections.
#
# It deliberately does NOT decide reachability. dev-bot used to probe with a
# bare TCP connect+close, which made MariaDB count handshake aborts per client
# host until `max_connect_errors` blocked the host (Error 1129) — the
# 2026-09-18 outage. Reachability is decided by validate_catalogue.py, which
# runs the real toolbox against the candidate: the only program that talks to a
# database is the one that will actually serve it, and its connections are
# authenticated — so they neither poison a host nor keep a blocked one alive.
#
# Usage:
#     available_catalogue.py < catalogue.json
#
# The candidate subset is written as JSON on stdout; each rejection, with its
# reason, goes to stderr so the render shows why a datasource is missing.
# =============================================================================

import json
import os
import sys
from typing import NoReturn

from render_tools_yaml import env_ref, field_parts, load_catalogue, validated_items


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
        _yaml_field, engine_var, default, _where, optional = field_parts(field)
        source = declared[engine_var] if engine_var in declared else "${" + engine_var + "}"
        value, absent = _resolve_field(source, default, environ)
        if absent and optional:
            absent = None  # an optional field being absent is not a failure
        values[engine_var] = value
        if absent:
            missing.append(absent)
    return values, missing


def is_candidate(spec: dict, engine: dict, environ) -> tuple:
    """(candidate, reason) — the environment is the only judge here.

    Whether toolbox can actually initialize the datasource is not decidable
    from the environment; validate_catalogue.py answers that against the real
    gateway.
    """
    _values, missing = _field_values(spec, engine, environ)
    if missing:
        return False, f"required env not set: {', '.join(sorted(missing))}"
    return True, "usable"


def main():
    if sys.argv[1:]:
        fail("usage: available_catalogue.py (reads the catalogue on stdin, takes no arguments)")

    catalogue = load_catalogue(sys.stdin.read())

    candidates = {}
    for name, spec, engine in validated_items(catalogue):
        ok, reason = is_candidate(spec, engine, os.environ)
        if ok:
            candidates[name] = spec
        else:
            sys.stderr.write(f"INFO: datasource '{name}' is not usable — {reason}\n")

    sys.stdout.write(json.dumps(candidates, indent=2) + "\n")


if __name__ == "__main__":
    main()
