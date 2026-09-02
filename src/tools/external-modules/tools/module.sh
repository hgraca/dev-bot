#!/usr/bin/env bash
# =============================================================================
# src/tools/external-modules/tools/module.sh
# DevBot module manager — register/list/remove external modules and wire them
# into projects.
#
# Usage:
#   module.sh install    # clone/pull configured external modules
#   module.sh init [path] # wire modules into a project's .agents/ dir
#   module.sh add <url|path>   # register a module (git URL or local path)
#   module.sh remove <name>    # unregister a module
#   module.sh list              # list registered modules
#   module.sh sync [path]       # re-wire all modules (alias for init)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${SCRIPT_DIR}/../../../.." && pwd)}"
MODULES_DIR="${DEV_BOT_ROOT}/vendor"
CONFIG_FILE="${DEV_BOT_ROOT}/.devbot.global.jsonc"
READ_JSONC="${SCRIPT_DIR}/../../../_shared/read_jsonc.py"
MERGE_JSONC="${SCRIPT_DIR}/../../../_shared/merge_modules_jsonc.py"

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../../../_shared/functions.sh
source "${SCRIPT_DIR}/../../../_shared/functions.sh"
# shellcheck source=../functions.sh
source "${SCRIPT_DIR}/../functions.sh"

# ── Helpers ────────────────────────────────────────────────────────────────────
_url_to_name() {
    local url="${1%/}"
    url="${url%.git}"
    basename "${url}"
}


_ensure_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        _step "Creating .devbot.global.jsonc ..."
        echo '{}' > "${CONFIG_FILE}"
        _ok ".devbot.global.jsonc created"
    fi
}

_read_external_modules() {
    python3 "${READ_JSONC}" "${CONFIG_FILE}" external_modules 2>/dev/null || echo "{}"
}

_get_external_module_field() {
    local name="$1" field="$2"
    python3 "${READ_JSONC}" "${CONFIG_FILE}" external_modules "${name}" "${field}" 2>/dev/null || true
}

# Register a module in external_modules via the comment-preserving merge script.
# Args: $1 name, $2 url (or empty), $3 path (or empty), $4 paths JSON.
_register_entry() {
    local name="$1" url="$2" path="$3" paths_json="$4"
    local tmp_entries
    tmp_entries="$(mktemp)"
    if ! python3 -c "
import json, sys
name, url, path, paths = sys.argv[1:5]
entry = {'paths': json.loads(paths)}
if url:
    entry['url'] = url
if path:
    entry['path'] = path
json.dump({name: entry}, open(sys.argv[5], 'w'))
" "${name}" "${url}" "${path}" "${paths_json}" "${tmp_entries}"; then
        rm -f "${tmp_entries}"
        return 1
    fi
    python3 "${MERGE_JSONC}" "${CONFIG_FILE}" "${tmp_entries}"
    local rc=$?
    rm -f "${tmp_entries}"
    return ${rc}
}

_discover_projects() {
    # Find projects with a .devbot.project.jsonc file
    while IFS= read -r _f; do
        echo "$(dirname "${_f}")"
    done < <(find "${DEV_BOT_ROOT}" -maxdepth 5 -path '*/node_modules/*' -prune -o -name '.devbot.project.jsonc' -print 2>/dev/null || true)

    # Also check the devbot root itself
    if [[ -f "${DEV_BOT_ROOT}/.devbot.project.jsonc" || -f "${CONFIG_FILE}" ]]; then
        echo "${DEV_BOT_ROOT}"
    fi
}

_unwire_module() {
    local name="$1"
    shift
    for proj in "$@"; do
        for type in skills agents commands plugins; do
            local link_path="${proj}/.opencode/${type}/${name}"
            if [[ -L "${link_path}" ]]; then
                rm "${link_path}"
                _log "Removed .opencode/${type}/${name}"
            fi
        done
    done
}

