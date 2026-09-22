#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-index/reset.sh
# Removes codebase-index files for a project: config files by default,
# or index data only when --full is passed (config preserved).
#
# The default also reclaims the index store when this module is disabled — which
# is what a `codebase_index_provider` flip to codebase-memory looks like from
# here. See the prune below.
#
# Usage:
#   reset.sh /path/to/project            # config files, plus the index store
#                                        # when this engine has been retired
#   reset.sh /path/to/project --full     # remove index data only (preserve config)
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SHARED_DIR="$(cd "${MODULE_DIR}/../../_shared" && pwd)"

# Force-correct before sourcing: _shared/functions.sh computes DEV_BOT_ROOT from
# its OWN location — one level too deep — and this script is documented for
# direct invocation. A mis-resolved root means the real global config is never
# found and the provider lookup falls back to its default, which is what decides
# whether the index store gets destroyed below.
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="${1:-}"
FULL_RESET=false

# Parse optional second arg
case "${2:-}" in
  --full) FULL_RESET=true ;;
esac

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  echo "Usage: reset.sh <project_dir> [--full]" >&2
  exit 1
fi

_header_3 "Codebase Index Reset"

OPENCODE_CONFIG="${PROJECT_DIR}/.opencode/codebase-index.json"
CLAUDE_CONFIG="${PROJECT_DIR}/.claude/codebase-index.json"
OPENCODE_INDEX="${PROJECT_DIR}/.opencode/index"
CLAUDE_INDEX="${PROJECT_DIR}/.claude/index"

removed=0

# True when another codebase engine owns this project. `devbot reinit` runs
# every module's reset.sh — disabled ones included — so a flip to
# codebase-memory is observable from here, and this is the only place it passes
# through.
#
# Only a POSITIVE answer may authorise destroying the store, so an existing-but-
# unreadable global config stops us: _devbot_get_codebase_provider() maps "cannot
# read the provider" onto the same codebase-memory default as a real flip, and a
# corrupt config must not be what deletes a live engine's index. A MISSING config
# really is the default (codebase-memory), so that case does prune.
_codebase_index_is_disabled() {
  local project_dir="${1:-}"
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"

  if [[ -f "${global_config}" ]] &&
    ! python3 "${_SHARED_DIR}/read_jsonc.py" "${global_config}" codebase_index_provider >/dev/null 2>&1; then
    _warn "codebase-index — ${global_config} is unreadable; keeping the index store"
    return 1
  fi

  # The disabled list is JSON; an exact quoted token cannot match a longer module
  # name. Same idiom as _devbot_prune_memories_detached in functions.sh.
  _devbot_get_disabled_modules "${project_dir}" | grep -q '"codebase-index"'
}

# Index data is rebuildable, so removing it never loses work — the engine
# re-indexes at the next session. These are the only two things a reset can do;
# which of them runs is the whole policy.
_remove_store() {
  if [[ -d "${OPENCODE_INDEX}" ]]; then
    rm -rf "${OPENCODE_INDEX}"
    _ok "Removed .opencode/index/"
    removed=$((removed + 1))
  else
    _skip "No .opencode/index/"
  fi

  if [[ -d "${CLAUDE_INDEX}" ]]; then
    rm -rf "${CLAUDE_INDEX}"
    _ok "Removed .claude/index/"
    removed=$((removed + 1))
  else
    _skip "No .claude/index/"
  fi
}

_remove_configs() {
  if [[ -f "${OPENCODE_CONFIG}" ]]; then
    rm -f "${OPENCODE_CONFIG}"
    _ok "Removed .opencode/codebase-index.json"
    removed=$((removed + 1))
  else
    _skip "No .opencode/codebase-index.json"
  fi

  if [[ -f "${CLAUDE_CONFIG}" ]]; then
    rm -f "${CLAUDE_CONFIG}"
    _ok "Removed .claude/codebase-index.json"
    removed=$((removed + 1))
  else
    _skip "No .claude/codebase-index.json"
  fi
}

if [[ "${FULL_RESET}" == "true" ]]; then
  # --full: index data only, config preserved.
  _remove_store
elif _codebase_index_is_disabled "${PROJECT_DIR}"; then
  # Retired engine: nothing will read this store again, so leaving it is dead
  # weight (tens of MB on a real project) plus a background-worker lease that
  # can confuse a future boot. Config files go too — the flip already dropped
  # the plugin/MCP registration that used them.
  _remove_configs
  _remove_store
else
  # Still the project's engine: drop the config (init regenerates it) and keep
  # the index, which is expensive to rebuild.
  _remove_configs
fi

if [[ ${removed} -eq 0 ]]; then
  _skip "Nothing to reset"
fi
