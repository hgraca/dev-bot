#!/usr/bin/env bash
# ---
# description: Resolve a path to the registered devbot project that owns it, and report that project's effective configuration.
# ---
# =============================================================================
# src/tools/devbot-cli/tools/project-for-path.mcp.sh
# A polyrepo session has no single current project: every project-scoped
# action must first find the project that owns the files it touches. This tool
# is that lookup plus the owner's effective config: scalars resolve
# project-first then global; `modules` merges per key; `datasources` is the
# project's own opt-in selection. `mcps` is the per-server state of the
# generated harness config: the one under `--session-root` when given (the
# checkout the harness actually runs in), otherwise the nearest one at or above
# the owner. `mcps_sources` names the files read, so state is never mistaken for a
# config that was never consulted. `mcps_errors` reports a config that could not
# be read, parsed, or shaped as expected. `atlassian_server` resolves the
# Atlassian MCP server by endpoint, not by name: OAuth credentials are per server
# name, so a second Jira account registers the same URL under a second name.
# `name` is null when nothing can be named — two live servers, or several entries
# with none live — and `candidates` then lists them.
#
# Usage:
#   project-for-path.mcp.sh <path>                       # markdown table
#   project-for-path.mcp.sh <path> --json                # JSON object
#   project-for-path.mcp.sh <path> --key mcps            # one resolved value
#   project-for-path.mcp.sh <path> --session-root DIR    # live harness checkout
#   project-for-path.mcp.sh <path> --global-config F     # non-default registry
#
# Exit codes: 0 resolved, 2 usage error, 3 no registered project contains <path>.
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"project-for-path","description":"Resolve a path to the registered devbot project that owns it (longest registered prefix in .devbot.global.jsonc), and report that project's effective workspace type, commit_memory, workflow, devbot_dir, datasources, modules and configured MCP servers. `atlassian_server` resolves the Atlassian MCP server by endpoint to `{name, state}` (with `candidates` when `name` is null) — a project may register it under a name other than `atlassian` to keep a separate Jira account, so read that key rather than the literal one. Use it in a polyrepo session before any project-scoped action, and before assuming an MCP server is configured. Configuration does not imply reachability: an enabled server may still be offline or unauthenticated.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: <path> [--json] [--key <name>] [--session-root <dir>] [--global-config <file>]"}},"required":["args"]}}
JSON
    exit 0
    ;;
  -h | --help)
    sed -n '7,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
DEV_BOT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
SHARED_DIR="${DEV_BOT_ROOT}/src/_shared"
CONFIG_FILE="${DEV_BOT_GLOBAL_CONFIG:-${DEV_BOT_ROOT}/.devbot.global.jsonc}"

OUTPUT_FORMAT="markdown"
KEY=""
TARGET=""
SESSION_ROOT="${DEV_BOT_PROJECT_ROOT:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT_FORMAT="json"; shift ;;
    --key)
      [[ $# -ge 2 ]] || { echo "ERROR: --key requires a name" >&2; exit 2; }
      KEY="$2"; shift 2
      ;;
    --key=*) KEY="${1#--key=}"; shift ;;
    --global-config)
      [[ $# -ge 2 ]] || { echo "ERROR: --global-config requires a file" >&2; exit 2; }
      CONFIG_FILE="$2"; shift 2
      ;;
    --session-root)
      [[ $# -ge 2 ]] || { echo "ERROR: --session-root requires a directory" >&2; exit 2; }
      SESSION_ROOT="$2"; shift 2
      ;;
    --session-root=*) SESSION_ROOT="${1#--session-root=}"; shift ;;
    --global-config=*) CONFIG_FILE="${1#--global-config=}"; shift ;;
    -*) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    *)
      [[ -z "${TARGET}" ]] || { echo "ERROR: unexpected argument: $1" >&2; exit 2; }
      TARGET="$1"; shift
      ;;
  esac
done

if [[ -z "${TARGET}" ]]; then
  echo "ERROR: <path> is required (the file or directory the action concerns)" >&2
  exit 2
fi

python3 - "${SHARED_DIR}" "${TARGET}" "${CONFIG_FILE}" "${OUTPUT_FORMAT}" "${KEY}" "${SESSION_ROOT}" <<'PY'
import json
import os
import sys

shared, target, config_path, fmt, raw_key, session_root = sys.argv[1:7]
key = raw_key.replace("-", "_")
sys.path.insert(0, shared)

from read_jsonc import load_jsonc  # noqa: E402
import resolve_project  # noqa: E402

projects = resolve_project.load_projects(config_path)
owner = resolve_project.resolve_project(target, projects)
if session_root and not os.path.isdir(session_root):
    print(f"ERROR: --session-root is not a directory: {session_root}", file=sys.stderr)
    sys.exit(2)

