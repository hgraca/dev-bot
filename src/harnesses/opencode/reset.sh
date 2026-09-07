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
    # key → module template declaring it (qmd module, mdctx module, tools-mcp module)
    declare -A MCP_TEMPLATES=(
      [qmd]="${DEV_BOT_ROOT}/src/agentic/qmd/mcp.opencode.json"
      [mdctx]="${DEV_BOT_ROOT}/src/agentic/mdctx/mcp.opencode.json"
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

  # ── Prune plugin/MCP entries declared by now-DISABLED modules ─────────────
  # Registration into opencode.jsonc is append-only (_upsert_opencode_plugin,
  # merge_mcp_jsonc.py SKIP_EXISTS), so a module that became disabled — e.g.
  # codebase-index after a codebase_index_provider flip to codebase-memory —
  # keeps its plugin/MCP entries unless reset drops them. init never re-adds
  # disabled modules, so removal is unconditional (unlike the stale-only
  # enabled-module refresh above) and byte-idempotent: a second reset finds the
  # entry already gone and touches nothing.
  #
  # TRADEOFF (intentional, documented in docs/configuration.md): disabling a
  # module now UNREGISTERS its declared plugin/MCP entries at the next reinit,
  # not merely stops future registration. A user-customized entry for a module
  # dev-bot no longer manages is removed permanently — config files are
  # rewritten, not backed up. Required for the codebase_index_provider engine
  # swap: a flipped-off engine must shed its registrations.
  REMOVE_PLUGIN_PY="${DEV_BOT_ROOT}/src/_shared/remove_plugin_entry.py"
  # Parse the disabled set once (module names the registration loops skip).
  disabled_name=""
  while IFS= read -r disabled_name; do
    [[ -n "${disabled_name}" ]] || continue

    # Locate the module dir in the bases that register into opencode.jsonc
    # (tools/agentic declare mcp.opencode.json + plugin.opencode.json; harnesses
    # only mcp.opencode.json — external modules never register here).
    mod_dir=""
    base_dir=""
    for base_dir in "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/harnesses"; do
      if [[ -d "${base_dir}/${disabled_name}" ]]; then
        mod_dir="${base_dir}/${disabled_name}"
        break
      fi
    done
    [[ -n "${mod_dir}" ]] || continue

    # Plugin array entries (plugin.opencode.json = ["name", ...])
    if [[ -f "${mod_dir}/plugin.opencode.json" && -f "${REMOVE_PLUGIN_PY}" ]]; then
      while IFS= read -r plugin_name; do
        [[ -n "${plugin_name}" ]] || continue
        # Pre-check scoped to the actual plugin array (not a whole-file grep,
        # which would match the name inside comments or other sections and then
        # report a phantom removal).
        if python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${OPENCODE_CONFIG}" "plugin" 2>/dev/null \
          | grep -q "\"${plugin_name}\""; then
          python3 "${REMOVE_PLUGIN_PY}" "${OPENCODE_CONFIG}" "${plugin_name}" 2>/dev/null || true
          # Post-check: only report success when the entry is actually gone —
          # a removal that silently no-ops (e.g. the top-level plugin array was
          # absent despite the pre-check) must surface as a warning, not an _ok.
          if python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${OPENCODE_CONFIG}" "plugin" 2>/dev/null \
            | grep -q "\"${plugin_name}\""; then
            _warn "${disabled_name}: plugin '${plugin_name}' still present in plugin array — removal failed"
          else
            _ok "${disabled_name}: removed plugin '${plugin_name}' (module disabled)"
          fi
        fi
      done < <(jq -r '.[]' "${mod_dir}/plugin.opencode.json" 2>/dev/null)
    fi

    # MCP keys (mcp.opencode.json = { "key": {...} })
    if [[ -f "${mod_dir}/mcp.opencode.json" && -f "${REMOVE_MCP_PY}" ]]; then
      mcp_key_name=""
      while IFS= read -r mcp_key_name; do
        [[ -n "${mcp_key_name}" ]] || continue
        if python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${OPENCODE_CONFIG}" "mcp" 2>/dev/null \
          | grep -q "\"${mcp_key_name}\""; then
          python3 "${REMOVE_MCP_PY}" "${OPENCODE_CONFIG}" "${mcp_key_name}" 2>/dev/null || true
          _ok "${disabled_name}: removed MCP '${mcp_key_name}' (module disabled)"
        fi
      done < <(python3 -c "
import json
with open('${mod_dir}/mcp.opencode.json') as f:
    data = json.load(f)
for k in data.keys():
    print(k)
" 2>/dev/null)
    fi
  done < <(echo "${_disabled_raw}" | jq -r '.[]' 2>/dev/null || true)
  unset REMOVE_PLUGIN_PY
fi

_ok "Opencode reset complete"
