#!/usr/bin/env bash
# =============================================================================
# src/tools/external-modules/tools/module.sh
# DevBot module manager — manage external module repos (clone, wire, sync).
#
# Usage:
#   module.sh install    # clone/pull configured external modules
#   module.sh init [path] # wire modules into .opencode/ dirs
#   module.sh add <url|path>   # register a module (git URL or local path)
#   module.sh remove <name>    # unregister a module
#   module.sh list              # list registered modules
#   module.sh sync [--project=<dir>]  # re-wire all modules (alias for init)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${SCRIPT_DIR}/../../../.." && pwd)}"
MODULES_DIR="${DEV_BOT_ROOT}/vendor"
CONFIG_FILE="${DEV_BOT_ROOT}/.devbot.global.jsonc"
READ_JSONC="${SCRIPT_DIR}/../../../_shared/read_jsonc.py"

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
        echo '{"modules":{}}' > "${CONFIG_FILE}"
        _ok ".devbot.global.jsonc created"
        return 0
    fi
    # Ensure modules key exists (use python to write clean JSON)
    if ! python3 "${READ_JSONC}" "${CONFIG_FILE}" modules 2>/dev/null; then
        _step "Fixing .devbot.global.jsonc (adding modules key)..."
        python3 -c "
import json
with open('${CONFIG_FILE}') as f:
    data = json.loads(__import__('re').sub(r'//.*', '', f.read()))
data.setdefault('modules', {})
with open('${CONFIG_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null || true
    fi
}

_read_modules() {
    python3 "${READ_JSONC}" "${CONFIG_FILE}" modules 2>/dev/null || echo "{}"
}

