#!/usr/bin/env bash
# src/tools/external-modules/functions.sh
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate,
# plus module-local helpers.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Derive a vendor directory path from a git URL.
# Actual semantics: strip a trailing .git and any *:// scheme+host, then drop
# the first remaining path segment (the host's org/user namespace).
#   https://github.com/org/repo.git  →  org/repo
#   https://github.com/org/repo       →  org/repo
# scp-style (git@host:org/repo.git) has no *:// scheme, so only the part after
# the first '/' survives — it derives to a single segment (repo). Declared
# modules use https URLs, which is what the vendor layout expects.
_derive_vendor_path() {
    local url="${1%/}"
    url="${url%.git}"
    local path_part="${url#*://}"
    path_part="${path_part#*/}"
    echo "${path_part}"
}

# Remove README files (case-insensitive) from each path subdirectory
# within a cloned module. Prevents READMEs from being symlinked into
# .opencode/{agents,skills,commands}/ via init.sh.
_remove_readme_from_paths() {
    local src_dir="$1"
    local paths_json="$2"

    python3 -c "
import json, os, sys

src_dir = sys.argv[1]
paths = json.loads(sys.argv[2])

for rel_path in paths.values():
    if not isinstance(rel_path, str):
        continue
    target = os.path.join(src_dir, rel_path)
    if not os.path.isdir(target):
        continue
    for entry in os.listdir(target):
        full = os.path.join(target, entry)
        if os.path.isfile(full):
            name, _ = os.path.splitext(entry)
            if name.lower() == 'readme':
                os.remove(full)
                print(f'  removed {full}')
" "$src_dir" "$paths_json" || true
}