if not owner:
    print(
        f"ERROR: no registered project contains {os.path.realpath(target)} "
        f"(add it to the projects array in {config_path})",
        file=sys.stderr,
    )
    sys.exit(3)

DEFAULTS = {
    "devbot_dir": ".agents",
    "datasources": [],
    "modules": {},
}

WORKSPACE_DEFAULTS = {
    "type": "repo",
    "commit_memory": "false",
    "workflow": "worktrees",
}

PROJECT_CONFIG = os.path.join(owner, ".devbot.project.jsonc")


def _get(config_file, name):
    try:
        data = load_jsonc(config_file)
    except FileNotFoundError:
        return None
    except Exception as exc:
        # A malformed config must not read as "key absent" — report it to the
        # MCP log so a parse error is distinguishable from a missing key.
        print(f"WARNING: {config_file}: {exc}", file=sys.stderr)
        return None
    if not isinstance(data, dict) or name not in data:
        return None
    return data[name]


def resolve_scalar(name):
    """Scalar: project value, then global value, then the built-in default.

    One precedence for every reader — resolve_project.resolve_setting also
    serves _devbot_get_config and the devbot-cli / memory Python tools.
    """
    return resolve_project.resolve_setting(
        config_path, owner, name, DEFAULTS.get(name, "")
    )


def resolve_workspace(name):
    """`workspace.<name>`: project value, then global value, then the default."""
    value = resolve_project.resolve_setting(
        config_path,
        owner,
        name,
        WORKSPACE_DEFAULTS.get(name, ""),
        section="workspace",
    )
    return as_text(value)


def resolve_datasources():
    """The owner's opt-in selection.

    The global `datasources` key is the machine-wide catalogue, not a selection
    (see docs/configuration.md), so it must never stand in for the project's
    list.
    """
    value = _get(PROJECT_CONFIG, "datasources")
    return value if isinstance(value, list) else []


def resolve_modules():
    """Per-key merge, the project value winning (matches _devbot_get_disabled_modules)."""
    merged = {}
    for candidate in (config_path, PROJECT_CONFIG):
        value = _get(candidate, "modules")
        if isinstance(value, dict):
            merged.update(value)
    return merged


def as_text(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (list, dict)):
        return json.dumps(value, sort_keys=True)
    return str(value)


def _config_dir():
    """The checkout whose harness config describes the live session.

    `--session-root` (or DEV_BOT_PROJECT_ROOT) names it outright and is never
    walked — a parent workspace's unrelated config must not leak in. Only the
    owner fallback searches ancestors.
    """
    if session_root:
        return os.path.realpath(session_root)
    cur = os.path.realpath(owner)
    while True:
        if os.path.isfile(os.path.join(cur, "opencode.jsonc")) or os.path.isfile(
            os.path.join(cur, ".mcp.json")
        ):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        cur = parent


def escape_cell(value):
    """A markdown table cell cannot carry a pipe or a line break."""
    return " ".join(str(value).split()).replace("|", "\\|")


def _one_line(exc):
    """A message that survives embedding in a markdown table row."""
    return " ".join(str(exc).split())


def _server_state(name, cfg, source, errors):
    """One server's state, or None when its flag is not usable.

    The two harnesses spell the switch oppositely: opencode-v2 writes
    `disabled: true` to wire a server without starting it, while a v1 config
    writes `enabled: false`. A server with neither flag is on. The value must be
    a real boolean — `"false"` or null must not read as on.
    """
    for flag, inverted in (("disabled", True), ("enabled", False)):
        if flag not in cfg:
            continue
        value = cfg[flag]
        if not isinstance(value, bool):
            errors.append(f"{source}: server `{name}` has a non-boolean `{flag}`")
            return None
        on = (not value) if inverted else value
        return "enabled" if on else "disabled"
    return "enabled"


