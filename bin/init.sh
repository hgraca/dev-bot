#!/usr/bin/env bash
# =============================================================================
# bin/init.sh
# Initialises dev-bot in a project directory. A project that already carries a
# `.devbot.project.jsonc` is reset first (module reset.sh scripts, module
# memory, pre-modules memory files) and then wired; anything else is wired
# directly. Re-running it is idempotent.
#
# Usage:
#   bin/init.sh                        # init/reinit the current directory
#   bin/init.sh /path/to/project       # init/reinit the given project
#   bin/init.sh --all|-a               # every project in the global config
#   bin/init.sh --full|-f              # full reset: drop QMD/index data too
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
    # never logs connection errors. A hybrid def (docker with a non-docker
    # fallback its own launcher picks at runtime, like playwright) is still
    # registered; its canonical manifest declares that with `"_hybrid": true`,
    # read by _mcp_declares_hybrid. Never key this on the fallback's command
    # text: e7e7cd40 replaced playwright's fallback and the old literal grep
    # left it misclassified as docker-only.
    if echo "${mcp_def}" | grep -q 'docker run' \
      && ! _mcp_declares_hybrid "${mcp_file}" "${mcp_key}" \
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

  # External names whose every declaring umbrella is disabled for this project:
  # the global config/mirror keeps them, but per-project wiring must skip them.
  local disabled_external_list
  disabled_external_list="$(_devbot_disabled_external_names "${PROJECT_DIR}")"

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

    if echo "${disabled_external_list}" | grep -Fxq "${ext_mod_name}" 2>/dev/null; then
      _skip "${ext_mod_name}: declared by a disabled module — skipping"
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

# _all_declared_external_names — prints every external-module name declared by
# any internal module's external-modules.json (src/agentic/* and src/tools/*),
# regardless of whether that module is enabled. Enablement is per-project while
# the declaration store and the storage mirrors are global, so a name declared
# by a disabled module is still a live declaration.

_all_declared_external_names() {
  python3 -c "
import glob, json
for f in glob.glob('${DEV_BOT_ROOT}/src/agentic/*/external-modules.json') + glob.glob('${DEV_BOT_ROOT}/src/tools/*/external-modules.json'):
    try:
        for name in json.load(open(f)):
            print(name)
    except Exception:
        continue
" 2>/dev/null || true
}

# _prune_orphaned_external_modules — removes an external-module storage mirror
# ONLY when nothing declares it: not any internal module's external-modules.json
# (enabled or disabled) and not the `external_modules` config. A declared name is
# always kept — the mirrors live under the global dev-bot root and another
# project may need the one this project has disabled.

_prune_orphaned_external_modules() {
  local external_base="${DEV_BOT_ROOT}/storage/external-agentic-modules"
  [[ -d "${external_base}" ]] || return 0

  local declared configured
  declared="$(_all_declared_external_names)"
  configured="$(_devbot_get_external_modules)"

  local orphan_dir
  for orphan_dir in "${external_base}/"*/; do
    # An empty storage dir leaves the glob unexpanded — skip the literal "*".
    [[ -d "${orphan_dir}" ]] || continue

    local dir_name
    dir_name="$(basename "${orphan_dir}")"

    # Declared by a module (any state) → keep.
    if echo "${declared}" | grep -Fxq "${dir_name}" 2>/dev/null; then
      continue
    fi

    # Registered in the config (CLI `module add` / hand-written) → keep.
    if echo "${configured}" | grep -Fxq "${dir_name}" 2>/dev/null; then
      continue
    fi

    _warn "Removing orphaned external module storage: ${dir_name} (not declared by any module)"
    rm -rf "${orphan_dir}"
  done
}

# _link_memory_folders — links memory for built-in + external modules.
# Idempotent. Called by tests and by main().
# Gitignore is handled by the memory module (src/agentic/memory/init.sh).