# Set up external module storage structure.
# Creates storage/external-agentic-modules/<sanitized-name>/ with:
#   - Directory symlinks for string-valued paths (e.g. "skills" -> "skills")
#   - File symlinks for object-valued paths (e.g. {"CLAUDE.md": "bootstrap/..."})
# The config name is sanitized via _external_storage_dir_name (org/repo ->
# org__repo) so the storage dir stays a single path segment.
#
# Args:
#   $1  src_dir  — vendor directory (or local path) for the module
#   $2  name     — module name from config
#   $3  paths_json — JSON string of the paths map from config
#   $4  dev_bot_root — root of dev-bot installation
_setup_external_module_storage() {
    local src_dir="$1"
    local name="$2"
    local paths_json="$3"
    local dev_bot_root="$4"

    local storage_base="${dev_bot_root}/storage/external-agentic-modules/$(_external_storage_dir_name "${name}")"

    _step "${name}: setting up storage structure..."

    python3 -c "
import json, os, sys, shutil

src_dir = sys.argv[1]
paths = json.loads(sys.argv[2])
storage_base = sys.argv[3]
name = sys.argv[4]

expected_dirs = set()
expected_files = set()

for path_type, value in paths.items():
    dest_dir = os.path.join(storage_base, path_type)
    expected_dirs.add(dest_dir)

    if isinstance(value, str):
        source = os.path.join(src_dir, value)
        if not os.path.isdir(source):
            print(f'  \u26a0  {name}/{path_type} \u2014 source dir not found: {source}')
            continue

        if os.path.islink(dest_dir):
            current = os.readlink(dest_dir)
            if current == source:
                print(f'  \u203a  {name}/{path_type} \u2014 already correct')
            else:
                os.unlink(dest_dir)
                os.symlink(source, dest_dir)
                print(f'  -  {name}/{path_type} \u2192 {source} (repaired)')
        elif os.path.exists(dest_dir):
            print(f'  \u26a0\u26a0  {name}/{path_type} \u2014 exists but not symlink: {dest_dir}')
        else:
            os.makedirs(os.path.dirname(dest_dir), exist_ok=True)
            os.symlink(source, dest_dir)
            print(f'  -  {name}/{path_type} \u2192 {source}')

    elif isinstance(value, dict):
        for src_file, dest_rel_path in value.items():
            source_file = os.path.join(src_dir, src_file)
            if not os.path.exists(source_file):
                print(f'  \u26a0  {name}/{path_type}/{dest_rel_path} \u2014 source not found: {source_file}')
                continue

            dest_file = os.path.join(dest_dir, dest_rel_path)
            expected_files.add(dest_file)
            expected_dirs.add(os.path.dirname(dest_file))
            dest_parent = os.path.dirname(dest_file)

            if os.path.islink(dest_file):
                current = os.readlink(dest_file)
                if current == source_file:
                    print(f'  \u203a  {name}/{path_type}/{dest_rel_path} \u2014 already correct')
                else:
                    os.unlink(dest_file)
                    os.symlink(source_file, dest_file)
                    print(f'  -  {name}/{path_type}/{dest_rel_path} \u2192 {source_file} (repaired)')
            elif os.path.exists(dest_file):
                print(f'  \u26a0\u26a0  {name}/{path_type}/{dest_rel_path} \u2014 exists but not symlink: {dest_file}')
            else:
                os.makedirs(dest_parent, exist_ok=True)
                os.symlink(source_file, dest_file)
                print(f'  -  {name}/{path_type}/{dest_rel_path} \u2192 {source_file}')
    else:
        print(f'  \u26a0  {name}/{path_type} \u2014 unknown value type: {type(value).__name__}')

# --- Lifecycle script symlinks (mirror internal module lifecycle) ---
lifecycle_scripts = ['functions.sh', 'pre.sh', 'install.sh', 'update.sh', 'up.sh', 'down.sh', 'init.sh', 'reset.sh', 'uninstall.sh']
for script in lifecycle_scripts:
    source_file = os.path.join(src_dir, script)
    dest_file = os.path.join(storage_base, script)
    if not os.path.isfile(source_file):
        continue
    expected_files.add(dest_file)
    if os.path.islink(dest_file):
        if os.readlink(dest_file) == source_file:
            continue
        os.unlink(dest_file)
    elif os.path.exists(dest_file):
        print(f'  \u26a0\u26a0  {name}/{script} \u2014 exists but not symlink: {dest_file}')
        continue
    os.symlink(source_file, dest_file)
    print(f'  -  {name}/{script} \u2192 {source_file}')

# --- Stale entry cleanup ---
# Remove files and empty dirs in storage that are not in the expected set.
if os.path.isdir(storage_base):
    # Collect all existing files under storage
    for root, dirs, files in os.walk(storage_base, topdown=False):
        for fname in files:
            fpath = os.path.join(root, fname)
            if fpath not in expected_files:
                os.unlink(fpath)
                print(f'  -  {name} stale file removed: {os.path.relpath(fpath, storage_base)}')
        for dname in dirs:
            dpath = os.path.join(root, dname)
            if dpath not in expected_dirs:
                try:
                    shutil.rmtree(dpath)
                    print(f'  -  {name} stale dir removed: {os.path.relpath(dpath, storage_base)}')
                except OSError:
                    pass
" "$src_dir" "$paths_json" "$storage_base" "$name" 2>&1 || true
}

