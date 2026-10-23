#!/usr/bin/env bash
# ---
# description: Resolve a path to the registered devbot project that owns it, and report that project's effective configuration.
# ---
# =============================================================================
# src/tools/devbot-cli/tools/project-for-path.mcp.sh
# A supervisor session has no single current project: every project-scoped
# action must first find the project that owns the files it touches. This tool
# is that lookup plus the owner's effective config: scalars resolve
# project-first then global; `modules` merges per key; `datasources` is the
# project's own opt-in selection.
#
# Usage:
#   project-for-path.mcp.sh <path>                    # markdown table
#   project-for-path.mcp.sh <path> --json             # JSON object
#   project-for-path.mcp.sh <path> --key workflow     # one resolved value
#   project-for-path.mcp.sh <path> --global-config F  # non-default registry
#
# Exit codes: 0 resolved, 2 usage error, 3 no registered project contains <path>.
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"project-for-path","description":"Resolve a path to the registered devbot project that owns it (longest registered prefix in .devbot.global.jsonc), and report that project's effective commit_memory, workflow, devbot_dir, datasources and modules. Use it in a supervisor session before any project-scoped action.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: <path> [--json] [--key <name>] [--global-config <file>]"}},"required":["args"]}}
JSON
    exit 0
    ;;
  -h | --help)
    sed -n '7,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

python3 - "${SHARED_DIR}" "${TARGET}" "${CONFIG_FILE}" "${OUTPUT_FORMAT}" "${KEY}" <<'PY'
import json
import os
import sys

shared, target, config_path, fmt, key = sys.argv[1:6]
sys.path.insert(0, shared)

from read_jsonc import load_jsonc  # noqa: E402
import resolve_project  # noqa: E402

projects = resolve_project.load_projects(config_path)
owner = resolve_project.resolve_project(target, projects)
if not owner:
    print(
        f"ERROR: no registered project contains {os.path.realpath(target)} "
        f"(add it to the projects array in {config_path})",
        file=sys.stderr,
    )
    sys.exit(3)

DEFAULTS = {
    "commit_memory": "false",
    "workflow": "worktrees",
    "devbot_dir": ".agents",
    "datasources": [],
    "modules": {},
    "supervisor": "false",
}

PROJECT_CONFIG = os.path.join(owner, ".devbot.project.jsonc")


def _get(config_file, name):
    try:
        data = load_jsonc(config_file)
    except Exception:
        return None
    if not isinstance(data, dict) or name not in data:
        return None
    return data[name]


def resolve_scalar(name):
    """Scalar: project value, then global value, then the built-in default."""
    for candidate in (PROJECT_CONFIG, config_path):
        value = _get(candidate, name)
        if value is not None and value != "":
            return value
    return DEFAULTS.get(name, "")


def resolve_workflow():
    """The effective workflow: `workflow`, else the retired `worktrees` key
    (true -> worktrees, false -> trunk) until `devbot update` migrates it."""
    for candidate in (PROJECT_CONFIG, config_path):
        value = _get(candidate, "workflow")
        if value is not None and value != "":
            return as_text(value)
        legacy = _get(candidate, "worktrees")
        if legacy is not None:
            return {"true": "worktrees", "false": "trunk"}.get(as_text(legacy), as_text(legacy))
    return DEFAULTS["workflow"]


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


resolved = {
    "commit_memory": as_text(resolve_scalar("commit_memory")),
    "workflow": resolve_workflow(),
    "devbot_dir": as_text(resolve_scalar("devbot_dir")),
    "datasources": resolve_datasources(),
    "modules": resolve_modules(),
}
resolved["supervisor"] = as_text(resolve_scalar("supervisor")) == "true"

if key:
    if key not in resolved:
        print(f"ERROR: unknown key '{key}' (known: {', '.join(sorted(resolved))})", file=sys.stderr)
        sys.exit(2)
    value = resolved[key]
    print(as_text(value) if not isinstance(value, (list, dict)) else json.dumps(value))
    sys.exit(0)

report = {
    "name": os.path.basename(owner.rstrip("/")),
    "path": owner,
    "registered": True,
    "supervisor": resolved["supervisor"],
    "config": {
        "commit_memory": as_text(resolved["commit_memory"]),
        "workflow": as_text(resolved["workflow"]),
        "devbot_dir": as_text(resolved["devbot_dir"]),
        "datasources": resolved["datasources"] or [],
        "modules": resolved["modules"] or {},
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
print(f"**Supervisor:** {'yes' if report['supervisor'] else 'no'}")
print()
print("| Key | Value |")
print("| --- | --- |")
print(f"| commit_memory | {report['config']['commit_memory']} |")
print(f"| workflow | {report['config']['workflow']} |")
print(f"| devbot_dir | {report['config']['devbot_dir']} |")
print(f"| datasources | {', '.join(datasources) if datasources else '(none)'} |")
if modules:
    rendered = ", ".join(f"{name}:{'true' if enabled else 'false'}" for name, enabled in sorted(modules.items()))
else:
    rendered = "(all enabled)"
print(f"| modules | {rendered} |")
PY
