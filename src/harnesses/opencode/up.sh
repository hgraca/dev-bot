#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode/up.sh
# Pre-launch check for the opencode harness: refuses an opencode 2.x host.
#
# dev-bot's hooks and TUI plugins use the opencode V1 plugin API, which v2
# replaced — on a v2 host none of them load. Runs on `devbot`, `devbot up` and
# `make up` (auto-discovered by bin/up.sh).
#
# A non-zero exit here is REPORTED but not fatal to the start sequence:
# _run_service_scripts warns about a failed module script and still
# returns 0. start.sh re-runs the same check, and only there is the launch
# actually refused.
#
# Usage:
#   up.sh [project_dir]
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# The unselected harness is disabled, so _run_service_scripts skips this here.
# The guard below only covers a direct invocation.
if [[ "$(_devbot_get_harness "${1:-.}")" != "opencode" ]]; then
  exit 0
fi

if ! _devbot_require_opencode_1x; then
  exit 1
fi

# Converge the herdr pane-title TUI plugin: a project seeded before the plugin
# existed has neither the symlink nor the tui.json entry. init.sh seeds both, but
# it only runs on init/reinit, so a launch closes the gap too.
#
# Not EVERY launch: bin/devbot skips bin/up.sh entirely when bin/up.sh --is-up
# reports a completed start, so a relaunch inside an already-up project reaches
# this only when the start was redone (a version bump, a config change).
#
# The herdr check governs usefulness, not correctness: the plugin is inert
# outside a herdr pane, but a project on a machine without the terminal has no
# use for the wiring. HERDR_BIN_PATH counts as installed — herdr sets it on hosts
# where the binary is not on PATH.
if command -v herdr >/dev/null 2>&1 || [[ -n "${HERDR_BIN_PATH:-}" ]]; then
  _ensure_tui_plugin "${1:-.}" herdr-pane-title || true
elif [[ -n "${HERDR_ENV:-}" ]]; then
  _skip "tui-plugins/herdr-pane-title: herdr is not installed — not wired"
fi
