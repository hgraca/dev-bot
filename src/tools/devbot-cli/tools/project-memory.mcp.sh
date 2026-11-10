#!/usr/bin/env bash
# ---
# description: Print the active memory a project loads for itself — its AGENTS.md/CLAUDE.md and <devbot_dir>/memory/active/**/*.md — labelled by file and scoped to that project.
# ---
# =============================================================================
# src/tools/devbot-cli/tools/project-memory.mcp.sh
# In a polyrepo session the agent works across many projects, each with its
# own always-on context. This tool loads the owning project's memory in one
# call, labelled by file and scoped to that project, so rules read here do not
# leak into sibling projects or into the polyrepo's coordination work.
#
# Usage:
#   project-memory.mcp.sh <path>                    # active memory of the owner
#   project-memory.mcp.sh <path> --global-config F  # non-default registry
#
# Exit codes: 0 printed (including "no active memory"), 2 usage error,
#             3 no registered project contains <path>.
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"project-memory","description":"Print the always-on memory of the registered devbot project that owns <path>: its AGENTS.md and CLAUDE.md when present, plus <devbot_dir>/memory/active/**/*.md. Each file is labelled and the output is scoped to that project. Run it once before the first read or edit in a project during a polyrepo session.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: <path> [--global-config <file>]"}},"required":["args"]}}
JSON
    exit 0
    ;;
  -h | --help)
    sed -n '12,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
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

python3 - "${SHARED_DIR}" "${TARGET}" "${CONFIG_FILE}" <<'PY'
import os
import sys

shared, target, config_path = sys.argv[1:4]
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

owner = os.path.realpath(owner)


def project_config(name, default=""):
    for candidate in (os.path.join(owner, ".devbot.project.jsonc"), config_path):
        try:
            data = load_jsonc(candidate)
        except Exception:
            continue
        if isinstance(data, dict):
            value = data.get(name)
            if isinstance(value, str) and value:
                return value
    return default


devbot_dir = project_config("devbot_dir", ".agents")
devbot_dir = devbot_dir if os.path.isabs(devbot_dir) else os.path.join(owner, devbot_dir)
active_dir = os.path.join(devbot_dir, "memory", "active")

files = [os.path.join(owner, name) for name in ("AGENTS.md", "CLAUDE.md")]
files = [path for path in files if os.path.isfile(path)]

active_files = []
if os.path.isdir(active_dir):
    for root, _dirs, names in os.walk(active_dir):
        active_files.extend(
            os.path.join(root, name) for name in names if name.endswith(".md")
        )
files.extend(sorted(active_files, key=lambda path: os.path.relpath(path, owner)))


def label(path):
    rel = os.path.relpath(path, owner)
    return f"{rel} -> {os.path.realpath(path)}" if os.path.islink(path) else rel

print(f"## Active memory for {os.path.basename(owner.rstrip(os.sep))}")
print()
print(f"**Path:** {owner}")
print(
    "**Scope:** applies only within this project. Do not carry these rules into "
    "other projects or into the polyrepo's coordination work."
)
print()

if not files:
    print(
        "No active memory: no AGENTS.md, CLAUDE.md, or "
        f"{os.path.relpath(active_dir, owner)}/**/*.md found."
    )
    sys.exit(0)

print(f"**Files:** {len(files)}")
for path in files:
    print()
    print(f"### {label(path)}")
    print()
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            content = handle.read().strip()
    except OSError as error:
        content = f"_(unreadable: {error})_"
    print(content or "_(empty)_")
PY
