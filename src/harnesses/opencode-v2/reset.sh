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

# ── Prune RETIRED MCP keys ───────────────────────────────────────────────────
# Deliberately before the .opencode/ guard below: a project can carry a
# dev-bot-managed opencode.jsonc without the symlink farm, and a retired key
# must be shed there too. Independent of the symlink cleanup.
RETIRED_MCP_KEYS=(qmd next-devtools)
RETIRED_MCP_KEY_PREFIXES=(datasources-)

# Server keys in whichever shape the config holds them: a migrated config nests
# them under mcp.servers, one mid-upgrade still keeps them directly under mcp —
# and bin/init.sh runs this reset BEFORE init migrates it, so both occur.
# Compared as literals: a dotted `get` path would split a key containing dots.
_mcp_config_server_keys() {
  [[ -f "${CONFIG}" ]] || return 0
  local servers
  servers="$(_v2 get "${CONFIG}" mcp.servers 2>/dev/null || true)"
  if [[ -n "${servers}" ]]; then
    jq -r 'keys[]' <<<"${servers}" 2>/dev/null || true
    return 0
  fi
  servers="$(_v2 get "${CONFIG}" mcp 2>/dev/null || true)"
  [[ -n "${servers}" ]] || return 0
  jq -r 'keys[] | select(. != "servers")' <<<"${servers}" 2>/dev/null || true
}

_prune_retired_mcp_key() {
  local mcp_key="$1" reason="$2" keys
  [[ -f "${CONFIG}" ]] || return 0
  # grep reads a here-string, never a live pipe: `grep -q` exits on the first
  # match, and a producer still writing would take SIGPIPE — which pipefail
  # reports as failure, silently skipping the removal.
  keys="$(_mcp_config_server_keys)"
  grep -Fxq -- "${mcp_key}" <<<"${keys}" || return 0
  if _v2 get "${CONFIG}" mcp.servers >/dev/null 2>&1; then
    _v2 remove-mcp "${CONFIG}" "${mcp_key}" >/dev/null 2>&1 || true
  else
    python3 "${DEV_BOT_ROOT}/src/_shared/remove_mcp_key.py" "${CONFIG}" "${mcp_key}" >/dev/null 2>&1 || true
  fi
  _ok "${mcp_key}: removed retired MCP key (${reason})"
}

_main_retired_mcp_sweep() {
  local retired_key retired_prefix candidate
  for retired_key in "${RETIRED_MCP_KEYS[@]}"; do
    _prune_retired_mcp_key "${retired_key}" "retired"
  done
  for retired_prefix in "${RETIRED_MCP_KEY_PREFIXES[@]}"; do
    while IFS= read -r candidate; do
      [[ -n "${candidate}" ]] || continue
      _prune_retired_mcp_key "${candidate}" "prefix ${retired_prefix}"
    done < <(
      while IFS= read -r retired_key; do
        [[ "${retired_key}" == "${retired_prefix}"* ]] && printf '%s\n' "${retired_key}"
      done < <(_mcp_config_server_keys)
    )
  done
}

_main_retired_mcp_sweep

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
# A module that ships mcp.dynamic.json is a producer too, whatever its name:
# its servers' keys need not be named after it (k8s writes kctl-<cluster>).
_is_dynamic_manifest_producer() {
  case "$1" in
    aws|datasources|jetbrains|netsuite) return 0 ;;
  esac
  [[ -f "$2/mcp.dynamic.json" ]]
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
    if [[ ! -f "${mod_dir}/mcp.json" ]] && _is_dynamic_manifest_producer "${disabled_name}" "${mod_dir}"; then
      while IFS= read -r orphan_key; do
        [[ -n "${orphan_key}" ]] || continue
        _prune_mcp_key "${orphan_key}" "${disabled_name}"
      done < <(
        # Keys this module owns: its own name, plus any server-key prefix it
        # declares in mcp.dynamic.json (datasources wires `ds-<source>`).
        owned_names="${disabled_name}"
        if [[ -f "${mod_dir}/mcp.dynamic.json" ]]; then
          while IFS= read -r declared_prefix; do
            [[ -n "${declared_prefix}" ]] && owned_names+=$'\n'"${declared_prefix}"
          done < <(jq -r '.prefixes[]?' "${mod_dir}/mcp.dynamic.json" 2>/dev/null || true)
        fi
        _v2 get "${CONFIG}" mcp.servers 2>/dev/null \
          | jq -r --arg names "${owned_names}" '
              ($names | split("\n") | map(select(. != ""))) as $ns
              | keys[] as $k
              | select(any($ns[]; . as $p | $k == $p or ($k | startswith($p + "-"))))
              | $k
            ' 2>/dev/null || true
      )
    fi
  done < <(echo "${_disabled_raw}" | jq -r '.[]' 2>/dev/null || true)
fi

_ok "Opencode v2 reset complete"
