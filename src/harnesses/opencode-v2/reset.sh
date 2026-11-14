#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode-v2/reset.sh
# Removes dev-bot-managed symlinks from .opencode/ and prunes plugin/MCP entries
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
# have exported an incorrect value when the script runs standalone.
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
OPENCODE_DIR="${PROJECT_DIR}/.opencode"
CONFIG="${PROJECT_DIR}/opencode.jsonc"
V2HELPER="${MODULE_DIR}/lib/v2config.py"

_v2() {
  V2_SHARED_DIR="${DEV_BOT_ROOT}/src/_shared" python3 "${V2HELPER}" "$@"
}

_header_3 "Opencode v2 Reset"

# ── If opencode-v2 is not the selected harness, leave it alone ───────────────
# .opencode/ and opencode.jsonc may be entirely the user's, and dev-bot never
# removes artifacts of a harness it is not managing. Symlinks left while this
# harness WAS selected are cleaned by the next init from the harness now
# selected, which sweeps dev-bot-owned links before it links its own.
_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"
if echo "${_disabled_raw}" | jq -e 'index("opencode-v2") != null' >/dev/null 2>&1; then
  _skip "opencode-v2 is not the selected harness — leaving .opencode/ and opencode.jsonc untouched"
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
    [[ -z "${target}" ]] && continue

    local link_dir abs_target
    link_dir="$(dirname "${link}")"
    abs_target="$(cd "${link_dir}" 2>/dev/null && cd "${target}" 2>/dev/null && pwd 2>/dev/null || true)"
    if [[ -z "${abs_target}" ]]; then
      local rel_target="${target}"
      [[ "${rel_target}" != /* ]] && rel_target="${link_dir}/${rel_target}"
      abs_target="$(cd -P "$(dirname "${rel_target}")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename "${rel_target}")" || true)"
    fi

    if [[ "${abs_target}" == "${DEV_BOT_ROOT}"/* ]]; then
      rm -f "${link}"
      removed=$((removed + 1))
    fi
  done < <(find "${dir}" -type l -print0 2>/dev/null)

  if [[ ${removed} -gt 0 ]]; then
    _ok "Removed ${removed} dev-bot symlink(s) from ${dir#"${PROJECT_DIR}/"}"
  fi

  local broken=0 broken_target
  while IFS= read -r -d '' link; do
    [[ -e "${link}" ]] && continue
    # A broken link is ours only when its target is inside dev-bot: a user's
    # intentionally broken link must survive a reset.
    broken_target="$(readlink "${link}" 2>/dev/null || true)"
    [[ "${broken_target}" == "${DEV_BOT_ROOT}"/* ]] || continue
    rm -f "${link}"
    broken=$((broken + 1))
  done < <(find "${dir}" -type l -print0 2>/dev/null)

  if [[ ${broken} -gt 0 ]]; then
    _ok "Removed ${broken} broken symlink(s) from ${dir#"${PROJECT_DIR}/"}"
  fi

  find "${dir}" -type d -empty -delete 2>/dev/null || true
}

for subdir in agents commands skills plugins tui-plugins tools; do
  _reset_symlinks_in_dir "${OPENCODE_DIR}/${subdir}"
done
_reset_symlinks_in_dir "${OPENCODE_DIR}"

# ── Prune plugin/MCP entries declared by now-DISABLED modules ────────────────
# Registration into opencode.jsonc is append-only, so a module that became
# disabled keeps its entries unless reset drops them. init never re-adds disabled
# modules, so removal is unconditional and byte-idempotent.
_prune_plugin_entry() {
  local plugin_name="$1" module_name="$2"
  [[ -f "${CONFIG}" ]] || return 0
  if ! _v2 get "${CONFIG}" plugins 2>/dev/null | grep -qF "\"${plugin_name}\""; then
    return 0
  fi
  if _v2 remove-plugin "${CONFIG}" "${plugin_name}" >/dev/null 2>&1; then
    _ok "${module_name}: removed plugin '${plugin_name}' (module disabled)"
  else
    _warn "${module_name}: plugin '${plugin_name}' still present — removal failed"
  fi
}

_prune_mcp_key() {
  local mcp_key="$1" module_name="$2"
  [[ -f "${CONFIG}" ]] || return 0
  if _v2 get "${CONFIG}" "mcp.servers.${mcp_key}" >/dev/null 2>&1; then
    _v2 remove-mcp "${CONFIG}" "${mcp_key}" >/dev/null 2>&1 || true
    _ok "${module_name}: removed MCP '${mcp_key}' (module disabled)"
  fi
}

# Only modules that WRITE <name>.mcp.json under .opencode/ own these keys.
_is_dynamic_manifest_producer() {
  case "$1" in
    aws|datasources|jetbrains|netsuite) return 0 ;;
  esac
  return 1
}

if [[ -f "${CONFIG}" ]]; then
  disabled_name=""
  while IFS= read -r disabled_name; do
    [[ -n "${disabled_name}" ]] || continue

    mod_dir=""
    for base_dir in "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/harnesses"; do
      if [[ -d "${base_dir}/${disabled_name}" ]]; then
        mod_dir="${base_dir}/${disabled_name}"
        break
      fi
    done
    [[ -n "${mod_dir}" ]] || continue

    # V2 plugin declarations only — a V1 plugin was never registered on this
    # harness, so there is nothing of its to prune.
    if [[ -f "${mod_dir}/plugin.opencode-v2.json" ]]; then
      while IFS= read -r plugin_name; do
        [[ -n "${plugin_name}" ]] || continue
        _prune_plugin_entry "${plugin_name}" "${disabled_name}"
      done < <(jq -r '.[]' "${mod_dir}/plugin.opencode-v2.json" 2>/dev/null)
    fi

    if [[ -f "${mod_dir}/mcp.json" ]]; then
      mcp_key_name=""
      while IFS= read -r mcp_key_name; do
        [[ -n "${mcp_key_name}" ]] || continue
        _prune_mcp_key "${mcp_key_name}" "${disabled_name}"
      done < <(python3 -c "
import json
with open('${mod_dir}/mcp.json') as f:
    data = json.load(f)
for k in data.get('mcp', {}):
    if not k.startswith('_'):
        print(k)
" 2>/dev/null)
    fi

    for dyn_manifest in "${OPENCODE_DIR}/${disabled_name}.mcp.json" "${OPENCODE_DIR}/${disabled_name}-"*.mcp.json; do
      [[ -f "${dyn_manifest}" ]] || continue
      while IFS= read -r dyn_key; do
        [[ -n "${dyn_key}" ]] || continue
        _prune_mcp_key "${dyn_key}" "${disabled_name}"
      done < <(jq -r 'keys[]' "${dyn_manifest}" 2>/dev/null)
      rm -f "${dyn_manifest}"
      _ok "${disabled_name}: removed $(basename "${dyn_manifest}") (module disabled)"
    done

    # A dynamic module's server stays registered after its manifest is gone, so
    # prune the keys it owns by name (<name>, <name>-<detail>).
    if [[ ! -f "${mod_dir}/mcp.json" ]] && _is_dynamic_manifest_producer "${disabled_name}"; then
      while IFS= read -r orphan_key; do
        [[ -n "${orphan_key}" ]] || continue
        _prune_mcp_key "${orphan_key}" "${disabled_name}"
      done < <(
        _v2 get "${CONFIG}" mcp.servers 2>/dev/null \
          | jq -r --arg name "${disabled_name}" \
            'keys[] | select(. == $name or startswith($name + "-"))' 2>/dev/null || true
      )
    fi
  done < <(echo "${_disabled_raw}" | jq -r '.[]' 2>/dev/null || true)
fi

_ok "Opencode v2 reset complete"
