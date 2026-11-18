#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode/start.sh
# Starts OpenCode in the project.
#
# This is what `devbot` (cmd_harness in bin/devbot) uses to launch OpenCode.
# The session agent is NOT forced here — it comes from the project's
# opencode.jsonc `default_agent`, which init.sh offers to set to devbot.
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

# AutoBot presence lock; the trap removes it on exit. The registry records which
# harness is running, so the launcher declares its own identity here.
export DEV_BOT_HARNESS="opencode"
session_lock="$(bash "${DEV_BOT_ROOT}/src/_shared/session_lock.sh" create "${PROJECT_DIR}" session "$$" 2>/dev/null || true)"
_remove_session_lock() {
  bash "${DEV_BOT_ROOT}/src/_shared/session_lock.sh" remove "${session_lock}"
}
if [[ -n "${session_lock}" ]]; then
  trap _remove_session_lock EXIT INT TERM
fi

# `devbot --gui` (DEV_BOT_GUI=1, set by cmd_harness) opens the OpenCode desktop
# app instead of the CLI, so the CLI binary and its version are not checked then.
gui=false
[[ "${DEV_BOT_GUI:-0}" == "1" ]] && gui=true

bin="${HOME}/.opencode/bin/opencode"
if [[ "${gui}" == "false" ]]; then
  if [[ ! -f "${bin}" ]]; then
    _fatal "opencode binary not found at ${bin}"
    exit 1
  fi

  # Refuse an opencode 2.x host before doing any work: the V1 plugin API dev-bot's
  # hooks and TUI plugins are built on does not exist there, so the harness would
  # boot with none of them loaded. Checked here, not only in up.sh, because
  # _run_service_scripts swallows a module up.sh's non-zero exit — this is the
  # call that actually refuses the launch.
  if ! _devbot_require_opencode_1x; then
    exit 1
  fi
fi

# Cap the harness's own log — nothing else rotates it, and it grows without
# bound (100 MB on a dev machine, never shrunk; audit-69 NOTE-2). One rotation
# before launch; DEV_BOT_OPENCODE_LOG_MAX_BYTES overrides the 50 MB cap.
_devbot_cap_file \
  "${XDG_DATA_HOME:-${HOME}/.local/share}/opencode/log/opencode.log" \
  "${DEV_BOT_OPENCODE_LOG_MAX_BYTES:-$((50 * 1024 * 1024))}"

# Rotate the previous session's logs (dated + 3-digit suffix, preserved under
# .agents/logs/rotated/) so the post-exit check only sees this session's
# entries. Fail open: if logs can't be rotated, the check still runs.
_devbot_rotate_session_logs "${PROJECT_DIR}"

# Fire the memory delete→prune self-heal detached BEFORE the harness boots
# (audit-34 NOTE-8 / audit-35 FAIL): qmd cleanup gets a head start ahead of
# the MCP fleet boot and the prune runs per launch, not only on the first
# session.created of a process. Fail-open — never blocks the launch.
_devbot_prune_memories_detached "${PROJECT_DIR}" || true

# Gate: MCP configs registered at init may reference {env:VAR} tokens that
# must be set in THIS shell's env (the harness inherits it). If any are
# missing, ask whether to launch anyway — the affected servers would fail to
# start. Non-interactive runs (SKIP_CONFIRM / no TTY) warn and launch.
if ! _devbot_check_mcp_env_vars "${PROJECT_DIR}" gate; then
  _fatal "Aborting launch — set the missing env vars (see above), then start devbot from a new terminal."
  exit 1
fi

# Run the harness as a child (not exec) so the session-error check can run
# after it exits; preserve the harness exit code for the caller. In GUI mode
# the "harness" is the desktop app: open it, then hold until Ctrl-C so the
# devbot session (and its docker services) outlives this launcher.
harness_exit=0
if [[ "${gui}" == "true" ]]; then
  _devbot_launch_gui opencode "${PROJECT_DIR}" || harness_exit=$?
else
  "${bin}" "$@" || harness_exit=$?
fi

_devbot_check_session_logs "${PROJECT_DIR}"

exit "${harness_exit}"
