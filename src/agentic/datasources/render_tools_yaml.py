#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/render_tools_yaml.py
# Render an mcp-toolbox `tools.yaml` from the dev-bot datasources catalogue.
#
# Internal helper — never a primary entry point. datasources/install.sh and
# update.sh pipe `.devbot.global.jsonc`'s `datasources` object into it:
#
#     read_jsonc.py .devbot.global.jsonc datasources | render_tools_yaml.py
#
# One `source`, one tool and one `toolset` are emitted per datasource. The
# TOOLSET is the per-project scoping mechanism: harnesses connect to
# http://127.0.0.1:18510/mcp/<datasource>, so a project only ever sees the
# datasources it selected.
#
# Tool names are process-global in toolbox, so the generated tool name is
# namespaced `<datasource>_<tool>` — two `mysql` datasources would otherwise
# both claim `execute_sql`.
#
# The per-engine schema below is transcribed from mcp-toolbox's own prebuilt
# manifests (internal/prebuiltconfigs/tools/<engine>.yaml), which are the
# authoritative source field names and defaults.
# =============================================================================

import json
import re
import sys
from typing import NoReturn

# (yaml_field, toolbox_env_var, default) — default None means REQUIRED.
ENGINES = {
    "mysql": {
        "type": "mysql",
        "fields": [
            ("host", "MYSQL_HOST", "localhost"),
            ("port", "MYSQL_PORT", "3306"),
            # Optional, defaulting to empty: one MySQL/MariaDB instance usually
            # holds several databases, and a source with no default schema can
            # still query all of them by qualifying names (SELECT ... FROM db.t).
            # Required fields (no default) gate inclusion; see available_catalogue.
            ("database", "MYSQL_DATABASE", ""),
            ("user", "MYSQL_USER", None),
            ("password", "MYSQL_PASSWORD", None),
            ("queryParams", "MYSQL_QUERY_PARAMS", ""),
        ],
        "tool": {
            "name": "execute_sql",
            "type": "mysql-execute-sql",
            "description": "Execute a single SQL statement.",
        },
        # How to tell whether this datasource is usable right now — see
        # available_catalogue.py. Host/port name engine fields, not env vars:
        # the operator's own variable names are resolved through `env`.
        "probe": {"kind": "tcp", "host": "MYSQL_HOST", "port": "MYSQL_PORT"},
    },
    "postgres": {
        "type": "postgres",
        "fields": [
            ("host", "POSTGRES_HOST", "localhost"),
            ("port", "POSTGRES_PORT", "5432"),
            ("database", "POSTGRES_DATABASE", None),
            ("user", "POSTGRES_USER", None),
            ("password", "POSTGRES_PASSWORD", None),
            ("queryParams", "POSTGRES_QUERY_PARAMS", ""),
        ],
        "tool": {
            "name": "execute_sql",
            "type": "postgres-execute-sql",
            "description": "Execute a single SQL statement.",
        },
        "probe": {
            "kind": "tcp",
            "host": "POSTGRES_HOST",
            "port": "POSTGRES_PORT",
        },
    },
    # SQLite is here for the same reason it is useful to operators: it needs no
    # server and no credentials, which makes it the only engine the module can
    # exercise end to end inside the test suite.
    "sqlite": {
        "type": "sqlite",
        "fields": [
            ("database", "SQLITE_DATABASE", None),
        ],
        "tool": {
            "name": "execute_sql",
            "type": "sqlite-execute-sql",
            "description": "Execute a single SQL statement.",
        },
        # No probe: sqlite is a file, needs no server, and is never
        # unreachable. Being env-complete is all it takes to be usable.
        "probe": {"kind": "none"},
    },
}
# Datasource names become tool and toolset names, and a URL path segment.
NAME_RE = re.compile(r"^[a-z][a-z0-9-]*$")

# Names the operator's environment must provide. Validated because they are
# passed straight through compose to the container.
ENV_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

# Every key a datasource definition may carry.
KNOWN_KEYS = frozenset({"type", "env"})

# A datasource deliberately has NO read-only affordance. Upstream enforces
# read-only at the protocol level only for Cloud SQL / AlloyDB / BigQuery
# (docs/en/documentation/configuration/security/read-only.md); on the
# self-hosted engines the scope of the database user's credential is the only
# real defence. These keys are rejected loudly rather than silently ignored,
# so nobody believes writes are blocked when they are not.
READ_ONLY_KEYS = frozenset({"read_only", "readOnly"})


