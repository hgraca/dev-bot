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

from render_tools_yaml import (
    HOST_GATEWAY_BINDING,
    SIDECARS,
    effective_env_names,
    is_sidecar,
    load_catalogue,
    on_macos,
)
from validate_catalogue import load_versions

# Replaced by the env var name list. Kept on a single line so the substitution
# is a plain string replace and survives any formatter re-indenting the rest.
MARKER = "__DATASOURCE_ENV__"

# Replaced by the gateway's network stanza: host networking on Linux, a
# loopback-published port plus the host-gateway pin on macOS (see
# _network_mode). A COMMENT line so the template stays valid YAML — and
# prettier-parseable — on its own.
NETWORK_MODE_MARKER = "    # __NETWORK_MODE__"

# Replaced by the address the toolbox binds: 127.0.0.1 on Linux (host
# networking reaches the host loopback directly), 0.0.0.0 on macOS (the
# published port is what keeps it off the LAN).
BIND_ADDRESS_MARKER = "__BIND_ADDRESS__"

# Replaced by one compose service per sidecar datasource (empty when there are
# none). It is written as a COMMENT so the template stays valid YAML on its own —
# only the toolbox service is shipped, the sidecar block is generated.
SIDECAR_MARKER = "# __SIDECAR_SERVICES__"

# Sidecar ports sit just above the gateway's own port, inside the block this
# module already owns (18500-18599). The base is DERIVED from DATASOURCES_PORT
# rather than hardcoded, so moving the gateway moves the sidecars with it instead
# of letting the two collide on one loopback port. Allocation is by SORTED
# datasource name, so a reinit renders byte-identical ports whatever order the
# catalogue is in.
DEFAULT_GATEWAY_PORT = 18510
SIDECAR_PORT_OFFSET = 10
SIDECAR_PORT_LIMIT = 18599

# The sidecar package cache. `uvx` resolves the server's dependencies at every
# container start, so a shared host directory turns a restart into a warm start
# instead of a re-download (69 packages for opensearch). uv's cache is
# content-addressed, so one directory safely serves every sidecar.
UV_CACHE_DIR = "/var/cache/uv"
UV_CACHE_HOST_DIR = "uv-cache"

ENV_REF_RE = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$")


def fail(message: str) -> NoReturn:
    sys.stderr.write(f"ERROR: {message}\n")
    sys.exit(1)


def gateway_port() -> int:
    """The port the toolbox gateway binds, from DATASOURCES_PORT."""
    raw = os.environ.get("DATASOURCES_PORT", "").strip()
    if not raw:
        return DEFAULT_GATEWAY_PORT
    try:
        return int(raw)
    except ValueError:
        fail(f"DATASOURCES_PORT={raw!r} is not an integer")


def _network_mode(port: int) -> str:
    """The gateway's network stanza, indented as a compose service entry.

    Host networking is Linux-only: on macOS Docker Desktop the container's
    loopback is not the host's, so the gateway publishes the port instead. The
    published port is bound to the host's loopback, keeping the gateway off the
    LAN exactly as host networking does. Replaces the whole marker line, so the
    returned lines carry their own indentation.

    Also pins host.docker.internal, whose Desktop-supplied DNS entry
    can NXDOMAIN behind a VPN resolver.
    """
    if on_macos():
        return (
            "    ports:\n"
            f'      - "127.0.0.1:${{DATASOURCES_PORT:-{port}}}:'
            f'${{DATASOURCES_PORT:-{port}}}"\n'
            "    extra_hosts:\n"
            f'      - "{HOST_GATEWAY_BINDING}"'
        )
    return "    network_mode: host"


def _bind_address() -> str:
    """The address the toolbox binds: 127.0.0.1 on Linux, 0.0.0.0 on macOS."""
    return "0.0.0.0" if on_macos() else "127.0.0.1"


