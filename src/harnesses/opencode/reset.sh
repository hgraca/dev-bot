#!/usr/bin/env bash
# =============================================================================
# src/tools/opencode/reset.sh
# Removes dev-bot-managed symlinks from .opencode/ and cleans up MCP entries
# from opencode.jsonc. Leaves user-created files and non-devbot symlinks intact.
#
# Usage:
#   reset.sh /path/to/project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="${1:-}"
if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  echo "Usage: reset.sh <project_dir>" >&2
  exit 1
fi

# ── Paths ──────────────────────────────────────────────────────────────────────
# Force-calculate DEV_BOT_ROOT from module location — _shared/functions.sh may
# have exported an incorrect value when the script runs standalone (without a
# parent process pre-setting DEV_BOT_ROOT).
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
OPENCODE_DIR="${PROJECT_DIR}/.opencode"

_header_3 "Opencode Reset"

# ── If opencode is disabled, leave the harness alone ──────────────────────────
# The user may use opencode independently of dev-bot: .opencode/ and
# opencode.jsonc may be entirely theirs. dev-bot never removes artifacts of a
# harness it is not managing — reinit must not destroy a user's setup.
# NOTE: this also means dev-bot symlinks left by a previous (enabled) init are
# kept when the module is disabled; there is no cleanup path for them while
# disabled. Re-enable the module and reset to clean them.
_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"
if echo "${_disabled_raw}" | jq -e 'index("opencode") != null' >/dev/null 2>&1; then
  _skip "opencode is disabled — leaving .opencode/ and opencode.jsonc untouched"
  exit 0
fi

if [[ ! -d "${OPENCODE_DIR}" ]]; then
  _skip "No .opencode/ directory — nothing to reset"
  exit 0
fi

# ── Remove dev-bot symlinks from .opencode/ subdirs ──────────────────────────
_reset_symlinks_in_dir() {
  local dir="$1"
  [[ -d "${dir}" ]] || return 0

  local removed=0
  while IFS= read -r -d '' link; do
    local target
    target="$(readlink "${link}" 2>/dev/null || true)"
    if [[ -z "${target}" ]]; then
      continue
    fi

    # Resolve relative symlink targets to absolute for comparison
    local link_dir
    link_dir="$(dirname "${link}")"
    local abs_target
    abs_target="$(cd "${link_dir}" 2>/dev/null && cd "${target}" 2>/dev/null && pwd 2>/dev/null || true)"
    if [[ -z "${abs_target}" ]]; then
      local rel_target="${target}"
      [[ "${rel_target}" != /* ]] && rel_target="${link_dir}/${rel_target}"
      abs_target="$(cd -P "$(dirname "${rel_target}")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "${rel_target}")" || true)"
    fi

    # Remove if target is under DEV_BOT_ROOT (dev-bot-managed)
    if [[ "${abs_target}" == "${DEV_BOT_ROOT}"/* ]]; then
      rm -f "${link}"
      removed=$((removed + 1))
    fi
  done < <(find "${dir}" -type l -print0 2>/dev/null)

  if [[ ${removed} -gt 0 ]]; then
    _ok "Removed ${removed} dev-bot symlink(s) from ${dir#"${PROJECT_DIR}/"}"
  fi

  # Also prune broken symlinks (targets that no longer exist)
  local broken=0
  while IFS= read -r -d '' link; do
    if [[ ! -e "${link}" ]]; then
      rm -f "${link}"
      broken=$((broken + 1))
    fi
  done < <(find "${dir}" -type l -print0 2>/dev/null)

  if [[ ${broken} -gt 0 ]]; then
    _ok "Removed ${broken} broken symlink(s) from ${dir#"${PROJECT_DIR}/"}"
  fi

  # Clean up empty directories
  find "${dir}" -type d -empty -delete 2>/dev/null || true
}

for subdir in agents commands skills plugins tools; do
  _reset_symlinks_in_dir "${OPENCODE_DIR}/${subdir}"
done

# ── Also clean root-level symlinks in .opencode/ ─────────────────────────────
# Some modules (tools-mcp, graphify) create MCP wrapper symlinks at the root
_reset_symlinks_in_dir "${OPENCODE_DIR}"

# ── Remove module-managed MCP keys from opencode.jsonc ─────────────────────
# Reinit runs reset.sh then init.sh: init's module registration is
# skip-if-exists, so any stale MCP entry (old env, outdated command) survives
# reinit unless reset drops it first. devbot-tools and qmd are re-registered
# fresh by init from their module templates — qmd's environment changed in
# audit-28 (QMD_LLAMA_GPU boolean → __GPU_ENABLED__ placeholder +
# QMD_EXPAND_CONTEXT_SIZE), so existing configs must not keep the stale entry.
# Only STALE entries are removed: dropping an entry that already matches its
# module template makes init re-append it at the end of the mcp map, reordering
# keys and breaking reinit byte-idempotency (audit-32 NOTE).
OPENCODE_CONFIG="${PROJECT_DIR}/opencode.jsonc"
if [[ -f "${OPENCODE_CONFIG}" ]]; then
  REMOVE_MCP_PY="${DEV_BOT_ROOT}/src/_shared/remove_mcp_key.py"
  IS_CURRENT_PY="${DEV_BOT_ROOT}/src/_shared/mcp_key_is_current.py"
  if [[ -f "${REMOVE_MCP_PY}" ]]; then
    # key → module template declaring it (qmd module, tools-mcp module)
    declare -A MCP_TEMPLATES=(
      [qmd]="${DEV_BOT_ROOT}/src/agentic/qmd/mcp.opencode.json"
      [devbot-tools]="${DEV_BOT_ROOT}/src/agentic/tools-mcp/mcp.opencode.json"
    )
    for mcp_key in "${!MCP_TEMPLATES[@]}"; do
      local_template="${MCP_TEMPLATES[$mcp_key]}"
      if [[ -f "${IS_CURRENT_PY}" && -f "${local_template}" ]] \
        && python3 "${IS_CURRENT_PY}" "${OPENCODE_CONFIG}" "${local_template}" "${mcp_key}" 2>/dev/null; then
        _skip "${mcp_key}: matches module template — no refresh needed"
        continue
      fi
      python3 "${REMOVE_MCP_PY}" "${OPENCODE_CONFIG}" "${mcp_key}" 2>/dev/null || true
    done
    unset MCP_TEMPLATES
  fi
fi

_ok "Opencode reset complete"