def resolve_mcps():
    """Configured per-server state from the generated harness config.

    Always reads both shapes: opencode's `mcp` map is authoritative per server
    (`enabled: false` = wired but not started), while a `.mcp.json` entry only
    adds servers, because Claude Code has no per-server switch. This is
    configuration, not reachability: an enabled entry can still be offline or
    unauthenticated. A config that cannot be read, parsed, or shaped is reported
    through `mcps_errors` — collapsing it to an empty map would read as "server
    absent". Only those expected failures are caught: a programmer error must
    surface instead of masquerading as a bad config.
    """
    root = _config_dir()
    state, urls, sources, errors = {}, {}, [], []
    declared = set()
    if root:
        opencode = os.path.join(root, "opencode.jsonc")
        claudecode = os.path.join(root, ".mcp.json")
        if os.path.isfile(opencode):
            sources.append(opencode)
            try:
                data = load_jsonc(opencode)
                if not isinstance(data, dict):
                    raise ValueError("top level is not an object")
                # Default only when absent: `or {}` would hide null and [].
                mcp = data["mcp"] if "mcp" in data else {}
                if not isinstance(mcp, dict):
                    raise ValueError("`mcp` is not an object")
                # opencode-v2 nests the per-server map under `mcp.servers`; a
                # v1 config is the map itself. Reading only the outer keys
                # reported one bogus server named `servers`. Key presence, not
                # shape, decides: a malformed `servers` must not be mistaken
                # for a v1 map and silently report the wrong servers.
                if "servers" in mcp:
                    nested = mcp["servers"]
                    if not isinstance(nested, dict):
                        raise ValueError("`mcp.servers` is not an object")
                    servers = nested
                else:
                    servers = mcp
            except (OSError, ValueError) as exc:
                errors.append(f"{opencode}: {_one_line(exc)}")
                servers = {}
            for name, cfg in servers.items():
                # Recorded before the shape check: a name opencode declares but
                # cannot read is still opencode's, and `.mcp.json` must not
                # fill it in as enabled below.
                declared.add(name)
                if not isinstance(cfg, dict):
                    errors.append(f"{opencode}: server `{name}` is not an object")
                    continue
                # The endpoint identifies the server; the key is a local label
                # (one name per OAuth account — see `resolve_atlassian_server`).
                if isinstance(cfg.get("url"), str):
                    urls[name] = cfg["url"]
                status_of = _server_state(name, cfg, opencode, errors)
                if status_of is not None:
                    state[name] = status_of
        if os.path.isfile(claudecode):
            sources.append(claudecode)
            try:
                with open(claudecode, encoding="utf-8") as fh:
                    data = json.load(fh)
                if not isinstance(data, dict):
                    raise ValueError("top level is not an object")
                servers = data["mcpServers"] if "mcpServers" in data else {}
                if not isinstance(servers, dict):
                    raise ValueError("`mcpServers` is not an object")
            except (OSError, ValueError) as exc:
                errors.append(f"{claudecode}: {_one_line(exc)}")
                servers = {}
            for name, cfg in servers.items():
                if not isinstance(cfg, dict):
                    errors.append(f"{claudecode}: server `{name}` is not an object")
                    continue
                # opencode is the per-server authority, so this file only adds
                # servers. Filling in a name opencode errored on would report
                # `enabled` while `mcps_errors` says the entry is broken.
                if name in declared:
                    continue
                if isinstance(cfg.get("url"), str):
                    urls.setdefault(name, cfg["url"])
                state.setdefault(name, "enabled")
    # Sorted: the report must not change shape with the config's key order.
    return (
        dict(sorted(state.items())),
        dict(sorted(urls.items())),
        sources,
        errors,
    )


# The module's canonical endpoint (`src/agentic/atlassian/mcp.json`). Atlassian
# hosts the Rovo MCP server, so the URL is stable across projects.
ROVO_ENDPOINTS = ("https://mcp.atlassian.com/v2/mcp",)


def resolve_atlassian_server(state, urls):
    """The configured Atlassian server, resolved by endpoint rather than name.

    opencode stores OAuth credentials per server *name*, so a project that needs
    a second Jira account registers the same endpoint under a second name
    (`atlassian-wedding`). Reading the literal key `atlassian` therefore misses
    it, and a `devbot reinit` can put a disabled `atlassian` stub back beside the
    live server. Resolving by URL finds the server whichever name it carries,
    and preferring the enabled candidate makes the stub irrelevant.

    Returns `{name, state}`, with `candidates` whenever `name` is null: two live
    servers, or several entries with none live. Nothing is picked in those
    cases — the canonical stub sorts first and enabling it would sign the
    project back into the other account.
    """
    candidates = sorted(
        name
        for name, url in urls.items()
        if url.rstrip("/") in ROVO_ENDPOINTS
    )
    live = [name for name in candidates if state.get(name) == "enabled"]
    if len(live) > 1:
        # Two signed-in accounts behind one endpoint: picking either would
        # silently file the ticket against the wrong site.
        return {"name": None, "state": "ambiguous", "candidates": live}
    if live:
        return {"name": live[0], "state": "enabled"}
    if not candidates:
        return {"name": None, "state": "missing"}
    if len(candidates) == 1:
        # A name is worth reporting only when there is nothing to choose
        # between. Absent from `state` means the flag was unreadable, which is
        # a config fault — not "off, so enable it".
        only = candidates[0]
        return {"name": only, "state": state.get(only, "error")}
    broken = [name for name in candidates if name not in state]
    return {
        "name": None,
        "state": "error" if broken else "disabled",
        "candidates": candidates,
    }


