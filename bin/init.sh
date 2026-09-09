#!/usr/bin/env bash
# =============================================================================
# bin/init.sh
# Initialises dev-bot in a project directory. Sets up the agent vault
# and runs all init.sh scripts discovered under src/.
#
# Usage:
#   bin/init.sh                    # init in current directory
#   bin/init.sh /path/to/project   # init in specified project
#
# Adding a new init step:
#   Create src/tools/<module>/init.sh or src/agentic/<module>/init.sh — it will be auto-discovered and run.
# =============================================================================

set -euo pipefail

# ── Resolve paths ──────────────────────────────────────────────────────────────
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "Directory '${1:-.}' does not exist or cannot be resolved."
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_DIR}")"

_register_module_mcp() {
  local mod_dir="$1"
  local config_file="$2"
  local config_name="$3"

  local mcp_file="${mod_dir}mcp.json"
  if [[ ! -f "${mcp_file}" || -z "${config_file}" ]]; then
    echo 0
    return
  fi

  local mod_name
  mod_name="$(basename "${mod_dir}")"
  local merge_mcp_script="${DEV_BOT_ROOT}/src/_shared/merge_mcp_jsonc.py"
  local translate_script="${DEV_BOT_ROOT}/src/_shared/mcp_translate.py"

  # Plugin-provided servers are NOT also registered as MCPs: opencode loads
  # them from the module's plugin.opencode.json (codebase-index), and
  # registering the server as an MCP too would double-load it.
  if [[ -f "${mod_dir}plugin.opencode.json" ]]; then
    _skip "${mod_name}: MCP provided via opencode plugin — skipping MCP registration" >&2
    echo 0
    return
  fi

  # Translate the canonical manifest (src/agentic/<module>/mcp.json) into the
  # opencode mcp shape. The translator resolves {harness-dir} → .opencode and
  # the __GPU_ENABLED__ / __DEV_BOT_ROOT__ placeholders (qmd GPU value /
  # dev-bot install root) at registration time.
  local translated
  translated="$(python3 "${translate_script}" "${mcp_file}" opencode \
    --gpu "$(_qmd_gpu_value)" --root "${DEV_BOT_ROOT}" 2>/dev/null || true)"

  if ! python3 -c "import json, sys; json.loads(sys.stdin.read())" <<<"${translated}" 2>/dev/null; then
    _warn "${mod_name}: could not translate ${mcp_file} — skipping MCP registration" >&2
    echo 0
    return
  fi

  local inserted=0
  local mcp_key
  while IFS= read -r mcp_key; do
    [[ -n "${mcp_key}" ]] || continue

    # Check if already registered in config — scoped to the mcp section. A
    # whole-file grep matched the key ANYWHERE (e.g. the permission block's
    # `"websearch": "allow"`), so an unregistered MCP was silently skipped on
    # every reinit. read_jsonc gives the mcp map; the merge script's own
    # SKIP_EXISTS remains the authoritative idempotency check.
    if python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${config_file}" "mcp" 2>/dev/null \
      | grep -q "\"${mcp_key}\""; then
      _skip "${mod_name}: MCP '${mcp_key}' already registered in ${config_name}" >&2
      continue
    fi

    # Extract this server's translated definition.
    local mcp_def
    mcp_def="$(python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print(json.dumps(d['${mcp_key}']))
" <<<"${translated}" 2>/dev/null || true)"

    if [[ -z "${mcp_def}" ]]; then
      _warn "${mod_name}: could not read MCP definition for '${mcp_key}' — skipping" >&2
      continue
    fi

    # Docker-only MCPs can't run without a docker daemon (e.g. inside a
    # container) — skip registering them so the client never starts them and
    # never logs connection errors. Hybrid defs (docker with an npx fallback,
    # like playwright) are still registered; their wrapper picks the path.
    if echo "${mcp_def}" | grep -q 'docker run' \
      && ! echo "${mcp_def}" | grep -q 'npx -y @playwright/mcp' \
      && ! docker info >/dev/null 2>&1; then
      _skip "${mod_name}: MCP '${mcp_key}' needs a docker daemon — skipping registration" >&2
      continue
    fi

    # Merge into opencode config (comment-preserving approach)
    _info "Registering ${mod_name} MCP '${mcp_key}' in ${config_name}..." >&2
    local merge_result
    merge_result=$(python3 "${merge_mcp_script}" "${config_file}" "${mcp_key}" "${mcp_def}" 2>/dev/null || true)
    case "${merge_result}" in
      INSERTED)
        _ok "${mod_name}: MCP '${mcp_key}' registered in ${config_name}" >&2
        inserted=$((inserted + 1))
        ;;
      SKIP_EXISTS)
        _skip "${mod_name}: MCP '${mcp_key}' already registered in ${config_name}" >&2
        ;;
      *)
        _error "${mod_name}: merge_mcp_jsonc returned unexpected result '${merge_result}' — skipping" >&2
        ;;
    esac
  done < <(python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print('\n'.join(d.keys()))
" <<<"${translated}" 2>/dev/null)

  echo "${inserted}"
}

