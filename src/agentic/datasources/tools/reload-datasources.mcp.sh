#!/usr/bin/env bash
# ---
# description: Re-evaluate the datasource catalogue against the network as it is now, then verify the shared gateway serves every selected source
# ---
# =============================================================================
# src/agentic/datasources/tools/reload-datasources.mcp.sh
# MCP wrapper for `devbot datasources reload`, so an agent can recover a source
# that was unreachable when the session booted without a restart.
#
# The reload exits 1 when any selected source is still unserved, and the
# devbot-tools server surfaces stderr instead of stdout once a tool exits
# non-zero having written to both — so propagating that status would hide every
# per-source result the agent needs. This wrapper therefore flattens the whole
# transcript onto stdout, names the project it acted on, and ends with an
# explicit outcome line for each documented status (0, 1, 2). Any other status
# means the reload could not run at all: that is a tool malfunction, not a
# result, so the call fails.
#
# Usage:
#   reload-datasources.mcp.sh                     # TOOLS_MCP_PROJECT_DIR, else cwd
#   reload-datasources.mcp.sh --project <dir>     # another project (polyrepo)
#
# Dependencies: docker, curl (the reload's own preflight)
# =============================================================================

# Deliberately not -e: the reload's non-zero status is a result to report.
set -uo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"reload-datasources","description":"Re-evaluate the datasource catalogue against the network as it is now and verify the shared gateway serves it. Use when a datasource was unreachable when the session started (a VPN that was down, a local database not yet up) and its MCP tool is failing to connect: this starts what became reachable, renders the config and proves every selected source answers, without restarting the session. Reports per-source results and a final 'reload: complete', 'reload: not complete' (the render applied, a source is still unserved) or 'reload: not applied' (nothing ran, no config changed) line.","timeoutMs":900000,"parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: [--project <dir>] — the project whose datasources to reload; defaults to the session project"}},"required":["args"]}}
JSON
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
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# The server exports the project it was launched for: the inherited cwd is not
# authoritative, and a wrong one reloads nothing and still looks like success.
project="${TOOLS_MCP_PROJECT_DIR:-$(pwd)}"
if [[ "${1:-}" == "--project" ]]; then
  project="${2:-}"
  if [[ -z "${project}" ]]; then
    echo "ERROR: --project needs a directory" >&2
    exit 2
  fi
  shift 2
fi

project="$(cd "${project}" 2>/dev/null && pwd)" || {
  echo "ERROR: no such project directory: ${project}" >&2
  exit 2
}

# A plain directory has no selection, so the reload would verify nothing and
# report a clean result. Refuse it instead of confirming an empty run.
if [[ ! -f "${project}/.devbot.project.jsonc" ]]; then
  echo "ERROR: not a devbot project: ${project}" >&2
  exit 2
fi

reload="${DATASOURCES_RELOAD_SCRIPT:-${MODULE_DIR}/reload.sh}"
if [[ ! -f "${reload}" ]]; then
  echo "ERROR: reload script not found: ${reload}" >&2
  exit 2
fi

output="$(bash "${reload}" "${project}" 2>&1)"
status=$?

printf 'project: %s\n' "${project}"
printf '%s\n' "${output}"
printf -- '---\n'
case "${status}" in
  0) echo "reload: complete" ;;
  1) echo "reload: not complete (exit 1) — applied; the transcript names what is unserved" ;;
  2) echo "reload: not applied (exit 2) — nothing changed; the transcript says why" ;;
  *)
    echo "reload: could not run (exit ${status}) — see the transcript above"
    exit "${status}"
    ;;
esac

exit 0