# Prune stale external module config entries — entries whose key is declared
# by a *disabled* internal module (e.g. a disabled module's declaration that
# was merged into config before the module was disabled). Entries with no
# declaring module (CLI-added, local `path`) are intentional and kept.
# Args:
#   $1  config_file     — .devbot.global.jsonc
#   $2  dev_bot_root    — root of dev-bot installation
#   $3  disabled_json   — JSON array of disabled module names
#   $4  merge_script    — path to merge_modules_jsonc.py
_prune_stale_external_modules() {
    local config_file="$1"
    local dev_bot_root="$2"
    local disabled_json="$3"
    local merge_script="$4"

    local shared_dir
    shared_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../_shared" && pwd)"

    local stale_names
    stale_names=$(python3 -c "
import json, sys, glob
sys.path.insert(0, '${shared_dir}')
from read_jsonc import load_jsonc
root = '${dev_bot_root}'
disabled = set(json.loads('${disabled_json}'))
owner = {}
for pattern in ('src/agentic/*/external-modules.json', 'src/tools/*/external-modules.json'):
    for f in glob.glob(root + '/' + pattern):
        mod = f.split('/')[-2]
        try:
            with open(f) as fh:
                for name in json.load(fh):
                    # Prefer an enabled owner over a disabled one if both declare it.
                    if name not in owner or owner[name] in disabled:
                        owner[name] = mod
        except Exception:
            continue
data = load_jsonc('${config_file}')
modules = data.get('external_modules', {})
stale = []
for name, entry in modules.items():
    if not isinstance(entry, dict):
        continue
    owning = owner.get(name, '')
    if owning and owning in disabled:
        stale.append(name)
print('\n'.join(sorted(stale)))
" 2>/dev/null || true)

    local removed=0
    local name
    while IFS= read -r name; do
        [[ -z "${name}" ]] && continue
        python3 "${merge_script}" "${config_file}" --remove "${name}" >/dev/null 2>&1 && removed=$((removed + 1))
    done <<< "${stale_names}"

    if [[ ${removed} -gt 0 ]]; then
        _log "removed ${removed} stale external module config entry/entries"
    fi
}

# Remove vendor clones that are no longer referenced by any url entry in the
# config (e.g. stale clones of modules whose config entry was pruned).
# Args:
#   $1  modules_dir    — the vendor directory
#   $2  config_file    — .devbot.global.jsonc
_prune_stale_vendor_clones() {
    local modules_dir="$1"
    local config_file="$2"

    local shared_dir
    shared_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../_shared" && pwd)"

    local referenced=""
    local url
    while IFS= read -r url; do
        [[ -z "${url}" ]] && continue
        referenced+="$(_derive_vendor_path "${url}")"$'\n'
    done < <(python3 -c "
import json, sys
sys.path.insert(0, '${shared_dir}')
from read_jsonc import load_jsonc
d = load_jsonc('${config_file}')
for e in d.get('external_modules', {}).values():
    if isinstance(e, dict) and e.get('url'):
        print(e['url'])
" 2>/dev/null || true)

    local removed=0
    local org_dir repo_dir rel
    for org_dir in "${modules_dir}"/*/; do
        [[ -d "${org_dir}" ]] || continue
        for repo_dir in "${org_dir}"*/; do
            [[ -d "${repo_dir}.git" ]] || continue
            rel="$(basename "${org_dir}")/$(basename "${repo_dir}")"
            if ! echo "${referenced}" | grep -Fxq "${rel}"; then
                rm -rf "${repo_dir}"
                _log "removed stale vendor clone: vendor/${rel}"
                removed=$((removed + 1))
            fi
        done
    done

    if [[ ${removed} -gt 0 ]]; then
        _ok "${removed} stale vendor clone(s) removed"
    fi
}

# Clone or update a single git-sourced external module.
# Args:
#   $1  name        — module display name
#   $2  url         — git clone URL
#   $3  dest        — target directory (e.g., vendor/github.com/org/repo)
#   $4  paths_json  — JSON string of paths for README cleanup
# Returns: 0 on success, 1 on failure
_install_one_module() {
    local name="$1"
    local url="$2"
    local dest="$3"
    local paths_json="$4"

    if [[ -d "${dest}/.git" ]]; then
        _info "Updating ${name} ..."
        if (cd "${dest}" && git fetch --depth 1 origin +refs/heads/*:refs/remotes/origin/* && \
            git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)) >/dev/null 2>&1; then
            _ok "${name} updated"
        else
            _warn "Failed to update ${name}"
            return 1
        fi
    else
        _info "Installing ${name} ..."
        mkdir -p "$(dirname "${dest}")"
        if git clone --depth 1 "${url}" "${dest}" >/dev/null 2>&1; then
            _ok "${name} installed"
        else
            _warn "Failed to clone ${name}"
            return 1
        fi
    fi

    _remove_readme_from_paths "${dest}" "${paths_json}"
    return 0
}
