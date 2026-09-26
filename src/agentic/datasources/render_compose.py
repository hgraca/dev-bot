#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/render_compose.py
# Render the datasource gateways' docker-compose.yml from the catalogue.
#
# Internal helper — never a primary entry point. datasources/render.sh runs it.
#
# The file is rendered rather than shipped for two reasons:
#   - the toolbox gateway must receive every env var the declared datasources
#     reference, and those names are dynamic (they come from .devbot.global.jsonc,
#     and compose has no "pass the whole environment" form). Only NAMES are
#     written, and the values are interpolated by compose from the environment
#     `devbot up` builds — so no credential is ever written to disk.
#   - each SIDECAR datasource (a non-toolbox type) is served by its own
#     streamable-http container, so the service list is dynamic too.
#
# Usage:
#     render_compose.py <template-path> < catalogue.json > docker-compose.yml
# =============================================================================

import json
import os
import re
import sys
from typing import NoReturn

from render_tools_yaml import SIDECARS, effective_env_names, is_sidecar, load_catalogue
from validate_catalogue import load_versions

# Replaced by the env var name list. Kept on a single line so the substitution
# is a plain string replace and survives any formatter re-indenting the rest.
MARKER = "__DATASOURCE_ENV__"

# Replaced by one compose service per sidecar datasource (empty when there are
# none). It is written as a COMMENT so the template stays valid YAML on its own —
# only the toolbox service is shipped, the sidecar block is generated.
SIDECAR_MARKER = "# __SIDECAR_SERVICES__"

# Sidecar ports sit after the toolbox gateway's 18510, inside the block this
# module already owns (18500-18599). Allocation is by SORTED datasource name, so
# a reinit renders byte-identical ports regardless of catalogue order.
SIDECAR_PORT_BASE = 18520
SIDECAR_PORT_LIMIT = 18599

ENV_REF_RE = re.compile(r"^\$\{[A-Za-z_][A-Za-z0-9_]*\}$")


def fail(message: str) -> NoReturn:
    sys.stderr.write(f"ERROR: {message}\n")
    sys.exit(1)


def sidecar_ports(catalogue: dict) -> dict:
    """Each sidecar datasource's fixed port, keyed by name."""
    names = sorted(
        name
        for name, spec in catalogue.items()
        if isinstance(spec, dict) and is_sidecar(spec)
    )
    if names and SIDECAR_PORT_BASE + len(names) - 1 > SIDECAR_PORT_LIMIT:
        fail(
            f"{len(names)} sidecar datasources exceed the port block "
            f"{SIDECAR_PORT_BASE}-{SIDECAR_PORT_LIMIT}"
        )
    return {name: SIDECAR_PORT_BASE + index for index, name in enumerate(names)}


def _environment_value(value) -> str:
    """A compose `environment` value for one declared datasource entry.

    A `${VAR}` reference is passed through for compose to interpolate from the
    environment `devbot up` builds — the value never touches disk. A literal is
    JSON-quoted so YAML reads it as the string it is.
    """
    raw = str(value)
    if ENV_REF_RE.match(raw):
        return raw
    return json.dumps(raw)


def _substitute(value: str, versions: dict, port: int) -> str:
    """Resolve {TOKEN} references in a sidecar command or path.

    {port} is the allocated port; every other token is a versions.env key, so a
    pin lives in one place. An unknown token fails loudly rather than rendering
    an empty argument.
    """

    def replace(match: "re.Match") -> str:
        token = match.group(1)
        if token == "port":
            return str(port)
        resolved = versions.get(token, "")
        if not resolved:
            fail(f"versions.env is missing '{token}' (referenced by a sidecar)")
        return resolved

    return re.sub(r"\{([A-Za-z_][A-Za-z0-9_]*)\}", replace, value)


def render_sidecar_service(name: str, spec: dict, port: int, versions: dict) -> str:
    """One streamable-http compose service, indented as a `services:` entry."""
    entry = SIDECARS[spec["type"]]

    image = versions.get(entry["image"], "")
    if not image:
        fail(f"datasource '{name}': versions.env must define {entry['image']}")

    command = [_substitute(arg, versions, port) for arg in entry["command"]]

    lines = [
        f"  {name}:",
        f"    image: {image}",
    ]
    if entry.get("build"):
        lines.append("    build:")
        lines.append(f"      context: {entry['build']}")
    lines += [
        f"    container_name: dev-bot-datasources-{name}",
        '    restart: "no"',
        # Loopback-only, like every other dev-bot gateway: the sidecar's
        # streamable-http listener has no inbound auth, and host networking
        # reaches the host's loopback without exposing a port mapping.
        "    network_mode: host",
    ]

    declared = spec.get("env", {})
    env_lines = [
        f"      {var}: {_environment_value(declared[var])}"
        for var in entry["env"]
        if var in declared
    ]
    if env_lines:
        lines.append("    environment:")
        lines.extend(env_lines)

    lines.append("    command:")
    lines.extend(f"      - {json.dumps(arg)}" for arg in command)

    return "\n".join(lines) + "\n"


def render_sidecars(catalogue: dict, versions: dict) -> str:
    """Every sidecar service, or "" when the catalogue has none."""
    ports = sidecar_ports(catalogue)
    return "".join(
        render_sidecar_service(name, catalogue[name], ports[name], versions)
        for name in sorted(ports)
    )


def main():
    if "--sidecar-ports" in sys.argv[1:]:
        # Print just the sidecar name -> port map, for init.sh. The allocation
        # lives HERE, so a manifest URL and the service's listener cannot drift.
        sys.stdout.write(json.dumps(sidecar_ports(load_catalogue(sys.stdin.read()))) + "\n")
        return

    if len(sys.argv) < 2:
        fail("usage: render_compose.py <template-path> | --sidecar-ports")

    template_path = sys.argv[1]
    catalogue = load_catalogue(sys.stdin.read())

    try:
        with open(template_path, encoding="utf-8") as handle:
            template = handle.read()
    except OSError as exc:
        fail(f"cannot read template {template_path}: {exc}")

    for marker in (MARKER, SIDECAR_MARKER):
        if marker not in template:
            fail(f"template {template_path} does not contain {marker}")

    versions = load_versions(
        os.path.join(os.path.dirname(template_path), "versions.env")
    )

    out = template.replace(MARKER, json.dumps(effective_env_names(catalogue)))
    # rstrip: the template already carries the newline after the marker.
    out = out.replace(SIDECAR_MARKER, render_sidecars(catalogue, versions).rstrip("\n"))
    sys.stdout.write(out)


if __name__ == "__main__":
    main()
