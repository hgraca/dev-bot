#!/usr/bin/env bash
# =============================================================================
# src/tools/claudecode/reset.sh
# Removes dev-bot-managed symlinks from .claude/, clears dev-bot hook entries
# from .claude/settings.local.json, and removes the generated .mcp.json.
# Leaves user-created files and non-devbot symlinks intact.
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
CLAUDE_DIR="${PROJECT_DIR}/.claude"

_header_3 "Claude Code Reset"

# ── If claudecode is disabled, leave the harness alone ────────────────────────
# The user may use Claude Code independently of dev-bot: .claude/, CLAUDE.md
# and .mcp.json may be entirely theirs. dev-bot never removes artifacts of a
# harness it is not managing — reinit must not destroy a user's setup.
# NOTE: this also means dev-bot symlinks left by a previous (enabled) init are
# kept when the module is disabled; there is no cleanup path for them while
# disabled. Re-enable the module and reset to clean them.
_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"
if echo "${_disabled_raw}" | jq -e 'index("claudecode") != null' >/dev/null 2>&1; then
  _skip "claudecode is disabled — leaving .claude/, .mcp.json and CLAUDE.md untouched"
  exit 0
fi

if [[ ! -d "${CLAUDE_DIR}" ]]; then
  _skip "No .claude/ directory — nothing to reset"
  exit 0
fi

# ── Clear dev-bot hooks from .claude/settings.local.json ────────────────────
# Runs BEFORE the symlink removal below (audit-31 §2): .claude/plugins/*.py are
# symlinks into DEV_BOT_ROOT that the subsequent loop deletes. If the hook
# entries were cleared after the symlinks, a concurrent PreToolUse in the gap
# would hit a registered hook whose script no longer exists — Claude Code
# treats that hook execution error as "no decision" → default-allow, silently
# disabling the guard. Clearing hooks first means no registered hook ever
# references a script that is about to be deleted.
_clear_settings_hooks() {
  local config="${CLAUDE_DIR}/settings.local.json"
  [[ -f "${config}" ]] || return 0

  python3 -c "
import json
try:
    with open('${config}') as f:
        data = json.load(f)
    if 'hooks' in data:
        del data['hooks']
        with open('${config}', 'w') as f:
            json.dump(data, f, indent=2)
            f.write('\n')
        print('[OK] Cleared hooks from .claude/settings.local.json')
    else:
        print('[SKIP] No hooks in .claude/settings.local.json')
except Exception as e:
    print(f'[WARN] Could not process settings.local.json: {e}')
    exit(1)
" 2>/dev/null || true
}

_clear_settings_hooks

# ── Remove dev-bot symlinks from .claude/ subdirs ────────────────────────────
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
  _reset_symlinks_in_dir "${CLAUDE_DIR}/${subdir}"
done

# ── Also clean root-level symlinks in .claude/ ──────────────────────────────
# Some modules (tools-mcp) create MCP wrapper symlinks at the root
_reset_symlinks_in_dir "${CLAUDE_DIR}"

# ── Remove .mcp.json (fully regenerated by devbot init) ────────────────────
MCP_CONFIG="${PROJECT_DIR}/.mcp.json"
if [[ -f "${MCP_CONFIG}" ]]; then
  # Use remove_mcp_key.py to surgically remove dev-bot MCP servers
  # Scan agentic modules for known MCP keys
  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    MCP_FILE="${mod_dir}/mcp.claudecode.json"
    if [[ -f "${MCP_FILE}" ]]; then
      # Extract MCP server keys from this module
      python3 -c "
import json
with open('${MCP_FILE}') as f:
    data = json.load(f)
for name in data.get('mcpServers', {}):
    print(name)
" 2>/dev/null | while IFS= read -r mcp_key; do
        if [[ -n "${mcp_key}" ]]; then
          REMOVE_MCP_PY="${DEV_BOT_ROOT}/src/_shared/remove_mcp_key.py"
          if [[ -f "${REMOVE_MCP_PY}" ]]; then
            python3 "${REMOVE_MCP_PY}" "${MCP_CONFIG}" "${mcp_key}" 2>/dev/null || true
          fi
        fi
      done
    fi
  done
fi

_ok "Claude Code reset complete"