_link_module_memory() {
  local mod_dir="$1"
  local memory_dir="$2"
  local mod_name
  mod_name="$(basename "${mod_dir}")"

  local mem_dir="${mod_dir}memory"
  [[ -d "${mem_dir}" ]] || return 0

  local link_path="${memory_dir}/${mod_name}"
  mkdir -p "${memory_dir}"

  if [[ -L "${link_path}" ]]; then
    local current
    current="$(readlink "${link_path}")"
    if [[ "${current}" == "${mem_dir}" ]]; then
      _skip "${mod_name} memory → ${mem_dir} (already linked)"
    else
      rm "${link_path}"
      ln -s "${mem_dir}" "${link_path}"
      _log "${mod_name} memory → ${mem_dir} (repaired)"
    fi
  elif [[ -e "${link_path}" ]]; then
    _warn "${link_path} exists but is not a symlink — skipping"
  else
    ln -s "${mem_dir}" "${link_path}"
    _log "${mod_name} memory → ${mem_dir}"
  fi
}

_run_external_module_init() {
  local ext_mod_dir="$1"
  local project_dir="$2"
  local ext_init="${ext_mod_dir}init.sh"
  [[ -f "${ext_init}" ]] || return 1

  local ext_mod_name
  ext_mod_name="$(basename "${ext_mod_dir}")"
  _header_3 "Running ${ext_mod_name} init..."
  local start=${SECONDS}
  if bash "${ext_init}" "${project_dir}"; then
    _ok "${ext_mod_name} init done ($(_fmt_duration $(( SECONDS - start ))))"
  else
    _warn "${ext_mod_name} init had issues"
  fi
}

_link_external_module_memory() {
  local ext_mod_dir="$1"
  local memory_dir="$2"
  local ext_mem_dir="${ext_mod_dir}memory"
  [[ -d "${ext_mem_dir}" ]] || return 0

  local ext_mod_name
  ext_mod_name="$(basename "${ext_mod_dir}")"

  _step "${ext_mod_name}: linking memory files..."

  while IFS= read -r -d '' file; do
    local rel_path="${file#"${ext_mem_dir}"/}"
    local target_link="${memory_dir}/${rel_path}"
    local target_dir
    target_dir="$(dirname "${target_link}")"

    mkdir -p "${target_dir}"

    if [[ -L "${target_link}" ]]; then
      local current_target
      current_target="$(readlink "${target_link}")"
      if [[ -L "${file}" ]]; then
        local desired_target
        desired_target="$(readlink "${file}")"
        if [[ "${current_target}" == "${desired_target}" ]]; then
          _skip "${ext_mod_name} memory → ${rel_path} (already correct)"
          continue
        fi
      fi
      rm "${target_link}"
      # fall through to recreate
    elif [[ -e "${target_link}" ]]; then
      _warn "${target_link} exists but is not a symlink — skipping"
      continue
    fi

    # Create symlink pointing to the same vendor file
    if [[ -L "${file}" ]]; then
      local vendor_target
      vendor_target="$(readlink "${file}")"
      ln -s "${vendor_target}" "${target_link}"
    else
      ln -s "${file}" "${target_link}"
    fi
    _log "${ext_mod_name} memory → ${rel_path}"
  done < <(find "${ext_mem_dir}" \( -type f -o -type l \) -print0)
}

# ── Test-compatible entry points ───────────────────────────────────────────────
#
# _run_inits — runs init.sh for each external agentic module.
# Called by tests and by main().

