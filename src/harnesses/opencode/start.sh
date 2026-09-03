#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode/start.sh
# Starts OpenCode in the project.
#
# This is what `devbot` (cmd_harness in bin/devbot) uses to launch OpenCode.
# The session agent is NOT forced here — it comes from the project's
# opencode.jsonc `default_agent`, which init.sh offers to set to DevBot.
#
# Usage:
#   start.sh [project_dir] [opencode args...]
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"
if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "project directory not found: ${1:-$(pwd)}"
  exit 1
fi
shift || true

# Open the requested project so the harness resolves its config there.
cd "${PROJECT_DIR}"

bin="${HOME}/.opencode/bin/opencode"
if [[ ! -f "${bin}" ]]; then
  _fatal "opencode binary not found at ${bin}"
  exit 1
fi

# Rotate the previous session's logs (dated + 3-digit suffix, preserved under
# .agents/logs/rotated/) so the post-exit check only sees this session's
# entries. Fail open: if logs can't be rotated, the check still runs.
_devbot_rotate_session_logs "${PROJECT_DIR}"

# Fire the memory delete→prune self-heal detached BEFORE the harness boots
# (audit-34 NOTE-8 / audit-35 FAIL): qmd cleanup gets a head start ahead of
# the MCP fleet boot and the prune runs per launch, not only on the first
# session.created of a process. Fail-open — never blocks the launch.
_devbot_prune_memories_detached "${PROJECT_DIR}" || true

# Run the harness as a child (not exec) so the session-error check can run
# after it exits; preserve the harness exit code for the caller.
harness_exit=0
"${bin}" "$@" || harness_exit=$?

_devbot_check_session_logs "${PROJECT_DIR}"

exit "${harness_exit}"
