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
            ("database", "MYSQL_DATABASE", None),
            ("user", "MYSQL_USER", None),
            ("password", "MYSQL_PASSWORD", None),
            ("queryParams", "MYSQL_QUERY_PARAMS", ""),
        ],
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
            ("queryParams", "POSTGRES_QUERY_PARAMS", ""),
        ],
        "tool": {
            "name": "execute_sql",
            "type": "postgres-execute-sql",
            "description": "Execute a single SQL statement.",
        },
    },
}

# Datasource names become tool and toolset names, and a URL path segment.
NAME_RE = re.compile(r"^[a-z][a-z0-9-]*$")

# `read_only` note: upstream documents protocol-level enforcement only for
# Cloud SQL / AlloyDB / BigQuery
# (docs/en/documentation/configuration/security/read-only.md), so on the
# self-hosted engines the database credential remains the real barrier. The
# flag is still emitted — it is toolbox's own mechanism — but the module docs
# must not present it as a guarantee there.
def _fail(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def render_source(name, spec, engine):
    database = spec["env"]
    known = {var for _, var, _ in engine["fields"]}

    for var in database:
        if var not in known:
            _fail(
                f"datasource '{name}': env key '{var}' is not a {engine['type']} "
                f"source field (known: {', '.join(sorted(known))})"
            )

    lines = ["kind: source", f"name: {name}", f"type: {engine['type']}"]
    for field, engine_var, default in engine["fields"]:
        var = database.get(engine_var, engine_var)
        lines.append(f"{field}: ${{{var}:{default}}}" if default is not None else f"{field}: ${{{var}}}")

    # Defaults to true: fail-safe. Emitted only when true, so an engine that
    # rejects the field is unaffected by an explicit read_only: false.
    if spec.get("read_only", True):
        lines.append("readOnly: true")
    return lines


def render(catalogue):
    if not isinstance(catalogue, dict):
        _fail("catalogue must be an object of datasource name -> definition")

    docs = []
    for name in sorted(catalogue):
        spec = catalogue[name]
        if not NAME_RE.match(name):
            _fail(f"datasource name '{name}' must match {NAME_RE.pattern}")

        engine = ENGINES.get(spec.get("type"))
        if engine is None:
            _fail(
                f"datasource '{name}': unknown type '{spec.get('type')}' "
                f"(known: {', '.join(sorted(ENGINES))})"
            )

        if not isinstance(spec.get("env", {}), dict):
            _fail(f"datasource '{name}': 'env' must be an object")
        if not isinstance(spec.get("read_only", True), bool):
            _fail(f"datasource '{name}': 'read_only' must be a boolean")

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


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        _fail("no catalogue on stdin")
    try:
        catalogue = json.loads(raw)
    except json.JSONDecodeError as exc:
        _fail(f"catalogue is not valid JSON: {exc}")
    if catalogue in (None, {}):
        catalogue = {}
    sys.stdout.write(render(catalogue))


if __name__ == "__main__":
    main()