_run_inits() {
  local external_base="${DEV_BOT_ROOT}/storage/external-agentic-modules"

  local disabled_list
  disabled_list=$(echo "$(_devbot_get_disabled_modules "${PROJECT_DIR}")" | python3 -c "
import json, sys
for m in json.loads(sys.stdin.read()):
    print(m)
" 2>/dev/null || true)

  # audit-33 NOTE: an empty "External Agentic Modules" section (header with no
  # content) printed when no registered module shipped an init.sh. Track what
  # actually ran and emit a status line so reinit output never implies a step
  # ran with nothing to report.
  local ext_mod_name
  local checked=0
  local ran=0
  while IFS= read -r ext_mod_name; do
    [[ -z "${ext_mod_name}" ]] && continue
    checked=$((checked + 1))

    if echo "${disabled_list}" | grep -Fxq "${ext_mod_name}" 2>/dev/null; then
      _skip "${ext_mod_name}: disabled per config — skipping"
      continue
    fi

    if _run_external_module_init "${external_base}/${ext_mod_name}/" "${PROJECT_DIR}"; then
      ran=$((ran + 1))
    fi
  done < <(_devbot_get_external_modules)

  if [[ ${checked} -eq 0 ]]; then
    _skip "no external modules configured"
  elif [[ ${ran} -eq 0 ]]; then
    _skip "${checked} external module(s) checked — none ship init.sh (wiring handled by harness init)"
  fi
}

# _prune_orphaned_external_modules — removes external-module storage dirs that
# are no longer present in the `modules` config. The config is the source of
# truth; orphaned storage is removed regardless of what still exists on disk.

_prune_orphaned_external_modules() {
  local external_base="${DEV_BOT_ROOT}/storage/external-agentic-modules"
  [[ -d "${external_base}" ]] || return 0

  local configured
  configured="$(_devbot_get_external_modules)"

  local orphan_dir
  for orphan_dir in "${external_base}/"*/; do
    local dir_name
    dir_name="$(basename "${orphan_dir}")"
    if echo "${configured}" | grep -Fxq "${dir_name}" 2>/dev/null; then
      continue
    fi
    _warn "Removing orphaned external module storage: ${dir_name} (not in modules config)"
    rm -rf "${orphan_dir}"
  done
}

# _link_memory_folders — links memory for built-in + external modules.
# Idempotent. Called by tests and by main().
# Gitignore is handled by the memory module (src/agentic/memory/init.sh).

_link_memory_folders() {
  local memory_dir="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")/memory"

  local disabled_list
  disabled_list=$(echo "$(_devbot_get_disabled_modules "${PROJECT_DIR}")" | python3 -c "
import json, sys
for m in json.loads(sys.stdin.read()):
    print(m)
" 2>/dev/null || true)

  # Built-in modules (tools + agentic + harnesses)
  for base_dir in "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses"; do
    for mod_dir in "${base_dir}/"*/; do
      local mod_name
      mod_name="$(basename "${mod_dir}")"
      if echo "${disabled_list}" | grep -Fxq "${mod_name}" 2>/dev/null; then
        continue
      fi
      _link_module_memory "${mod_dir}" "${memory_dir}"
    done
  done

  # External modules (config-driven)
  local external_base="${DEV_BOT_ROOT}/storage/external-agentic-modules"
  local ext_mod_name
  while IFS= read -r ext_mod_name; do
    [[ -z "${ext_mod_name}" ]] && continue
    if echo "${disabled_list}" | grep -Fxq "${ext_mod_name}" 2>/dev/null; then
      continue
    fi
    _link_external_module_memory "${external_base}/${ext_mod_name}/" "${memory_dir}"
  done < <(_devbot_get_external_modules)
}

# ── main ───────────────────────────────────────────────────────────────────────
_format_opencode_config() {
  local config="${PROJECT_DIR}/opencode.jsonc"
  [[ -f "${config}" ]] || return 0

  local fmt_tool="${DEV_BOT_ROOT}/src/agentic/format-json/tools/format-json.mcp.sh"
  if [[ -x "${fmt_tool}" ]]; then
    bash "${fmt_tool}" "${config}" 2>/dev/null && _ok "opencode.jsonc formatted" || true
  fi
}

# ── Remove broken symlinks from the devbot dir ────────────────────────────────
# Run LAST (after every module/harness init) so it catches dangling symlinks left
# by module renames/removals anywhere in the devbot dir.
_remove_broken_symlinks() {
  local target="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")"
  [[ -d "${target}" ]] || return 0

  local removed=0
  local link
  while IFS= read -r -d '' link; do
    rm -f "${link}"
    removed=$((removed + 1))
  done < <(find "${target}" -type l ! -exec test -e {} \; -print0 2>/dev/null)

  if [[ ${removed} -gt 0 ]]; then
    _ok "Removed ${removed} broken symlink(s) from ${target}"
  else
    _ok "No broken symlinks found in ${target}"
  fi
}

