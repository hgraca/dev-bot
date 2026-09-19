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
# Toolbox reads a source's `queryParams` as a MAP, and it is the only place a
# connection timeout can live. Without one the driver dials on the OS default
# (~2 minutes for a host that silently drops packets), which hangs the
# gateway's startup — and makes the availability canary unattributable: it
# never becomes ready and never exits, so no culprit can be named and the
# source is neither dropped nor reported. The render then aborts forever.
#
# Verified against the pinned 1.11.0 image: with these, a firewalled host fails
# in ~5s and names itself. Units are per driver — the Go MySQL driver takes a
# duration (`5s`), pgx takes seconds (`5`).
#
# Two engines stay unbounded, deliberately and visibly:
#   * mongodb has no queryParams field; its timeout lives inside the URI
#     (`connectTimeoutMS` / `serverSelectionTimeoutMS`), and dev-bot passes the
#     operator's URI through untouched rather than rewriting it.
#   * redis exposes no dial timeout in 1.11.0 — both `timeout` and
#     `dialTimeout` are rejected as unknown fields.
# A blackholed host for either is only bounded by the canary's own deadline, so
# it cannot be attributed. See docs/configuration.md.
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
        ],
        # Go MySQL driver dial timeout — see the queryParams note above.
        "query_params": {"timeout": "5s"},
        "tool": {
            "name": "execute_sql",
            "type": "mysql-execute-sql",
            "description": "Execute a single SQL statement.",
        },
    },
    "postgres": {
        "type": "postgres",
        "fields": [
            ("host", "POSTGRES_HOST", "localhost"),
            ("port", "POSTGRES_PORT", "5432"),
            ("database", "POSTGRES_DATABASE", None),
            ("user", "POSTGRES_USER", None),
            ("password", "POSTGRES_PASSWORD", None),
        ],
        # pgx connect timeout, in SECONDS — see the queryParams note above.
        "query_params": {"connect_timeout": "5"},
        "tool": {
            "name": "execute_sql",
            "type": "postgres-execute-sql",
            "description": "Execute a single SQL statement.",
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
    },
    "mongodb": {
        "type": "mongodb",
        "fields": [
            # The whole connection lives in the URI, credentials included —
            # hence a ${VAR} reference for it in practice.
            ("uri", "MONGODB_URI", None),
            # Tool-level: mongodb-aggregate requires a database, so one mongo
            # datasource covers ONE database (unlike mysql, whose source may
            # have no default schema). `collection` is deliberately not set, so
            # it stays a runtime parameter the agent chooses.
            ("database", "MONGODB_DATABASE", None, "tool"),
        ],
        "tool": {
            "name": "aggregate",
            "type": "mongodb-aggregate",
            "description": "Run a MongoDB aggregation pipeline against a collection.",
        },
        # The free-form surface: the agent supplies the entire pipeline, which
        # toolbox renders straight into the payload. Appended verbatim — this
        # is the one place a tool needs more than scalar key/values.
        #
        # An array parameter REQUIRES a fully-formed `items` (name, type AND
        # description): without it the image refuses the whole config with
        # "unable to parse 'items' field", which would take the shared gateway
        # down. `collection` is deliberately omitted — upstream documents that
        # it then has to be supplied at runtime, which is what lets the agent
        # choose the collection rather than pinning one.
        "tool_body": [
            "pipelinePayload: |",
            "  {{json .pipeline}}",
            "pipelineParams:",
            "  - name: pipeline",
            "    type: array",
            "    description: The aggregation pipeline, as a JSON array of stage documents.",
            "    items:",
            "      name: stage",
            "      type: map",
            "      description: One aggregation stage, for example a $match filter.",
        ],
    },
    "redis": {
        "type": "redis",
        "fields": [
            # A YAML SEQUENCE upstream, even for a single endpoint.
            ("address", "REDIS_ADDRESS", None),
            # Optional upstream, and to be OMITTED rather than emptied: the
            # redis source documents "omit this field if you do not have a
            # password", and an empty AUTH string is not the same as none.
            ("username", "REDIS_USERNAME", None, "source", True),
            ("password", "REDIS_PASSWORD", None, "source", True),
        ],
        "list_fields": frozenset({"REDIS_ADDRESS"}),
        "tool": {
            "name": "run",
            "type": "redis",
            "description": "Run a Redis command.",
        },
        # Redis has no free-form tool of its own: its `commands` list is fixed
        # at config time. But an ARRAY argument is flattened into the command,
        # so templating the whole command with one array parameter makes the
        # command NAME a runtime value too — which is what gives Redis the same
        # free-form surface the SQL engines have, rather than a menu of
        # hand-picked commands. Verified against the pinned image.
        "tool_body": [
            "commands:",
            "  - [$args]",
            "parameters:",
            "  - name: args",
            "    type: array",
            "    description: 'The command and its arguments, e.g. [\"GET\", \"some-key\"].'",
            "    items:",
            "      name: arg",
            "      type: string",
            "      description: One token — the command name first, then its arguments.",
        ],
    },
}
# Datasource names become tool and toolset names, and a URL path segment.
NAME_RE = re.compile(r"^[a-z][a-z0-9-]*$")