def sidecar_ports(catalogue: dict) -> dict:
    """Each sidecar datasource's fixed port, keyed by name."""
    base = gateway_port() + SIDECAR_PORT_OFFSET
    names = sorted(
        name
        for name, spec in catalogue.items()
        if isinstance(spec, dict) and is_sidecar(spec)
    )
    if names and base + len(names) - 1 > SIDECAR_PORT_LIMIT:
        fail(
            f"{len(names)} sidecar datasources exceed the port block "
            f"{base}-{SIDECAR_PORT_LIMIT}"
        )
    return {name: base + index for index, name in enumerate(names)}


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


def _warn_unset_refs(name: str, spec: dict, entry: dict) -> None:
    """Warn about a declared `${VAR}` the render environment does not have.

    Engines are filtered OUT by available_catalogue.py when their env is
    incomplete; sidecars are not toolbox sources, so they bypass that gate
    entirely. This is the substitute: a warning, not a refusal, because a sidecar
    with unset credentials still starts and fails only when first called.
    """
    declared = spec.get("env", {})
    for var in entry["env"]:
        value = declared.get(var)
        if not isinstance(value, str):
            continue
        match = ENV_REF_RE.match(value)
        if match and not os.environ.get(match.group(1)):
            sys.stderr.write(
                f"WARN: datasource '{name}': {match.group(1)} is unset (for {var}) — "
                "the sidecar will start without it\n"
            )


def render_sidecar_service(name: str, spec: dict, port: int, versions: dict) -> str:
    """One streamable-http compose service, indented as a `services:` entry."""
    entry = SIDECARS[spec["type"]]

    image = versions.get(entry["image"], "")
    if not image:
        fail(f"datasource '{name}': versions.env must define {entry['image']}")

    _warn_unset_refs(name, spec, entry)

    command = [_substitute(arg, versions, port) for arg in entry["command"]]
    if on_macos():
        # The sidecar's streamable-http listener must answer the published
        # port, which Docker Desktop forwards to the container's own address.
        command = ["0.0.0.0" if arg == "127.0.0.1" else arg for arg in command]

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
    ]
    if on_macos():
        # Loopback-only published port: Docker Desktop cannot do host
        # networking, and the bind keeps the listener off the LAN.
        lines.append(f'    ports:\n      - "127.0.0.1:{port}:{port}"')
    else:
        # Loopback-only, like every other dev-bot gateway: the sidecar's
        # streamable-http listener has no inbound auth, and host networking
        # reaches the host's loopback without exposing a port mapping.
        lines.append("    network_mode: host")
    lines.append("    volumes:")
    # One host directory shared by every sidecar (see UV_CACHE_DIR).
    # render.sh creates it as the host user; the container writes it as
    # root, which is fine for a cache — the directory is disposable.
    lines.append(
        f"      - ${{DEV_BOT_ROOT}}/storage/datasources/{UV_CACHE_HOST_DIR}:{UV_CACHE_DIR}"
    )

    declared = spec.get("env", {})
    env_lines = [
        f"      {var}: {_environment_value(declared[var])}"
        for var in entry["env"]
        if var in declared
    ]
    # Always present, even when the sidecar declares no env of its own.
    env_lines.append(f"      UV_CACHE_DIR: {UV_CACHE_DIR}")
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

    for marker in (MARKER, NETWORK_MODE_MARKER, BIND_ADDRESS_MARKER, SIDECAR_MARKER):
        if marker not in template:
            fail(f"template {template_path} does not contain {marker}")

    versions = load_versions(
        os.path.join(os.path.dirname(template_path), "versions.env")
    )

    out = template.replace(MARKER, json.dumps(effective_env_names(catalogue)))
    out = out.replace(NETWORK_MODE_MARKER, _network_mode(gateway_port()))
    out = out.replace(BIND_ADDRESS_MARKER, _bind_address())
    # rstrip: the template already carries the newline after the marker.
    out = out.replace(SIDECAR_MARKER, render_sidecars(catalogue, versions).rstrip("\n"))
    sys.stdout.write(out)


if __name__ == "__main__":
    main()
