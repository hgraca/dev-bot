#!/usr/bin/env bash
# =============================================================================
# src/harnesses/claudecode/start.sh
# Starts Claude Code in the project.
#
# This is what `devbot` (cmd_harness in bin/devbot) uses to launch Claude Code.
# The session agent is NOT forced here — it comes from .claude/settings.json
# `agent`, which init.sh offers to set to DevBot.
#
# Usage:
#   start.sh [project_dir] [claude args...]
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

bin="$(command -v claude 2>/dev/null || true)"
if [[ -z "${bin}" ]]; then
  _fatal "claude binary not found on PATH (install with: npm install -g @anthropic-ai/claude-code)"
  exit 1
fi

# Rotate the previous session's logs (dated + 3-digit suffix, preserved under
# .agents/logs/rotated/) so the post-exit check only sees this session's
# entries. Fail open: if logs can't be rotated, the check still runs.
_devbot_rotate_session_logs "${PROJECT_DIR}"

# Run the harness as a child (not exec) so the session-error check can run
# after it exits; preserve the harness exit code for the caller.
harness_exit=0
"${bin}" "$@" || harness_exit=$?

_devbot_check_session_logs "${PROJECT_DIR}"

exit "${harness_exit}"