_get_module_field() {
    local name="$1" field="$2"
    python3 "${READ_JSONC}" "${CONFIG_FILE}" modules "${name}" "${field}" 2>/dev/null || true
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

_wire_module() {
    local name="$1" src_dir="$2" paths_json="$3"
    shift 3
    local project_dirs=("$@")

    for type in skills agents commands plugins; do
        local rel_path
        rel_path="$(python3 -c "
import json, sys
paths = json.loads('${paths_json}')
print(paths.get('${type}', ''))
")"
        [[ -z "${rel_path}" ]] && continue

        local type_src
        type_src="$(realpath "${src_dir}/${rel_path}" 2>/dev/null)" || continue
        [[ -d "${type_src}" ]] || continue

        for proj in "${project_dirs[@]}"; do
            local target_dir="${proj}/.opencode/${type}"
            local link_path="${target_dir}/${name}"
            mkdir -p "${target_dir}"
            if [[ -L "${link_path}" ]]; then
                local current
                current="$(readlink "${link_path}")"
                if [[ "${current}" == "${type_src}" ]]; then
                    _skip "${name} → .opencode/${type}/${name} (already correct)"
                else
                    rm "${link_path}"
                    ln -s "${type_src}" "${link_path}"
                    _log "${name} → .opencode/${type}/${name} repaired"
                fi
            elif [[ -e "${link_path}" ]]; then
                _warn "${link_path} exists but is not a symlink — skipping"
            else
                ln -s "${type_src}" "${link_path}"
                _log "${name} → .opencode/${type}/${name} linked"
            fi
        done
    done
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
    if ! python3 "${READ_JSONC}" "${CONFIG_FILE}" modules >/dev/null 2>&1; then
        _skip "No modules configured in .devbot.global.jsonc"
        return 0
    fi

    # Process each module
    while IFS=$'\x1f' read -r name url local_path paths_json; do
        if [[ -n "${local_path}" ]]; then
            # Local module - verify it exists
            if [[ ! -d "${local_path}" ]]; then
                _warn "${name}: local path not found (${local_path})"
                continue
            fi
            _skip "${name}: local module at ${local_path}"
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
            _warn "${name}: missing url and local_path — skipping"
            continue
        fi
    done < <(python3 "${READ_JSONC}" "${CONFIG_FILE}" modules | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for name, entry in data.items():
    url = entry.get('url', '')
    local_path = entry.get('local_path', '')
    paths = json.dumps(entry.get('paths', {}))
    print(f'{name}\x1f{url}\x1f{local_path}\x1f{paths}')
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

    DEV_BOT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
    CONFIG_FILE="${DEV_BOT_ROOT}/.devbot.global.jsonc"
    MODULES_DIR="${DEV_BOT_ROOT}/vendor"

    # Ensure config exists
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        _skip ".devbot.global.jsonc not found — nothing to wire"
        exit 0
    fi

    # Read modules configuration
    if ! python3 "${READ_JSONC}" "${CONFIG_FILE}" modules >/dev/null 2>&1; then
        _skip "No modules configured in .devbot.global.jsonc"
        exit 0
    fi

    # Discover projects to wire into (the specified project and optionally the devbot root)
    local -a projects=("${project_dir}")

    # Also wire into devbot root itself if it's a different directory and has a devbot.jsonc
    if [[ "${project_dir}" != "${DEV_BOT_ROOT}" && -f "${DEV_BOT_ROOT}/.devbot.project.jsonc" ]]; then
        projects+=("${DEV_BOT_ROOT}")
    fi

    # Deduplicate projects
    IFS=$'\n' read -r -d '' -a unique_projects < <(printf '%s\0' "${projects[@]}" | sort -zu | tr '\0' '\n' && printf '\0')
    projects=("${unique_projects[@]}")

    # Process each module
    while IFS=$'\x1f' read -r name url local_path paths_json; do
        # Determine source directory
        if [[ -n "${local_path}" ]]; then
            local src_dir="${local_path}"
        elif [[ -n "${url}" ]]; then
            local vendor_rel
            vendor_rel="$(_derive_vendor_path "${url}")"
            local src_dir="${MODULES_DIR}/${vendor_rel}"
            # Ensure the module is cloned (should have been done by install.sh)
            if [[ ! -d "${src_dir}" ]]; then
                _warn "${name}: source not found at ${src_dir} — run install.sh first"
                continue
            fi
        else
            _warn "${name}: missing url and local_path — skipping"
            continue
        fi

        # Parse paths JSON
        local paths_map
        paths_map="$(python3 -c "
import json, sys
paths = json.loads('${paths_json}')
# Output as key=value lines
for k, v in paths.items():
    print(f'{k}={v}')
")"

        # Wire each path type
        while IFS='=' read -r type rel_path; do
            [[ -z "${type}" || -z "${rel_path}" ]] && continue
            [[ ! -d "${src_dir}/${rel_path}" ]] && continue

            local type_src="${src_dir}/${rel_path}"
            for proj in "${projects[@]}"; do
                local target_dir="${proj}/.opencode/${type}"
                local link_path="${target_dir}/${name}"

                mkdir -p "${target_dir}"

                if [[ -L "${link_path}" ]]; then
                    local current
                    current="$(readlink "${link_path}")"
                    if [[ "${current}" == "${type_src}" ]]; then
                        _skip "${name} → .opencode/${type}/${name} (already correct)"
                    else
                        rm "${link_path}"
                        ln -s "${type_src}" "${link_path}"
                        _log "${name} → .opencode/${type}/${name} repaired"
                    fi
                elif [[ -e "${link_path}" ]]; then
                    _warn "${link_path} exists but is not a symlink — skipping"
                else
                    ln -s "${type_src}" "${link_path}"
                    _log "${name} → .opencode/${type}/${name} linked"
                fi
            done
        done <<< "${paths_map}"
    done < <(python3 "${READ_JSONC}" "${CONFIG_FILE}" modules | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for name, entry in data.items():
    url = entry.get('url', '')
    local_path = entry.get('local_path', '')
    paths = json.dumps(entry.get('paths', {}))
    print(f'{name}\x1f{url}\x1f{local_path}\x1f{paths}')
    ")

    _ok "external-modules wiring complete"
}

cmd_list() {
    _ensure_config

    _header_2 "External Modules"

    local count=0
    local modules_json
    modules_json="$(_read_modules)"
    if [[ "${modules_json}" == "{}" || -z "${modules_json}" ]]; then
        _info "No modules registered."
        echo "  Add one: devbot module add <git-url>"
        return 0
    fi

    while IFS=$'\x1f' read -r _name _url _local_path _paths_json; do
        if [[ -n "${_local_path}" ]]; then
            # Local module
            local status="✔"
            [[ -d "${_local_path}" ]] || status="✖"
            printf "  %s  %s  [local]  (%s)\n" "${status}" "${_name}" "${_local_path}"
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
    print(name + '\x1f' + entry.get('url', '') + '\x1f' + entry.get('local_path', '') + '\x1f' + json.dumps(entry.get('paths', {})))
")

    if [[ ${count} -eq 0 ]]; then
        _info "No modules registered."
        echo "  Add one: devbot module add <git-url>"
    fi
}

cmd_add() {
    local url_or_path="${1:-}"
    if [[ -z "${url_or_path}" ]]; then
        _error "Usage: module.sh add <url|path> [--name=<name>] [--skills=<path>] [--agents=<path>] [--commands=<path>] [--plugins=<path>]"
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
            *) _error "Unknown option '$1'"; exit 1 ;;
        esac
    done

    _ensure_config

    local is_local=false local_abs_path=""
    if [[ -d "${url_or_path}" ]]; then
        is_local=true
        local_abs_path="$(realpath "${url_or_path}")"
    fi

    if [[ "${is_local}" == true ]]; then
        local name="${opt_name:-$(basename "${local_abs_path}")}"
        local existing_url existing_local
        existing_url="$(_get_module_field "${name}" "url")"
        existing_local="$(_get_module_field "${name}" "local_path")"
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
        python3 "${READ_JSONC}" "${CONFIG_FILE}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
modules = data.setdefault('modules', {})
modules['${name}'] = {'local_path': '${local_abs_path}', 'paths': ${paths_json}}
with open('${CONFIG_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
        _ok "Registered: ${name}"
    else
        local url="${url_or_path}"
        local name="${opt_name:-$(_url_to_name "${url}")}"
        _header_3 "Module add: ${name}"

        local existing_url existing_local
        existing_url="$(_get_module_field "${name}" "url")"
        existing_local="$(_get_module_field "${name}" "local_path")"
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
        python3 "${READ_JSONC}" "${CONFIG_FILE}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
modules = data.setdefault('modules', {})
modules['${name}'] = {'url': '${url}', 'paths': ${paths_json}}
with open('${CONFIG_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
        _ok "Registered: ${name}"

        _step "Wiring into projects ..."
        local -a projects
        while IFS= read -r _proj; do
            projects+=("${_proj}")
        done < <(_discover_projects | sort -u)

        if [[ ${#projects[@]} -eq 0 ]]; then
            _info "No projects found — run 'devbot init <path>' first"
            return 0
        fi

        local src_dir="${local_abs_path:-${dest}}"
        _wire_module "${name}" "${src_dir}" "${paths_json}" "${projects[@]}"
        _ok "Wired into ${#projects[@]} project(s)"
    fi
}

cmd_remove() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then
        _error "Usage: module.sh remove <name>"
        exit 1
    fi

    _header_3 "Module remove: ${name}"

    local existing_url existing_local
    existing_url="$(_get_module_field "${name}" "url")"
    existing_local="$(_get_module_field "${name}" "local_path")"

    if [[ -z "${existing_url}" && -z "${existing_local}" ]]; then
        _warn "Module '${name}' not found"
        return 0
    fi

    # Unwire from projects
    local -a projects
    while IFS= read -r _proj; do
        projects+=("${_proj}")
    done < <(_discover_projects | sort -u)
    _unwire_module "${name}" "${projects[@]}"

    # Remove from config
    python3 "${READ_JSONC}" "${CONFIG_FILE}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
data.get('modules', {}).pop('${name}', None)
with open('${CONFIG_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
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
        echo "  init [path] Wire modules into .opencode/ directories"
        echo "  add <url|path>   Register a module (git URL or local path)"
        echo "  remove <name>    Unregister a module"
        echo "  list              List registered modules"
        echo "  sync [--project=<dir>]  Re-wire all modules (alias for init)"
        echo ""
        echo "Notes:"
        echo "  - 'install' reads .devbot.global.jsonc and clones/pulls the configured modules."
        echo "  - 'init' wires the installed modules into .opencode/ directories of projects."
        echo "  - 'sync' is an alias for 'init' (provided for backward compatibility)."
        ;;
    *) _error "Unknown subcommand '${_cmd}'"; echo "  Run: module.sh help"; exit 1 ;;
esac