# A datasource's `env` VALUE is either a `${VAR}` REFERENCE to an environment
# variable or a LITERAL, written straight into the rendered config:
#
#     "MYSQL_HOST": "db.internal",              <- literal, reads well inline
#     "MYSQL_PASSWORD": "${HOTELS_DB_PASSWORD}" <- reference, never hits disk
#
# A reference must be the whole value: there is no interpolation inside a
# longer string, so a password containing "${" can never be mistaken for one.
# References are resolved by toolbox from the container's environment at load
# time, so a secret behind one exists in no file at all.
ENV_REF_RE = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$")


def env_ref(value):
    """The referenced variable name, or None when the value is a literal."""
    if not isinstance(value, str):
        return None
    match = ENV_REF_RE.match(value)
    return match.group(1) if match else None


def _literal_text(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def _yaml_scalar(value) -> str:
    """A single-quoted YAML scalar — a literal may contain ':', '#' or spaces."""
    return "'" + _literal_text(value).replace("'", "''") + "'"


def field_parts(field) -> tuple:
    """(yaml_field, env_var, default, where, optional).

    `where` says which document the field belongs to: the `source` (a
    connection parameter) or the `tool` (a tool-level parameter — MongoDB's
    `database`, which its aggregate tool requires). Fields are declared as
    3-tuples and default to the source; a 4th element marks a tool field.

    `optional` means: when the datasource does not declare it, OMIT it rather
    than emitting a bare `${VAR}`. That distinction matters — toolbox treats an
    emitted `${VAR}` as a hard requirement, and for a field like redis
    `password` an empty value is not the same as an absent one.
    """
    yaml_field, engine_var = field[0], field[1]
    default = field[2] if len(field) > 2 else None
    where = field[3] if len(field) > 3 else "source"
    optional = field[4] if len(field) > 4 else False
    return yaml_field, engine_var, default, where, optional

# Every key a datasource definition may carry.
KNOWN_KEYS = frozenset({"type", "env"})

# A datasource deliberately has NO read-only affordance. Upstream's
# protocol-level lock covers only Cloud SQL / AlloyDB / BigQuery, and even where
# a tool can be marked read-only (MongoDB's aggregate) that is one engine's
# shape rather than a guarantee this module can make for all of them. A
# datasource is exactly as writable as the credential behind it, and that is
# where the control belongs. These keys are rejected loudly rather than
# silently ignored, so nobody believes writes are blocked when they are not.
READ_ONLY_KEYS = frozenset({"read_only", "readOnly"})


def _fail(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def _reject_unknown_keys(name: str, spec: dict) -> None:
    for key in sorted(set(spec) - KNOWN_KEYS):
        if key in READ_ONLY_KEYS:
            _fail(
                f"datasource '{name}': '{key}' is not supported — dev-bot does not "
                "manage read-only. A datasource is exactly as writable as the "
                "database user behind it, so scope that credential instead."
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
    """Every env var name the rendered tools.yaml will actually reference.

    `${VAR}` references, plus each engine's own default variable for fields the
    datasource leaves undeclared, which is what makes "export MYSQL_HOST" work.
    A literal needs no variable at all, so it contributes nothing here — the
    container is handed fewer variables, not more.
    """
    names = set()
    for _name, spec, engine in validated_items(catalogue):
        declared = spec.get("env", {})
        for field in engine["fields"]:
            _yaml_field, engine_var, default, _where, optional = field_parts(field)
            if optional and default is None and engine_var not in declared:
                continue  # omitted from the config, so nothing to pass in
            if engine_var in declared:
                ref = env_ref(declared[engine_var])
                if ref is not None:
                    names.add(ref)
            else:
                names.add(engine_var)
    return sorted(names)


def _validate_env(name, spec, engine):
    """Every `env` key must be a real field, with a scalar value."""
    database = spec.get("env", {})
    # Index 1 is the engine's variable name, whether the field is a 3-tuple
    # (source) or a 4-tuple (source/tool).
    known = {field[1] for field in engine["fields"]}

    for var, declared in database.items():
        if var not in known:
            _fail(
                f"datasource '{name}': env key '{var}' is not a {engine['type']} "
                f"field (known: {', '.join(sorted(known))})"
            )
        if declared is None or isinstance(declared, (dict, list)):
            _fail(
                f"datasource '{name}': the value for '{var}' must be a string or a "
                "number — either a literal or a ${VAR} reference to an "
                "environment variable"
            )


def _render_fields(spec, engine, where) -> list:
    """The rendered lines for the fields that belong to one document."""
    database = spec.get("env", {})
    list_fields = engine.get("list_fields", ())
    lines = []
    for field in engine["fields"]:
        yaml_field, engine_var, default, target, optional = field_parts(field)
        if target != where:
            continue

        if engine_var in database:
            ref = env_ref(database[engine_var])
            if ref is not None:
                # The value stays out of the file: toolbox reads the variable
                # from the container's environment when it loads this config.
                value = (
                    f"${{{ref}:{default}}}" if default is not None else f"${{{ref}}}"
                )
            else:
                # A literal, written straight in. Non-secret values (host, port,
                # database, user) read far better inline; a secret belongs
                # behind a ${VAR} reference.
                value = _yaml_scalar(database[engine_var])
        elif default is not None:
            # Undeclared: the engine's own variable, defaulted — exporting
            # MYSQL_HOST still works without declaring anything.
            value = f"${{{engine_var}:{default}}}"
        elif optional:
            # Absent by design. Emitting ${VAR} here would turn an optional
            # field into a hard requirement the image refuses to start without.
            continue
        else:
            # Undeclared, no default: still emitted, so exporting the engine's
            # own name works. available_catalogue gates it out when unset.
            value = f"${{{engine_var}}}"

        if engine_var in list_fields:
            # Upstream expects a sequence here even for one endpoint.
            lines.append(f"{yaml_field}:")
            lines.append(f"  - {value}")
        else:
            lines.append(f"{yaml_field}: {value}")
    return lines


def _render_query_params(engine) -> list:
    """The engine's fixed `queryParams` mapping — see the note above ENGINES.

    Emitted as a mapping, never a scalar: toolbox expects a map here and
    refuses the whole config if it finds a string.
    """
    params = engine.get("query_params")
    if not params:
        return []
    lines = ["queryParams:"]
    for key, value in params.items():
        lines.append(f"  {key}: {value}")
    return lines


def render_source(name, spec, engine) -> list:
    # `env` is optional: a datasource may rely entirely on the engine's own
    # default variable names (export MYSQL_HOST and declare nothing).
    lines = ["kind: source", f"name: {name}", f"type: {engine['type']}"]
    return lines + _render_fields(spec, engine, "source") + _render_query_params(engine)


def render_tool(name, spec, engine) -> list:
    tool = engine["tool"]
    lines = [
        "kind: tool",
        f"name: {name}_{tool['name']}",
        f"type: {tool['type']}",
        f"source: {name}",
        f"description: {tool['description']}",
    ]
    return lines + _render_fields(spec, engine, "tool") + list(engine.get("tool_body", []))


def render(catalogue):
    if not isinstance(catalogue, dict):
        _fail("catalogue must be an object of datasource name -> definition")

    docs = []
    for name, spec, engine in validated_items(catalogue):
        _validate_env(name, spec, engine)
        tool_name = f"{name}_{engine['tool']['name']}"

        docs.append("\n".join(render_source(name, spec, engine)))
        docs.append("\n".join(render_tool(name, spec, engine)))
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