_link_memory_folders() {
  local memory_dir
  memory_dir="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")/memory"

  local disabled_list
  disabled_list=$(echo "$(_devbot_get_disabled_modules "${PROJECT_DIR}")" | python3 -c "
import json, sys
for m in json.loads(sys.stdin.read()):
    print(m)
" 2>/dev/null || true)

  # External names declared only by a disabled umbrella: skip their memory links.
  local disabled_external_list
  disabled_external_list="$(_devbot_disabled_external_names "${PROJECT_DIR}")"

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
    if echo "${disabled_external_list}" | grep -Fxq "${ext_mod_name}" 2>/dev/null; then
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
    # --force: accepted by format-json for compatibility; formatting no longer
    # depends on a project prettier config, so the MCP-merge output keeps its
    # inserted-entry formatting (audit-69 NOTE-4).
    bash "${fmt_tool}" --force "${config}" 2>/dev/null && _ok "opencode.jsonc formatted" || true
  fi
}

# ── Remove broken symlinks from the devbot dir ────────────────────────────────
# Run LAST (after every module/harness init) so it catches dangling symlinks left
# by module renames/removals anywhere in the devbot dir.
_remove_broken_symlinks() {
  local target
  target="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")"
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

# ── Keep generated module memory out of the project's history ─────────────────
# Each enabled module writes its own active/modules/<name>.md on init and reinit
# clears the folder first, so the content is machine-local output. The entry is
# unconditional: it must be in place before the first module writes, and a
# project with no module memory yet still gets it.
_ignore_module_memory() {
  local project_dir="$1"
  local devbot_dir="$2"

  # The value comes from project config; an escaping path must not be written
  # into .gitignore as an ignore rule that then reads as project intent.
  if ! _devbot_is_plain_relative_path "${devbot_dir}"; then
    _warn "not ignoring module memory: devbot_dir '${devbot_dir}' is not a plain relative path"
    return 0
  fi

  # `rev-parse`, not a `.git` directory test: in a linked worktree and in a
  # submodule `.git` is a file, and both are normal places to run init.
  git -C "${project_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  if _upsert_gitignore_section "${project_dir}/.gitignore" \
    "# >>> DEVBOT - module memory" \
    "# <<< DEVBOT - module memory" \
    "${devbot_dir}/memory/active/modules/"; then
    _ok ".gitignore ignores ${devbot_dir}/memory/active/modules/"
  else
    _warn "could not add ${devbot_dir}/memory/active/modules/ to .gitignore"
  fi
}