def _fail(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def _reject_unknown_keys(name: str, spec: dict) -> None:
    for key in sorted(set(spec) - KNOWN_KEYS):
        if key in READ_ONLY_KEYS:
            _fail(
                f"datasource '{name}': '{key}' is not supported — dev-bot cannot enforce "
                "read-only on this engine. Scope the database user's credential instead; "
                "that is the only real defence."
            )
        _fail(
            f"datasource '{name}': unknown key '{key}' "
            f"(known: {', '.join(sorted(KNOWN_KEYS))})"
        )


def _engine_for(name: str, spec: dict) -> dict:
    engine_type = spec.get("type")
    engine = ENGINES.get(engine_type) if isinstance(engine_type, str) else None
    if engine is None:
        _fail(
            f"datasource '{name}': unknown type '{engine_type}' "
            f"(known: {', '.join(sorted(ENGINES))})"
        )
    return engine


def validated_items(catalogue: dict):
    """Yield (name, spec, engine) for each datasource, failing loudly on
    anything invalid. The single validation path, shared by every renderer."""
    for name in sorted(catalogue):
        spec = catalogue[name]
        _reject_unknown_keys(name, spec)
        if not NAME_RE.match(name):
            _fail(f"datasource name '{name}' must match {NAME_RE.pattern}")
        engine = _engine_for(name, spec)
        if not isinstance(spec.get("env", {}), dict):
            _fail(f"datasource '{name}': 'env' must be an object")
        yield name, spec, engine


def effective_env_names(catalogue: dict) -> list:
    """Every env var name the rendered tools.yaml will reference.

    Declared names, plus each engine's own default variable for fields the
    datasource leaves undeclared. The gateway container has to receive all of
    them — compose cannot express "the whole environment" — so this is the set
    the compose renderer passes through.
    """
    names = set()
    for _name, spec, engine in validated_items(catalogue):
        declared = spec.get("env", {})
        for _field, engine_var, _default in engine["fields"]:
            names.add(declared.get(engine_var, engine_var))
    return sorted(names)


def render_source(name, spec, engine):
    # `env` is optional: a datasource may rely entirely on the engine's own
    # default variable names (export MYSQL_HOST and declare nothing).
    database = spec.get("env", {})
    known = {var for _, var, _ in engine["fields"]}

    for var, ref in database.items():
        if var not in known:
            _fail(
                f"datasource '{name}': env key '{var}' is not a {engine['type']} "
                f"source field (known: {', '.join(sorted(known))})"
            )
        if not isinstance(ref, str) or not ENV_NAME_RE.match(ref):
            _fail(
                f"datasource '{name}': env var name '{ref}' for '{var}' is not a "
                "valid environment variable name"
            )

    lines = ["kind: source", f"name: {name}", f"type: {engine['type']}"]
    for field, engine_var, default in engine["fields"]:
        var = database.get(engine_var, engine_var)
        lines.append(f"{field}: ${{{var}:{default}}}" if default is not None else f"{field}: ${{{var}}}")

    return lines


def render(catalogue):
    if not isinstance(catalogue, dict):
        _fail("catalogue must be an object of datasource name -> definition")

    docs = []
    for name, spec, engine in validated_items(catalogue):
        tool_name = f"{name}_{engine['tool']['name']}"
        tool = engine["tool"]

        docs.append("\n".join(render_source(name, spec, engine)))
        docs.append(
            "\n".join(
                [
                    "kind: tool",
                    f"name: {tool_name}",
                    f"type: {tool['type']}",
                    f"source: {name}",
                    f"description: {tool['description']}",
                ]
            )
        )
        docs.append("\n".join(["kind: toolset", f"name: {name}", "tools:", f"- {tool_name}"]))

    if not docs:
        return "# No datasources configured in .devbot.global.jsonc.\n"
    return "\n---\n".join(docs) + "\n"


def load_catalogue(raw: str) -> dict:
    """Parse a catalogue from JSON text, failing loudly on anything unusable."""
    if not raw.strip():
        _fail("no catalogue on stdin")
    try:
        catalogue = json.loads(raw)
    except json.JSONDecodeError as exc:
        _fail(f"catalogue is not valid JSON: {exc}")
    if catalogue is None:
        return {}
    if not isinstance(catalogue, dict):
        _fail("catalogue must be an object of datasource name -> definition")
    return catalogue


def main():
    catalogue = load_catalogue(sys.stdin.read())

    # `--env-names` prints just the env var name set, for the compose renderer.
    if "--env-names" in sys.argv[1:]:
        sys.stdout.write(json.dumps(effective_env_names(catalogue)) + "\n")
    else:
        sys.stdout.write(render(catalogue))


if __name__ == "__main__":
    main()
