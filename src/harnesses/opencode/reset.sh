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

# ── If opencode is disabled, nuke everything ──────────────────────────────────
_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"
if echo "${_disabled_raw}" | python3 -c "import json,sys; tools=json.loads(sys.stdin.read()); sys.exit(0 if 'opencode' in tools else 1)" 2>/dev/null; then
  _step "opencode is disabled — removing .opencode/ and opencode.jsonc..."
  rm -rf "${OPENCODE_DIR}" 2>/dev/null || true
  rm -f "${PROJECT_DIR}/opencode.jsonc" 2>/dev/null || true
  _ok "Removed opencode artifacts (disabled)"
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
      abs_target="$(readlink -f "${link}" 2>/dev/null || true)"
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

# ── Remove devbot-tools MCP from opencode.jsonc ─────────────────────────────
OPENCODE_CONFIG="${PROJECT_DIR}/opencode.jsonc"
if [[ -f "${OPENCODE_CONFIG}" ]]; then
  REMOVE_MCP_PY="${DEV_BOT_ROOT}/src/_shared/remove_mcp_key.py"
  if [[ -f "${REMOVE_MCP_PY}" ]]; then
    python3 "${REMOVE_MCP_PY}" "${OPENCODE_CONFIG}" "devbot-tools" 2>/dev/null || true
  fi
fi

_ok "Opencode reset complete"
