#!/usr/bin/env bash
# src/agentic/sonarqube/serve.mcp.sh
# Launch the official SonarQube MCP server container over stdio.
#
# Symlinked into the project harness dirs by init.sh:
#   .opencode/sonarqube-serve.mcp.sh
#   .claude/sonarqube-serve.mcp.sh
#
# One container per harness instance, started only when the MCP entry is
# enabled, so a user who never turns SonarQube on pays nothing. `--rm` reaps it
# at session teardown.
#
# The token is passed with `-e VAR` (no value): docker copies it from this
# process's environment, so the secret never appears in argv or a config file.
#
# stderr is captured by the mcp.json `bash -c` into .agents/logs/.
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

# Resolve the real module dir through the symlink (versions.env lives there).
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SOURCE}" ]]; do
  DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
  SOURCE="$(readlink "${SOURCE}")"
  [[ "${SOURCE}" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
MODULE_DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

IMAGE="$(_sonarqube_image)"

if [[ -z "${SONARQUBE_TOKEN:-}" ]]; then
  echo "FATAL: SONARQUBE_TOKEN is unset — the SonarQube MCP server cannot authenticate." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "FATAL: docker is required to run the SonarQube MCP server. Run 'devbot install' (module sonarqube)." >&2
  exit 1
fi

ARGS=(run --init --rm -i --pull=missing)
ENV_ARGS=(-e SONARQUBE_TOKEN)
for var in SONARQUBE_URL SONARQUBE_ORG SONARQUBE_PROJECT_KEY SONARQUBE_TOOLSETS SONARQUBE_READ_ONLY; do
  [[ -n "${!var:-}" ]] && ENV_ARGS+=(-e "${var}")
done

# The workspace mount lets analysis tools read files by relative path instead
# of receiving their content through the context window. Read-only by default;
# opt out with SONARQUBE_WORKSPACE_MOUNT=false, or use rw with
# SONARQUBE_WORKSPACE_MODE=rw if an analysis call needs to write there.
# Cache analyzers: the sync dominates startup.
# Without it, every launch re-downloads plugins.
STORAGE_ARGS=(-v "devbot-sonarqube-mcp-storage:/app/storage")

MOUNT_ARGS=()
if [[ "${SONARQUBE_WORKSPACE_MOUNT:-true}" != "false" && -d "${PWD}" ]]; then
  case "${SONARQUBE_WORKSPACE_MODE:-ro}" in
    ro | rw) MOUNT_MODE="${SONARQUBE_WORKSPACE_MODE:-ro}" ;;
    *) MOUNT_MODE="ro" ;;
  esac
  MOUNT_ARGS+=(-v "${PWD}:/app/mcp-workspace:${MOUNT_MODE}")
fi

# ${arr[@]+...} keeps an empty MOUNT_ARGS safe under set -u on bash 3.2
# (macOS /bin/bash), where a bare "${arr[@]}" is an unbound-variable error.
exec docker "${ARGS[@]}" "${ENV_ARGS[@]}" "${STORAGE_ARGS[@]}" ${MOUNT_ARGS[@]+"${MOUNT_ARGS[@]}"} "${IMAGE}"