mcps_state, mcps_urls, mcps_sources, mcps_errors = resolve_mcps()

resolved = {
    "commit_memory": resolve_workspace("commit_memory"),
    "workflow": resolve_workspace("workflow"),
    "type": resolve_workspace("type"),
    "devbot_dir": as_text(resolve_scalar("devbot_dir")),
    "datasources": resolve_datasources(),
    "modules": resolve_modules(),
    "mcps": mcps_state,
    "atlassian_server": resolve_atlassian_server(mcps_state, mcps_urls),
    "mcps_sources": mcps_sources,
    "mcps_errors": mcps_errors,
}

if key:
    if key not in resolved:
        known = ", ".join(sorted(resolved)).replace("_", "-")
        print(f"ERROR: unknown key '{raw_key}' (known: {known}; dashes map to underscores)", file=sys.stderr)
        sys.exit(2)
    # An unreadable config and one with no servers are different failures: the
    # first must not send the user to "enable" a server that is already there.
    # Every gate reads `atlassian_server`, so that key needs the same guard —
    # otherwise a broken config tells the agent "no Atlassian server".
    if key == "mcps" and not resolved["mcps"] and resolved["mcps_errors"]:
        print(
            f"ERROR: cannot read the harness MCP config: {'; '.join(resolved['mcps_errors'])}",
            file=sys.stderr,
        )
        sys.exit(2)
    if (
        key == "atlassian_server"
        and resolved["atlassian_server"]["state"] == "missing"
        and resolved["mcps_errors"]
    ):
        print(
            f"ERROR: cannot read the harness MCP config: {'; '.join(resolved['mcps_errors'])}",
            file=sys.stderr,
        )
        sys.exit(2)
    value = resolved[key]
    print(as_text(value) if not isinstance(value, (list, dict)) else json.dumps(value))
    sys.exit(0)

report = {
    "name": os.path.basename(owner.rstrip("/")),
    "path": owner,
    "registered": True,
    "type": resolved["type"],
    "config": {
        "commit_memory": as_text(resolved["commit_memory"]),
        "workflow": as_text(resolved["workflow"]),
        "devbot_dir": as_text(resolved["devbot_dir"]),
        "datasources": resolved["datasources"] or [],
        "modules": resolved["modules"] or {},
        "mcps": resolved["mcps"] or {},
        "atlassian_server": resolved["atlassian_server"],
        "mcps_sources": resolved["mcps_sources"],
        "mcps_errors": resolved["mcps_errors"],
    },
}

if fmt == "json":
    print(json.dumps(report, indent=2))
    sys.exit(0)

datasources = report["config"]["datasources"]
modules = report["config"]["modules"]
print("## Owning project")
print()
print(f"**Name:** {report['name']}")
print(f"**Path:** {report['path']}")
print(f"**Type:** {report['type']}")
print()
print("| Key | Value |")
print("| --- | --- |")
print(f"| commit_memory | {escape_cell(report['config']['commit_memory'])} |")
print(f"| workflow | {escape_cell(report['config']['workflow'])} |")
print(f"| devbot_dir | {escape_cell(report['config']['devbot_dir'])} |")
print(f"| datasources | {escape_cell(', '.join(datasources) if datasources else '(none)')} |")
if modules:
    rendered = ", ".join(f"{name}:{'true' if enabled else 'false'}" for name, enabled in sorted(modules.items()))
else:
    rendered = "(all enabled)"
print(f"| modules | {escape_cell(rendered)} |")
mcps = report["config"]["mcps"]
sources = report["config"]["mcps_sources"]
errors = report["config"]["mcps_errors"]
if mcps:
    served = ", ".join(f"{name}:{state}" for name, state in sorted(mcps.items()))
elif sources:
    served = "(config found, no MCP servers declared)"
else:
    served = "(no harness config found)"
print(f"| mcps | {escape_cell(served)} |")
if sources:
    print(f"| mcps source | {escape_cell(', '.join(sources))} |")
if errors:
    print(f"| mcps error | {escape_cell('; '.join(errors))} |")
atlassian = report["config"]["atlassian_server"]
if atlassian["name"]:
    atlassian_cell = f"{atlassian['name']}:{atlassian['state']}"
elif atlassian.get("candidates"):
    atlassian_cell = f"{atlassian['state']} ({', '.join(atlassian['candidates'])})"
else:
    atlassian_cell = atlassian["state"]
print(f"| atlassian server | {escape_cell(atlassian_cell)} |")
PY