_init_wiring() {
  PROJECT_DIR="$1"
  local total_start=${SECONDS}

  _header_2 "Wiring ${PROJECT_DIR}"

  _migrate_workspace_config "${PROJECT_DIR}/.devbot.project.jsonc"

  # Mark the wiring dirty for the duration of this init: a run interrupted
  # before step 8b leaves the baseline missing, so the next `devbot` start
  # re-detects the change and re-runs init to repair the tree.
  _devbot_clear_config_sha "${PROJECT_DIR}"

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

  # ── 1b. Module memory is generated, never committed ──────────────────────
  _ignore_module_memory "${PROJECT_DIR}" "${devbot_dir}"

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
  # `devbot init --all` the DEV_BOT_DEFER_ENV_DIALOG marker collapses this
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
  local global_config="${DEV_BOT_GLOBAL_CONFIG:-${DEV_BOT_ROOT}/.devbot.global.jsonc}"
  if [[ -f "${add_project_py}" && -f "${global_config}" ]]; then
    python3 "${add_project_py}" "${global_config}" "${PROJECT_DIR}" 2>/dev/null || true
  fi

  # ── 8. Remove broken symlinks (after every init has run) ────────────────
  _header_2 "Broken Symlink Cleanup"
  _remove_broken_symlinks

  # ── 8b. Baseline wiring hash (auto-reinit detection) ────────────────────
  # Record the combined hash of the global + project configs AFTER
  # registration/symlink steps mutated them, so the next `devbot` start
  # compares equal and does not re-trigger a reinit. Written by every wiring
  # run — the reset path ends by calling this, so it refreshes it too. Missing
  # .sha (fresh project, or an install upgrading from the retired per-file
  # baselines) counts as changed, so one init establishes it.
  _devbot_write_config_sha "${PROJECT_DIR}"

  # ── 9. Final header ─────────────────────────────────────────────────────
  _header_2 "✔  DevBot init complete, you still should run the '/create-codebase-report' command on the first time you start the agent"

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

# ── Reset path ────────────────────────────────────────────────────────────────
#
# An initialised project is reset before wiring; a fresh one is wired directly.

# Read the projects array from the global config.
_get_projects() {
  local config
  config="$(_devbot_global_config)"
  if [[ ! -f "${config}" ]]; then
    echo "[]"
    return
  fi

  python3 -c "
import json, sys
sys.path.insert(0, '${DEV_BOT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
try:
    data = load_jsonc('${config}')
    projects = data.get('projects', [])
    print(json.dumps(projects))
except Exception as e:
    print('[]', file=sys.stderr)
" 2>/dev/null || echo "[]"
}

# Run a reset script for a given project. FULL_RESET passes --full through.
_run_reset() {
  local reset_script="$1"
  local project_dir="$2"

  if [[ ! -f "${reset_script}" || ! -x "${reset_script}" ]]; then
    return 1
  fi

  local name
  name="$(basename "$(dirname "${reset_script}")")"
  _header_3 "Running ${name} reset..."
  local start=${SECONDS}

  local -a args=("${reset_script}" "${project_dir}")
  if [[ "${FULL_RESET:-false}" == "true" ]]; then
    args+=("--full")
  fi

  if bash "${args[@]}"; then
    _ok "${name} reset done ($(_fmt_duration $(( SECONDS - start ))))"
  else
    _warn "${name} reset had issues (exit: $?)"
  fi
}

# Resolve the module-memory folders, refusing anything that escapes the
# project — the caller deletes them. Sets _MODULE_MEMORY_ACTIVE/_MODULES.
_module_memory_paths() {
  local project_dir="$1"

  _MODULE_MEMORY_ACTIVE=""
  _MODULE_MEMORY_MODULES=""

  # Both paths come from `_devbot_module_memory_path`, which rejects an escaping
  # `devbot_dir` and a symlink anywhere along the vault path.
  if ! _MODULE_MEMORY_ACTIVE="$(_devbot_module_memory_path "${project_dir}" active)"; then
    _warn "init — refusing module memory cleanup for ${project_dir}"
    return 1
  fi

  if ! _MODULE_MEMORY_MODULES="$(_devbot_module_memory_path "${project_dir}" modules)"; then
    _warn "init — refusing module memory cleanup for ${project_dir}"
    return 1
  fi
}

# A function under if/|| loses errexit, so wire in a
# child; the flag skips the detection recursion.
_wire_project() {
  DEV_BOT_WIRING_ONLY=1 bash "${DEV_BOT_ROOT}/bin/init.sh" "$1"
}

# Reset a single project, then wire it.
_reinit_project() {
  local project_dir="$1"
  shift
  # Remaining args are reset scripts, split by marker
  local -a scripts=("$@")

  if [[ ! -d "${project_dir}" ]]; then
    _warn "Directory does not exist — skipping: ${project_dir}"
    return
  fi

  # Module memory is regenerated during init. Validated first: a refused
  # project must not have its tree mutated by the reset scripts.
  local active_dir modules_dir
  if ! _module_memory_paths "${project_dir}"; then
    return 1
  fi
  active_dir="${_MODULE_MEMORY_ACTIVE}"
  modules_dir="${_MODULE_MEMORY_MODULES}"

  # Mark the wiring dirty BEFORE the reset scripts delete anything: a run
  # killed mid-way leaves the baseline missing, so the next `devbot` start
  # re-detects the change and repairs the tree. The wiring restores it.
  _devbot_clear_config_sha "${project_dir}"

  # Run all provided reset scripts
  if [[ ${#scripts[@]} -gt 0 ]]; then
    for reset_script in "${scripts[@]}"; do
      _run_reset "${reset_script}" "${project_dir}" || true
    done
  fi

  if [[ -d "${modules_dir}" ]]; then
    rm -rf -- "${modules_dir}"
    _ok "Cleared ${modules_dir#"${project_dir}/"}"
  fi

  # Pre-modules locations. They are cleaned here, not only in the module's own
  # init.sh, because a disabled module's init never runs and would leave its
  # old copy behind as a second source.
  local legacy
  for legacy in graphify.md aws-agent-rules.md; do
    rm -f -- "${active_dir}/${legacy}"
  done

  _header_3 "Running devbot init..."
  local init_start=${SECONDS}
  if _wire_project "${project_dir}"; then
    _ok "devbot init done ($(_fmt_duration $(( SECONDS - init_start ))))"
    return 0
  fi

  # Propagate the failure: the auto-reinit caller aborts the start on a
  # non-zero exit, so swallowing it launches on half-built wiring.
  _error "devbot init failed for ${project_dir}"
  return 1
}

# ── Dispatch ─────────────────────────────────────────────────────────────────

_usage() {
  echo "Usage: devbot init [<project-dir>] [--all|-a] [--full|-f]"
  echo ""
  echo "Initialise dev-bot for a project, the current directory, or all"
  echo "registered projects. A project that is already initialised is reset"
  echo "first, so re-running 'devbot init' is safe and idempotent."
  echo ""
  echo "Arguments:"
  echo "  <project-dir>  Project to initialise (default: current directory)"
  echo ""
  echo "Options:"
  echo "  --all, -a    Initialise all registered projects"
  echo "  --full, -f   Full reset: remove QMD collection + codebase index data"
  echo "  --help, -h   Show this help"
}

_process_project() {
  local project_dir="$1"
  shift
  local -a reset_scripts=("$@")

  # A stale entry can stay in the global registry after a directory is moved.
  if [[ ! -d "${project_dir}" ]]; then
    _warn "Directory does not exist — skipping: ${project_dir}"
    return 0
  fi

  if _devbot_project_initialized "${project_dir}"; then
    _info "Already initialised — resetting before wiring"
    _reinit_project "${project_dir}" "${reset_scripts[@]+"${reset_scripts[@]}"}"
    return
  fi

  _info "Not initialised yet — wiring from scratch"
  _wire_project "${project_dir}"
}

main() {
  local total_start=${SECONDS}
  local failed=0

  # Internal: the reset path re-enters this script to wire one project with
  # errexit live (see _wire_project), skipping the detection below.
  if [[ "${DEV_BOT_WIRING_ONLY:-0}" == "1" ]]; then
    _init_wiring "${1:?wiring target required}"
    exit 0
  fi

  _header_1 "DevBot Init"

  # ── 1. Parse arguments ───────────────────────────────────────────────────
  local all_projects=false
  local target_project=""
  FULL_RESET=false

  local arg
  for arg in "$@"; do
    case "${arg}" in
      --all|-a)
        all_projects=true
        ;;
      --full|-f)
        FULL_RESET=true
        ;;
      --help|-h)
        _usage
        exit 0
        ;;
      -*)
        _error "Unknown option: ${arg}"
        _usage >&2
        exit 1
        ;;
      *)
        if [[ -n "${target_project}" ]]; then
          _error "Too many arguments: ${target_project} ${arg}"
          exit 1
        fi
        target_project="${arg}"
        ;;
    esac
  done

  # Mutually exclusive: defaulting to the broader interpretation would turn a
  # typo into a --full reset of every registered project.
  if [[ "${all_projects}" == "true" && -n "${target_project}" ]]; then
    _error "Cannot combine --all with a project path (${target_project})"
    exit 1
  fi

  if [[ "${FULL_RESET}" == "true" ]]; then
    _info "Full reset mode: QMD collections and codebase index data will be removed"
  fi

  # The global config is the fallback every workspace reader resolves to, and
  # it belongs to no project, so it is migrated once here rather than per sweep.
  _migrate_workspace_config "$(_devbot_global_config)"

  # ── 2. Read registered projects ──────────────────────────────────────────
  local projects_json
  projects_json="$(_get_projects)"

  local project_count
  project_count=$(echo "${projects_json}" | python3 -c "import json,sys; print(len(json.loads(sys.stdin.read())))" 2>/dev/null || echo "0")

  # ── 3. Discover reset scripts (unified — tools + agentic + external) ─────
  local -a reset_scripts=()
  local -a reset_base_dirs=("${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses")
  [[ -d "${DEV_BOT_ROOT}/storage/external-agentic-modules" ]] && reset_base_dirs+=("${DEV_BOT_ROOT}/storage/external-agentic-modules")

  while IFS= read -r script; do
    [[ -n "${script}" ]] && reset_scripts+=("${script}")
  done < <(_collect_module_scripts "reset.sh" "${reset_base_dirs[@]}")

  _info "Found ${#reset_scripts[@]} reset script(s)"

  # ── 4. Determine mode: single project or all ─────────────────────────────
  if [[ "${all_projects}" == "true" ]]; then
    # --all: process every registered project
    if [[ ${project_count} -eq 0 ]]; then
      _info "No projects registered in the global config"
      _info "Run 'devbot init' in a project to register it first."
      exit 0
    fi

    _info "Found ${project_count} registered project(s):"
    echo "${projects_json}" | python3 -c "
import json, sys
for p in json.loads(sys.stdin.read()):
    print(f'    {p}')
" 2>/dev/null
    echo

    local i=0
    # Each per-project init emits only a compact env-var notice; the single
    # end-of-run dialog below shows the union across all projects.
    export DEV_BOT_DEFER_ENV_DIALOG=1
    while IFS= read -r project_dir; do
      i=$((i + 1))
      _header_2 "Project ${i}/${project_count}: ${project_dir}"
      _process_project "${project_dir}" "${reset_scripts[@]+"${reset_scripts[@]}"}" || failed=1
      echo
    done < <(echo "${projects_json}" | python3 -c "
import json, sys
for p in json.loads(sys.stdin.read()):
    print(p)
" 2>/dev/null)
    unset DEV_BOT_DEFER_ENV_DIALOG

    # ── 4b. End-of-run env-var dialog (union across every processed project) ──
    # init.sh only warned per project (deferred). Present the union once:
    # collect refs from all projects, dedupe, and run the full notice + ack.
    local union_refs=""
    while IFS= read -r project_dir; do
      [[ -d "${project_dir}" ]] || continue
      local proj_refs
      proj_refs="$(_devbot_missing_mcp_env_vars "${project_dir}")"
      if [[ -n "${proj_refs}" ]]; then
        union_refs+="${proj_refs}"$'\n'
      fi
    done < <(echo "${projects_json}" | python3 -c "
import json, sys
for p in json.loads(sys.stdin.read()):
    print(p)
" 2>/dev/null)

    if [[ -n "${union_refs}" ]]; then
      # Dedupe identical ref lines across projects (same module+server+key+var).
      local deduped
      deduped="$(echo "${union_refs}" | awk '!seen[$0]++')"
      _devbot_present_missing_env_vars "${deduped}" ack
    fi
  elif [[ -n "${target_project}" ]]; then
    if [[ ! -d "${target_project}" ]]; then
      _error "Not a directory: ${target_project}"
      exit 1
    fi
    _process_project "$(cd "${target_project}" && pwd)" "${reset_scripts[@]+"${reset_scripts[@]}"}" || failed=1
  else
    # Single project: init the current working directory
    _process_project "$(pwd)" "${reset_scripts[@]+"${reset_scripts[@]}"}" || failed=1
  fi

  # ── 5. Summary ──────────────────────────────────────────────────────────
  if [[ "${failed}" -ne 0 ]]; then
    _error "Init failed — fix the cause and re-run 'devbot init'."
    echo
    exit 1
  fi

  if [[ "${all_projects}" == "true" ]]; then
    _header_2 "✔  DevBot init complete for ${project_count} project(s)"
  fi
  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"