# ── Subcommands ────────────────────────────────────────────────────────────────
cmd_install() {
    _ensure_config

    # Read modules configuration
    if ! python3 "${READ_JSONC}" "${CONFIG_FILE}" external_modules >/dev/null 2>&1; then
        _skip "No modules configured in .devbot.global.jsonc"
        return 0
    fi

    # Process each module
    while IFS=$'\x1f' read -r name url path paths_json; do
        if [[ -n "${path}" ]]; then
            # Local module - verify it exists
            if [[ ! -d "${path}" ]]; then
                _warn "${name}: local path not found (${path})"
                continue
            fi
            _skip "${name}: local module at ${path}"
        elif [[ -n "${url}" ]]; then
            # Git module - clone or pull
            local vendor_rel
            vendor_rel="$(_derive_vendor_path "${url}")"
            local dest="${MODULES_DIR}/${vendor_rel}"

            if [[ -d "${dest}/.git" ]]; then
                # Existing repo - fetch updates
                _info "Updating ${name} ..."
                (cd "${dest}" && git fetch --depth 1 origin +refs/heads/*:refs/remotes/origin/* && \
                  git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)) >/dev/null 2>&1 || {
                    _warn "Failed to update ${name}"
                    continue
                }
                _ok "${name} updated"
                _remove_readme_from_paths "${dest}" "${paths_json}"
            else
                # New repo - clone
                _info "Cloning ${name} ..."
                mkdir -p "$(dirname "${dest}")"
                git clone --depth 1 "${url}" "${dest}" >/dev/null 2>&1 || {
                    _warn "Failed to clone ${name}"
                    continue
                }
                _ok "${name} cloned"
                _remove_readme_from_paths "${dest}" "${paths_json}"
            fi
        else
            _warn "${name}: missing url and path — skipping"
            continue
        fi
    done < <(python3 "${READ_JSONC}" "${CONFIG_FILE}" external_modules | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for name, entry in data.items():
    if not isinstance(entry, dict):
        continue  # boolean enable/disable flags are not module definitions
    url = entry.get('url', '')
    path = entry.get('path', '')
    paths = json.dumps(entry.get('paths', {}))
    print(f'{name}\x1f{url}\x1f{path}\x1f{paths}')
    ")

    _ok "external-modules installation complete"
}

cmd_init() {
    local project_dir="${1:-$(pwd)}"
    project_dir="$(cd "${project_dir}" && pwd 2>/dev/null || true)"

    if [[ -z "${project_dir}" || ! -d "${project_dir}" ]]; then
        echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  Directory '${1:-.}' does not exist or cannot be resolved." >&2
        exit 1
    fi

    # Delegate to the module's init.sh — the single source of truth for wiring
    # external module artifacts into a project's devbot dir (.agents/). It wires
    # declared modules plus config-only local (path) modules.
    bash "${SCRIPT_DIR}/../init.sh" "${project_dir}"
}

cmd_list() {
    _ensure_config

    _header_2 "External Modules"

    local count=0
    local modules_json
    modules_json="$(_read_external_modules)"
    if [[ "${modules_json}" == "{}" || -z "${modules_json}" ]]; then
        _info "No modules registered."
        echo "  Add one: devbot module add <git-url>"
        return 0
    fi

    while IFS=$'\x1f' read -r _name _url _path _paths_json; do
        if [[ -n "${_path}" ]]; then
            # Local module
            local status="✔"
            [[ -d "${_path}" ]] || status="✖"
            printf "  %s  %s  [local]  (%s)\n" "${status}" "${_name}" "${_path}"
        else
            # Git module
            local vendor_rel
            vendor_rel="$(_derive_vendor_path "${_url}")"
            local dest="${MODULES_DIR}/${vendor_rel}"
            local cloned="✖"
            [[ -d "${dest}/.git" ]] && cloned="✔"
            printf "  %s  %s  [git]    (%s)\n" "${cloned}" "${_name}" "${vendor_rel}"
        fi
        count=$((count + 1))
    done < <(echo "${modules_json}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for name, entry in data.items():
    if not isinstance(entry, dict):
        continue  # boolean enable/disable flags are not module definitions
    print(name + '\x1f' + entry.get('url', '') + '\x1f' + entry.get('path', '') + '\x1f' + json.dumps(entry.get('paths', {})))
")

    if [[ ${count} -eq 0 ]]; then
        _info "No modules registered."
        echo "  Add one: devbot module add <git-url>"
    fi
}

cmd_add() {
    local url_or_path="${1:-}"
    if [[ -z "${url_or_path}" ]]; then
        _fatal "Usage: module.sh add <url|path> [--name=<name>] [--skills=<path>] [--agents=<path>] [--commands=<path>] [--plugins=<path>]"
        exit 1
    fi
    shift

    local opt_name="" opt_skills="" opt_agents="" opt_commands="" opt_plugins=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name=*)     opt_name="${1#*=}";     shift ;;
            --skills=*)   opt_skills="${1#*=}";   shift ;;
            --agents=*)   opt_agents="${1#*=}";   shift ;;
            --commands=*) opt_commands="${1#*=}"; shift ;;
            --plugins=*)  opt_plugins="${1#*=}";  shift ;;
            *) _fatal "Unknown option '$1'"; exit 1 ;;
        esac
    done

    _ensure_config

    local is_local=false local_abs_path=""
    if [[ -d "${url_or_path}" ]]; then
        is_local=true
        local_abs_path="$(cd -P "${url_or_path}" && pwd)"
    fi

    if [[ "${is_local}" == true ]]; then
        local name="${opt_name:-$(basename "${local_abs_path}")}"
        local existing_url existing_local
        existing_url="$(_get_external_module_field "${name}" "url")"
        existing_local="$(_get_external_module_field "${name}" "path")"
        if [[ -n "${existing_url}" || -n "${existing_local}" ]]; then
            _skip "Already registered: ${name}"
            return 0
        fi

        # Auto-detect paths
        _step "Detecting available paths ..."
        local paths_json
        paths_json="$(python3 -c "
import json, os
dest = '${local_abs_path}'
defaults = {'skills': '${opt_skills:-./skills}', 'agents': '${opt_agents:-./agents}', 'commands': '${opt_commands:-./commands}', 'plugins': '${opt_plugins:-./plugins}'}
paths = {}
for key, rel in defaults.items():
    if os.path.isdir(os.path.join(dest, rel)):
        paths[key] = rel
print(json.dumps(paths))
")"
        if [[ "${paths_json}" == "{}" ]]; then
            _warn "No standard paths found, using defaults"
            paths_json='{"skills":"./skills","agents":"./agents","commands":"./commands","plugins":"./plugins"}'
        fi

        _step "Registering in .devbot.global.jsonc ..."
        _register_entry "${name}" "" "${local_abs_path}" "${paths_json}"
        _ok "Registered: ${name} [local]"
        _log "Run 'devbot init <project>' to wire it into .agents/ — local modules are never cloned into vendor/"
    else
        local url="${url_or_path}"
        local name="${opt_name:-$(_url_to_name "${url}")}"
        _header_3 "Module add: ${name}"

        local existing_url existing_local
        existing_url="$(_get_external_module_field "${name}" "url")"
        existing_local="$(_get_external_module_field "${name}" "path")"
        if [[ -n "${existing_url}" || -n "${existing_local}" ]]; then
            _skip "Already registered: ${name}"
            return 0
        fi

        local vendor_rel
        vendor_rel="$(_derive_vendor_path "${url}")"
        local dest="${MODULES_DIR}/${vendor_rel}"

        if [[ -d "${dest}/.git" ]]; then
            _skip "Already cloned: ${dest}"
        else
            _step "Cloning ${url} → ${dest} ..."
            mkdir -p "$(dirname "${dest}")"
            git clone --depth 1 "${url}" "${dest}"
            _ok "Cloned ${name}"
        fi

        _step "Detecting available paths ..."
        local paths_json
        paths_json="$(python3 -c "
import json, os
dest = '${dest}'
defaults = {'skills': '${opt_skills:-./skills}', 'agents': '${opt_agents:-./agents}', 'commands': '${opt_commands:-./commands}', 'plugins': '${opt_plugins:-./plugins}'}
paths = {}
for key, rel in defaults.items():
    if os.path.isdir(os.path.join(dest, rel)):
        paths[key] = rel
print(json.dumps(paths))
")"
        if [[ "${paths_json}" == "{}" ]]; then
            _warn "No standard paths found, using defaults"
            paths_json='{"skills":"./skills","agents":"./agents","commands":"./commands","plugins":"./plugins"}'
        fi

        _remove_readme_from_paths "${dest}" "${paths_json}"

        _step "Registering in .devbot.global.jsonc ..."
        _register_entry "${name}" "${url}" "" "${paths_json}"
        _ok "Registered: ${name} [git]"
        _log "Run 'devbot install' then 'devbot init <project>' — git modules are wired from vendor/ when declared by an enabled module"
    fi
}

cmd_remove() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then
        _fatal "Usage: module.sh remove <name>"
        exit 1
    fi

    _header_3 "Module remove: ${name}"

    local existing_url existing_local
    existing_url="$(_get_external_module_field "${name}" "url")"
    existing_local="$(_get_external_module_field "${name}" "path")"

    if [[ -z "${existing_url}" && -z "${existing_local}" ]]; then
        _warn "Module '${name}' not found"
        return 0
    fi

    # Unwire from projects (legacy .opencode links)
    local -a projects
    while IFS= read -r _proj; do
        projects+=("${_proj}")
    done < <(_discover_projects | sort -u)
    _unwire_module "${name}" "${projects[@]}"

    # Unwire modern .agents/<type>/<name> links — capture the entry's paths
    # before removing it from config.
    local paths_json
    paths_json="$(_get_external_module_field "${name}" "paths")"
    if [[ -n "${paths_json}" ]]; then
        local _type
        while IFS= read -r _type; do
            [[ -z "${_type}" ]] && continue
            local _proj
            for _proj in "${projects[@]}"; do
                local devbot_dir link_path
                devbot_dir="$(_devbot_get_project_dir "${_proj}")"
                link_path="${_proj}/${devbot_dir}/${_type}/${name}"
                if [[ -L "${link_path}" ]]; then
                    rm "${link_path}"
                    _log "Removed ${devbot_dir}/${_type}/${name}"
                fi
            done
        done < <(echo "${paths_json}" | python3 -c "
import json, sys
try:
    paths = json.load(sys.stdin)
    print('\n'.join(paths.keys()))
except Exception:
    pass
")
    fi

    # Remove from config (comment-preserving)
    python3 "${MERGE_JSONC}" "${CONFIG_FILE}" --remove "${name}" >/dev/null 2>&1
    # Remove storage structure (config is now the source of truth — no longer configured)
    local storage_dir="${DEV_BOT_ROOT}/storage/external-agentic-modules/${name}"
    if [[ -d "${storage_dir}" ]]; then
        rm -rf "${storage_dir}"
        _ok "Removed storage: ${storage_dir}"
    fi

    _ok "Unregistered: ${name}"
}

cmd_sync() {
    # Deprecated alias for init — kept for backward compatibility
    shift
    cmd_init "$@"
}

# ── Dispatch ───────────────────────────────────────────────────────────────────
_cmd="${1:-}"
shift || true

case "${_cmd}" in
    install)    cmd_install    "$@" ;;
    init)       cmd_init       "$@" ;;
    add)        cmd_add        "$@" ;;
    remove)     cmd_remove     "$@" ;;
    list)       cmd_list        ;;
    sync)       cmd_sync       "$@" ;;
    help|--help|-h|"")
        echo "Usage: module.sh <subcommand> [args]"
        echo ""
        echo "Subcommands:"
        echo "  install    Clone/pull configured external modules"
        echo "  init [path] Wire modules into a project's .agents/ directory"
        echo "  add <url|path>   Register a module (git URL or local path)"
        echo "  remove <name>    Unregister a module"
        echo "  list              List registered modules"
        echo "  sync [path]       Re-wire all modules (alias for init)"
        echo ""
        echo "Notes:"
        echo "  - 'install' reads .devbot.global.jsonc and clones/pulls the configured modules."
        echo "  - 'init' wires the installed modules into a project's .agents/ directory (delegates to the module init.sh)."
        echo "  - 'add <dir>' registers a local module (path) — it is wired by 'devbot init', never cloned."
        echo "  - 'sync' is an alias for 'init' (provided for backward compatibility)."
        ;;
    *) _fatal "Unknown subcommand '${_cmd}'"; echo "  Run: module.sh help"; exit 1 ;;
esac