main() {
  local total_start=${SECONDS}

  _header_1 "DevBot Init"

  # ── Parse disabled modules ONCE ────────────────────────────────────────────
  local disabled_modules_raw
  disabled_modules_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_modules_raw}" | python3 -c "
import json, sys
modules = json.loads(sys.stdin.read())
for m in modules:
    print(m)
" 2>/dev/null || true)

  # ── Shared paths ──────────────────────────────────────────────────────────
  local devbot_dir
  devbot_dir="$(_devbot_get_project_dir "${PROJECT_DIR}")"
  local memory_dir="${PROJECT_DIR}/${devbot_dir}/memory"

  # ── Migration: move old .ai/devbot to .agents ────────────────────────────
  _migrate_legacy_state() {
    local old_devbot="${PROJECT_DIR}/.ai/devbot"
    local new_devbot="${PROJECT_DIR}/${devbot_dir}"

    if [[ ! -d "${old_devbot}" ]]; then
      return 0
    fi

    # Migrate memory
    local old_memory="${old_devbot}/memory"
    local new_memory="${new_devbot}/memory"
    if [[ -d "${old_memory}" && ! -d "${new_memory}" ]]; then
      _step "Migrating memory from .ai/devbot/memory to ${devbot_dir}/memory..."
      mkdir -p "$(dirname "${new_memory}")"
      mv "${old_memory}" "${new_memory}" 2>/dev/null || {
        _warn "Could not move memory — copying instead"
        cp -r "${old_memory}" "${new_memory}" 2>/dev/null || true
      }
      _ok "Memory migrated to ${devbot_dir}/memory"
    fi

    # Migrate logs
    local old_logs="${old_devbot}/logs"
    local new_logs="${new_devbot}/logs"
    if [[ -d "${old_logs}" && ! -d "${new_logs}" ]]; then
      _step "Migrating logs from .ai/devbot/logs to ${devbot_dir}/logs..."
      mkdir -p "$(dirname "${new_logs}")"
      mv "${old_logs}" "${new_logs}" 2>/dev/null || {
        _warn "Could not move logs — copying instead"
        cp -r "${old_logs}" "${new_logs}" 2>/dev/null || true
      }
      _ok "Logs migrated to ${devbot_dir}/logs"
    fi

    # Remove old devbot dir if empty
    rmdir "${old_devbot}" 2>/dev/null || true
  }
  _migrate_legacy_state

  # ── Migration: rename bootstrap/ → active/ ──────────────────────────────
  if [[ -d "${memory_dir}/bootstrap" && ! -d "${memory_dir}/active" ]]; then
    _step "Renaming memory/bootstrap to memory/active..."
    mv "${memory_dir}/bootstrap" "${memory_dir}/active"
    _ok "Renamed to memory/active"
  fi

  # Detect opencode config (prefer jsonc, fall back to json)
  local config_file=""
  local config_name=""
  if [[ -f "${PROJECT_DIR}/opencode.jsonc" ]]; then
    config_file="${PROJECT_DIR}/opencode.jsonc"
    config_name="opencode.jsonc"
  elif [[ -f "${PROJECT_DIR}/opencode.json" ]]; then
    config_file="${PROJECT_DIR}/opencode.json"
    config_name="opencode.json"
  fi

  # ── 2. Init scripts (tools → agentic → harnesses) ────────────────────────
  # Modules are harness-agnostic: they only emit declarations (plugin.opencode.json,
  # runtime .mcp.json manifests, their own config files) and never touch
  # opencode.jsonc. The harnesses run last and apply those declarations.
  _header_2 "Init Scripts"

  _init_modules "${DEV_BOT_ROOT}/src/tools" "${PROJECT_DIR}"

  # Re-parse disabled_modules — tool init may have created/modified project config
  disabled_modules_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  disabled_modules=$(echo "${disabled_modules_raw}" | python3 -c "
import json, sys
modules = json.loads(sys.stdin.read())
for m in modules:
    print(m)
" 2>/dev/null || true)

  # Re-detect config_file — tool-init may have created opencode.jsonc
  if [[ -z "${config_file}" && -f "${PROJECT_DIR}/opencode.jsonc" ]]; then
    config_file="${PROJECT_DIR}/opencode.jsonc"
    config_name="opencode.jsonc"
  fi

  _header_2 "Agentic Modules"
  _init_modules "${DEV_BOT_ROOT}/src/agentic" "${PROJECT_DIR}"

  _header_2 "Harnesses"
  _init_modules "${DEV_BOT_ROOT}/src/harnesses" "${PROJECT_DIR}"

  # Re-detect config_file — harness init creates opencode.jsonc on first run
  if [[ -z "${config_file}" && -f "${PROJECT_DIR}/opencode.jsonc" ]]; then
    config_file="${PROJECT_DIR}/opencode.jsonc"
    config_name="opencode.jsonc"
  fi

  # ── 3. MCP registration (unified — tools + agentic + harnesses) ────────
  local mcp_count=0

  for base_dir in "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses"; do
    for mod_dir in "${base_dir}/"*/; do
      local mod_name
      mod_name="$(basename "${mod_dir}")"

      if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
        continue
      fi

      mcp_count=$((mcp_count + $(_register_module_mcp "${mod_dir}" "${config_file}" "${config_name}")))
    done
  done

  # ── 3.5 Env-var presence check ─────────────────────────────────────────
  # Configs registered above may reference {env:VAR} tokens that must exist
  # in the env of whatever launches the harness. If any are missing, tell
  # the user and wait for an acknowledgement before continuing. Under
  # `devbot reinit --all` the DEV_BOT_DEFER_ENV_DIALOG marker collapses this
  # to a compact per-project notice; the end-of-run dialog shows the union.
  _devbot_check_mcp_env_vars "${PROJECT_DIR}" ack

  # ── 4. Memory links + external module init ──────────────────────────────
  _prune_orphaned_external_modules
  _link_memory_folders

  # ── 4b. Regenerate the MCP server guide from the live configs ───────────
  # active/mcp.md is generated (not static) so the documented server list can
  # never drift from what is actually registered (audit-20: the fixture missed
  # devbot-tools + jetbrains). Runs after the harnesses wrote .mcp.json and
  # after MCP registration wrote opencode.jsonc's mcp block, above.
  local mcp_guide="${DEV_BOT_ROOT}/src/agentic/memory/tools/generate-mcp-guide.sh"
  if [[ -x "${mcp_guide}" ]]; then
    _header_2 "MCP Guide"
    if bash "${mcp_guide}" "${PROJECT_DIR}"; then
      _ok "active/mcp.md regenerated from live MCP configs"
    else
      _warn "generate-mcp-guide failed — keeping existing active/mcp.md"
    fi
  fi

  _header_2 "External Agentic Modules"
  _run_inits

  # ── 6. MCP summary ──────────────────────────────────────────────────────
  if [[ ${mcp_count} -gt 0 ]]; then
    _info "${mcp_count} MCP server(s) registered — restart opencode for changes to take effect"
    _format_opencode_config
  fi

  # ── 7. Register project in global config ────────────────────────────────
  local add_project_py="${DEV_BOT_ROOT}/src/_shared/add_project.py"
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  if [[ -f "${add_project_py}" && -f "${global_config}" ]]; then
    python3 "${add_project_py}" "${global_config}" "${PROJECT_DIR}" 2>/dev/null || true
  fi

  # ── 8. Remove broken symlinks (after every init has run) ────────────────
  _header_2 "Broken Symlink Cleanup"
  _remove_broken_symlinks

  # ── 9. Final header ─────────────────────────────────────────────────────
  _header_2 "✔  DevBot init complete, you still should run the '/create-codebase-report' command on the first time you start the agent"

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
