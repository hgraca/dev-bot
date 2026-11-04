#!/usr/bin/env bash
# src/tools/external-modules/functions.sh
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate,
# plus module-local helpers.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Derive a vendor directory path (<owner>/<repo>) from a git URL. The host and
# any credentials are dropped, so every spelling of one repository maps to the
# same checkout:
#   https://github.com/org/repo.git  →  org/repo
#   ssh://git@github.com/org/repo    →  org/repo
#   git@github.com:org/repo.git      →  org/repo
#   file:///srv/remotes/org/repo    →  srv/remotes/org/repo
_derive_vendor_path() {
    local url="${1%/}"
    url="${url%.git}"
    local path_part

    case "${url}" in
        *://*)
            path_part="${url#*://}" # [userinfo@]host/path
            path_part="${path_part#*@}" # drop credentials
            path_part="${path_part#*/}" # drop the host
            ;;
        *:*)
            path_part="${url#*:}" # scp form host:path — the host is gone already
            ;;
        *)
            path_part="${url#/}"
            ;;
    esac

    echo "${path_part}"
}

# Derive the vendor-relative path for a URL, refusing anything that would
# escape the managed vendor root: an absolute path, or a `..` component
# (`file:///tmp/../../outside` derives `tmp/../../outside` and would write
# outside vendor/). A rejected URL is the caller's failure to report.
# Args: url
_derived_vendor_path() {
    local rel="$1"
    rel="$(_derive_vendor_path "$1")" || return 1
    [[ -n "${rel}" ]] || return 1
    [[ "${rel}" != /* ]] || return 1
    case "/${rel}/" in
        */../*) return 1 ;;
    esac
    printf '%s' "${rel}"
}

# Are any mirror entries missing? Checks the configured `paths` links AND the
# lifecycle-script links `_setup_external_module_storage` creates for scripts
# that exist in the checkout — a module with no configured paths still has
# those, and a deleted one under an intact root must count as unfinished work.
# One python call for every entry.
# Args: dev_bot_root probe_blob — `name<US>src_dir<US>paths_json` per line
# Returns 0 when something is missing.
_external_module_mirror_incomplete() {
    local dev_bot_root="$1"
    local probe="$2"

    LIFECYCLE="functions.sh pre.sh install.sh update.sh up.sh down.sh init.sh reset.sh uninstall.sh" \
        DEV_BOT_ROOT="${dev_bot_root}" PROBE="${probe}" python3 - <<'PY'
import json
import os
import sys

root = os.environ["DEV_BOT_ROOT"]
storage = os.path.join(root, "storage", "external-agentic-modules")
lifecycle = os.environ["LIFECYCLE"].split()


def link_ok(link_path, target):
    """The rendered link exists, points at this entry's source, and the source
    is still there. A regular file, a link elsewhere, or a dangling link is not
    this mirror."""
    if not os.path.islink(link_path):
        return False
    if not os.path.exists(link_path):
        return False
    try:
        current = os.readlink(link_path)
    except OSError:
        return False
    if not os.path.isabs(current):
        current = os.path.join(os.path.dirname(link_path), current)
    return os.path.normpath(current) == os.path.normpath(target)


missing = []
for line in os.environ["PROBE"].splitlines():
    if not line:
        continue
    name, src_dir, paths_json = line.split("\x1f")
    base = os.path.join(storage, name)

    # A malformed map cannot be certified complete: report it as incomplete so
    # the render path runs and reports the failure instead of stamping.
    try:
        configured = json.loads(paths_json)
    except ValueError:
        sys.exit(0)  # cannot certify complete; the render path reports it
    if not isinstance(configured, dict):
        sys.exit(0)

    for path_type, value in configured.items():
        dest_dir = os.path.join(base, path_type)
        if isinstance(value, str):
            if not link_ok(dest_dir, os.path.join(src_dir, value)):
                missing.append(f"{name}/{path_type}")
        elif isinstance(value, dict):
            for src_file, dest_rel in value.items():
                if not link_ok(os.path.join(dest_dir, dest_rel), os.path.join(src_dir, src_file)):
                    missing.append(f"{name}/{path_type}/{dest_rel}")
        else:
            missing.append(f"{name}/{path_type}/<unsupported value>")

    for script in lifecycle:
        if not os.path.isfile(os.path.join(src_dir, script)):
            continue
        if not link_ok(os.path.join(base, script), os.path.join(src_dir, script)):
            missing.append(f"{name}/{script}")

for entry in missing:
    print(entry)
# 0 = something is missing (the doc contract), 1 = complete.
sys.exit(0 if missing else 1)
PY
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
# Creates storage/external-agentic-modules/<name>/ with:
#   - Directory symlinks for string-valued paths (e.g. "skills" -> "skills")
#   - File symlinks for object-valued paths (e.g. {"CLAUDE.md": "bootstrap/..."})
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

    if ! _external_module_name_ok "${name}"; then
        _warn "invalid module name — refusing to mirror: ${name}"
        return 1
    fi

    local storage_base="${dev_bot_root}/storage/external-agentic-modules/${name}"

    _step "${name}: setting up storage structure..."

    python3 -c "
import json, os, sys, shutil

src_dir = sys.argv[1]
paths = json.loads(sys.argv[2])
storage_base = sys.argv[3]
name = sys.argv[4]

# A lifecycle-only module (no configured paths) still needs its root: the
# lifecycle symlinks below are created directly inside it.
os.makedirs(storage_base, exist_ok=True)

expected_dirs = set()
expected_files = set()

if not isinstance(paths, dict):
    print(f'  \u2717  {name} \u2014 invalid paths config (expected an object)')
    sys.exit(1)

missing_sources = []
unrepairable = []
unrepairable_paths = set()


def safe_rel(rel):
    # Repo-relative and confined: not absolute, no parent component.
    if not isinstance(rel, str) or not rel or rel.startswith('/'):
        return False
    return '..' not in rel.split('/')


for path_type, value in paths.items():
    # Defence in depth: install/update validate this first, but init and the
    # start path also reach the renderer directly.
    if not safe_rel(path_type):
        print(f'  \u26a0\u26a0  {name} \u2014 unsafe path key: {path_type}')
        unrepairable.append(f'{path_type}')
        continue

    dest_dir = os.path.join(storage_base, path_type)
    expected_dirs.add(dest_dir)

    if isinstance(value, str):
        source = os.path.join(src_dir, value)
        if not safe_rel(value):
            print(f'  \u26a0\u26a0  {name}/{path_type} \u2014 unsafe source path: {value}')
            missing_sources.append(f'{path_type}={value}')
            continue
        if not os.path.isdir(source):
            print(f'  \u26a0  {name}/{path_type} \u2014 source dir not found: {source}')
            missing_sources.append(f'{path_type}={value}')
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
            unrepairable.append(f'{path_type}')
            unrepairable_paths.add(dest_dir)
        else:
            os.makedirs(os.path.dirname(dest_dir), exist_ok=True)
            os.symlink(source, dest_dir)
            print(f'  -  {name}/{path_type} \u2192 {source}')

    elif isinstance(value, dict):
        for src_file, dest_rel_path in value.items():
            if not safe_rel(src_file) or not safe_rel(dest_rel_path):
                print(f'  \u26a0\u26a0  {name}/{path_type} \u2014 unsafe mapping: {src_file} -> {dest_rel_path}')
                unrepairable.append(f'{path_type}')
                continue
            source_file = os.path.join(src_dir, src_file)
            if not os.path.exists(source_file):
                print(f'  \u26a0  {name}/{path_type}/{dest_rel_path} \u2014 source not found: {source_file}')
                missing_sources.append(f'{path_type}={src_file}')
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
                unrepairable.append(f'{path_type}/{dest_rel_path}')
                unrepairable_paths.add(dest_file)
            else:
                os.makedirs(dest_parent, exist_ok=True)
                os.symlink(source_file, dest_file)
                print(f'  -  {name}/{path_type}/{dest_rel_path} \u2192 {source_file}')
    else:
        print(f'  \u26a0\u26a0  {name}/{path_type} \u2014 unsupported value type: {type(value).__name__}')
        unrepairable.append(f'{path_type}')

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
        unrepairable.append(script)
        unrepairable_paths.add(dest_file)
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
            if any(fpath == keep or fpath.startswith(keep + os.sep) for keep in unrepairable_paths):
                continue  # a reported conflict stays put
            if fpath not in expected_files:
                os.unlink(fpath)
                print(f'  -  {name} stale file removed: {os.path.relpath(fpath, storage_base)}')
        for dname in dirs:
            dpath = os.path.join(root, dname)
            if any(dpath == keep or dpath.startswith(keep + os.sep) for keep in unrepairable_paths):
                continue  # a reported conflict stays put
            if dpath not in expected_dirs:
                try:
                    shutil.rmtree(dpath)
                    print(f'  -  {name} stale dir removed: {os.path.relpath(dpath, storage_base)}')
                except OSError:
                    pass

# A configured path with no source is a broken mirror, not a note: the caller
# must not stamp the check complete.
if missing_sources or unrepairable:
    for entry in missing_sources + unrepairable:
        print(f'  \u2717  {name}/{entry}')
    sys.exit(1)
" "$src_dir" "$paths_json" "$storage_base" "$name" 2>&1
}

# The watchdog's cap in seconds. DEV_BOT_FETCH_TIMEOUT is operator input, so a
# non-numeric, zero or negative value must not disarm the timer (a bare `sleep
# abc` exits at once, leaving the stalled call unbounded) — it falls back to the
# documented default instead.
_external_module_fetch_timeout() {
    local cap="${DEV_BOT_FETCH_TIMEOUT:-20}"
    if [[ ! "${cap}" =~ ^[0-9]+$ ]] || [[ "${cap}" -le 0 ]]; then
        cap=20
    fi
    echo "${cap}"
}

# Strip credentials from a URL before it reaches a message: config URLs can
# carry tokens (https://user:token@host/repo), and warnings end up in logs.
# Args: url
_redact_url() {
    local url="$1"
    if [[ "${url}" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@]*@(.*)$ ]]; then
        url="${BASH_REMATCH[1]}***@${BASH_REMATCH[2]}"
    fi
    echo "${url}"
}

# Run a command under a portable watchdog. GNU `timeout` is absent on macOS,
# and a start must never hang on a stalled network call.
# Args: cap_seconds command [args...]
# Returns: the command's status, or 124 when the cap elapsed.
_external_module_with_timeout() {
    local cap="$1"
    shift

    # The command runs in its OWN process group (job control), so the tree —
    # git and the transport it spawns — can be signalled at once. Signalling
    # only the direct child races: git can exit on TERM first, reparenting its
    # ssh transport, which then survives the pkill and keeps a caller's pipe
    # open — a start that hangs past its own timeout.
    set -m
    # 200>&-: do not leak the caller's flock descriptor into the child. An
    # inherited open file description shares the lock, so a survivor would keep
    # a caller's lock held.
    "$@" 200>&- &
    local pid=$!
    set +m

    # A timer, not a poll loop: the check runs on every start, and a 1s poll
    # tick per git call would add seconds of dead time to a warm start. TERM at
    # the cap, KILL two seconds later, both to the whole group. `fired` tells
    # the caller the escalation is in flight, so it waits for the KILL instead
    # of returning while a TERM-ignoring transport still holds the pipe.
    # Silenced so the timer cannot hold open a command-substitution pipe.
    # The timer likewise runs in its own process group, so the fast-path
    # cleanup can kill it AND its `sleep` child: killing the subshell alone
    # reparents that child, which then sleeps out the full cap after every
    # warm call and accumulates one orphan per network call per start.
    local fired
    fired="$(mktemp "${TMPDIR:-/tmp}/devbot-fetch.XXXXXX")"
    set -m
    (
        sleep "${cap}"
        echo fired > "${fired}"
        kill -TERM -- "-${pid}" 2>/dev/null || true
        sleep 2
        kill -KILL -- "-${pid}" 2>/dev/null || true
    ) 200>&- >/dev/null 2>&1 &
    local watchdog=$!
    set +m

    local rc=0
    wait "${pid}" || rc=$?
    # The leader exiting does not mean its group is empty: a transport can
    # outlive git. Reap any survivor before returning — one holding a caller's
    # pipe would block that caller despite the command being "done", and one
    # that ignores TERM needs the same KILL escalation the timer has.
    kill -TERM -- "-${pid}" 2>/dev/null || true
    if kill -0 -- "-${pid}" 2>/dev/null; then
        sleep 1
        kill -KILL -- "-${pid}" 2>/dev/null || true
    fi
    local timed_out=0
    if [[ -s "${fired}" ]]; then
        timed_out=1
        # The KILL escalation must finish before returning: a transport that
        # ignores TERM would otherwise keep a caller's pipe (and the start) open.
        wait "${watchdog}" 2>/dev/null || true
    else
        # The whole timer group, not just its subshell: see above.
        kill -TERM -- "-${watchdog}" 2>/dev/null || true
        wait "${watchdog}" 2>/dev/null || true
    fi
    rm -f "${fired}"

    # The deadline fired: report a timeout regardless of how the command
    # happened to exit — a command that traps TERM and exits 0 must not read
    # as a completed call.
    [[ ${timed_out} -eq 1 ]] && return 124
    return "${rc}"
}

# Run a git network command non-interactively and under the fetch watchdog:
# no credential prompt, and an SSH remote that cannot ask for a passphrase or a
# host-key confirmation (BatchMode) or hang on connect. A caller-supplied
# GIT_SSH_COMMAND wins.
# Args: cap_seconds git-args...
_external_module_git_network() {
    local cap="$1"
    shift

    _external_module_with_timeout "${cap}" \
        env GIT_TERMINAL_PROMPT=0 \
        GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=${cap}}" \
        "$@"
}

# ── Check interval ─────────────────────────────────────────────────────────
# One stamp per install records the last COMPLETE check (every destination
# comparable), so a warm start inside the interval does no network work at all.
# A check that could not reach a remote is not stamped, so an offline start
# retries next time instead of going quiet for a day.

# Stamp path for a dev-bot root. Args: dev_bot_root
_external_module_stamp_file() {
    echo "$1/storage/run/external-modules.checked"
}

# Seconds between checks: DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL (validated),
# default 24h. 0 means check on every start.
_check_interval() {
    local interval="${DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL:-86400}"
    if [[ ! "${interval}" =~ ^[0-9]+$ ]]; then
        interval=86400
    fi
    echo "${interval}"
}

# Seconds as a short human string (45s, 12m, 3h). Args: seconds
_seconds_ago() {
    local secs="$1"
    if [[ "${secs}" -lt 60 ]]; then
        echo "${secs}s"
    elif [[ "${secs}" -lt 3600 ]]; then
        echo "$((secs / 60))m"
    else
        echo "$((secs / 3600))h"
    fi
}

# Is the last check still inside the interval — and, when a fingerprint is
# given, was it made against this same configuration? A module added or its
# URL/paths edited since must be processed regardless of the interval.
# Args: stamp_file interval [config_fingerprint]
_check_is_fresh() {
    local stamp_file="$1"
    local interval="$2"
    local fingerprint="${3:-}"
    local last now

    [[ "${interval}" -gt 0 ]] || return 1
    [[ -f "${stamp_file}" ]] || return 1

    last="$(cat "${stamp_file}" 2>/dev/null || true)"
    [[ "${last}" =~ ^[0-9]+$ ]] || return 1

    if [[ -n "${fingerprint}" ]]; then
        [[ "$(cat "${stamp_file}.entries" 2>/dev/null || true)" == "${fingerprint}" ]] || return 1
    fi

    now="$(date +%s)"
    [[ $((now - last)) -lt "${interval}" ]]
}

# Fingerprint of the configured entry set, so a stamp can tell "nothing changed
# since the last check" from "a module was added or its URL/paths edited".
# Args: entries blob
_external_module_fingerprint() {
    printf '%s' "$1" |
        python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())' 2>/dev/null || true
}

# Record a complete check, and the configuration it covered.
# Args: stamp_file [config_fingerprint]
_stamp_check() {
    local stamp_file="$1"
    local fingerprint="${2:-}"
    mkdir -p "$(dirname "${stamp_file}")" 2>/dev/null || true
    date +%s > "${stamp_file}" 2>/dev/null || true
    if [[ -n "${fingerprint}" ]]; then
        printf '%s\n' "${fingerprint}" > "${stamp_file}.entries" 2>/dev/null || true
    fi
}

# Normalize a git remote URL so protocol and host spellings of one repository
# compare equal: git@host:org/repo, ssh://git@host/org/repo and
# https://host/org/repo (with or without a .git suffix) all become
# https://host/org/repo.
# Args: url
_normalize_remote_url() {
    local url="${1%/}"
    url="${url%.git}"

    # Drop userinfo before comparing: a rotated token in a credentialed HTTPS
    # URL must not make a valid checkout look like a different repository.
    # (The scp form `git@host:org/repo` has no scheme, so it is untouched here
    # and rewritten below.)
    if [[ "${url}" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@]*@(.*)$ ]]; then
        url="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    fi

    case "${url}" in
        git@*:*/*)
            local rest="${url#git@}"
            url="https://${rest%%:*}/${rest#*:}"
            ;;
        ssh://git@*) url="https://${url#ssh://git@}" ;;
        ssh://*) url="https://${url#ssh://}" ;;
        git://*) url="https://${url#git://}" ;;
    esac

    echo "${url}"
}

# Wire one external module into the project's devbot dir
# (.agents/<type>/<name>), harness-agnostic. Idempotent — repairs a wrong link
# and leaves a correct one alone.
#
# Reads PROJECT_DIR from the caller's scope (init.sh sets it from its argv).
# Args:
#   $1  name      — module name from config
#   $2  src_dir   — vendor directory (or local path) for the module
#   $3  paths_json — JSON string of the paths map from config
_wire_one_module() {
  local name="$1"
  local src_dir="$2"
  local paths_json="$3"

  if ! _external_module_name_ok "${name}"; then
    _warn "invalid module name — refusing to link it into the project: ${name}"
    return 1
  fi
  # Keys become directories under the project's devbot dir: validate the map
  # here too, because init wires before the storage renderer sees it.
  if ! _external_module_paths_ok "${paths_json}"; then
    _warn "${name}: invalid paths config — refusing to link it into the project"
    return 1
  fi

  local paths_map
  paths_map="$(python3 -c '
import json, sys
paths = json.loads(sys.argv[1])
for k, v in paths.items():
    print(f"{k}={v}")
' "${paths_json}" 2>/dev/null || true)"

  [[ -n "${paths_map}" ]] || return 0

  # External artifacts go into the DEVBOT DIR (e.g. .agents/), like the
  # internal artifacts — NOT .opencode/ — so both harnesses get them through
  # the harness delegation (.claude/* → .agents/*) and opencode's direct
  # .agents discovery. Each external module is its own namespace under the
  # type dir (.agents/skills/addyosmani, .agents/agents/addyosmani, ...).
  local devbot_dir
  devbot_dir="$(_devbot_get_project_dir "${PROJECT_DIR}")"

  while IFS='=' read -r type rel_path; do
    [[ -z "${type}" || -z "${rel_path}" ]] && continue
    [[ ! -d "${src_dir}/${rel_path}" ]] && continue

    local type_src="${src_dir}/${rel_path}"
    local target_dir="${PROJECT_DIR}/${devbot_dir}/${type}"
    local link_path="${target_dir}/${name}"

    mkdir -p "${target_dir}"

    if [[ -L "${link_path}" ]]; then
      local current
      current="$(readlink "${link_path}")"
      if [[ "${current}" == "${type_src}" ]]; then
        _skip "${name} → ${devbot_dir}/${type}/${name} (already correct)"
      else
        rm "${link_path}"
        ln -s "${type_src}" "${link_path}"
        _log "${name} → ${devbot_dir}/${type}/${name} repaired"
      fi
    elif [[ -e "${link_path}" ]]; then
      _warn "${link_path} exists but is not a symlink — skipping"
    else
      ln -s "${type_src}" "${link_path}"
      _log "${name} → ${devbot_dir}/${type}/${name} linked"
    fi
  done <<< "${paths_map}"
}

# List the configured paths that are absent from a COMMIT — not from the
# working tree. Validating the fetched commit is what lets an update be
# cancelled before `reset --hard`: the legacy checkout, and every symlink into
# it, stays exactly as it was.
#
# A string path is a directory (or symlink to one) in the repository; an object
# value names individual files. Existence is all that is required — the mirror
# only needs to be able to link it.
# Args: dir ref paths_json
# Prints one `<type>=<repo-path>` line per missing path; empty when all exist.
_external_module_missing_paths() {
    local dir="$1"
    local ref="$2"
    local paths_json="$3"

    python3 - "${dir}" "${ref}" "${paths_json}" <<'PY'
import json
import os
import subprocess
import sys

repo, ref, paths = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])

TREE = "040000"
SYMLINK = "120000"


def mode(rel_path):
    """Git mode of <path> in <ref>: '' when absent. Existence alone is not
    enough — replacing a configured directory with a file must not pass."""
    out = subprocess.run(
        ["git", "-C", repo, "ls-tree", ref, "--", rel_path],
        capture_output=True,
        text=True,
    )
    line = out.stdout.strip().splitlines()
    if out.returncode != 0 or not line:
        return ""
    return line[0].split()[0]


def blob(rel_path):
    out = subprocess.run(
        ["git", "-C", repo, "cat-file", "blob", f"{ref}:{rel_path}"],
        capture_output=True,
        text=True,
    )
    return out.stdout.strip() if out.returncode == 0 else ""


def directory_mode(rel_path):
    """Mode of a path once symlinks are resolved inside the commit. A symlink
    to a FILE is not a directory source, whatever it is named."""
    current = rel_path
    for _ in range(5):
        entry_mode = mode(current)
        if entry_mode != SYMLINK:
            return entry_mode
        target = blob(current)
        if not target or target.startswith("/"):
            return ""
        current = os.path.normpath(os.path.join(os.path.dirname(current), target))
        if current == ".." or current.startswith("../"):
            return ""
    return ""


missing = []
for path_type, value in paths.items():
    if isinstance(value, str):
        # Must resolve to a directory in the commit: a symlink to a file is not.
        if directory_mode(value) != TREE:
            missing.append(f"{path_type}={value}")
    elif isinstance(value, dict):
        # A file mapping needs a blob (a symlink is a blob too), never a tree.
        for src_file in value:
            entry_mode = mode(src_file)
            if not entry_mode or entry_mode == TREE:
                missing.append(f"{path_type}={src_file}")

for entry in missing:
    print(entry)
PY
}

# Validate every paths map a destination is configured with: the module's own
# map plus any aliases sharing the same clone (the react umbrella maps four
# different subdirectories of one repository). Prints one `<type>=<path>` line
# per missing path, from any of them.
# Args: dir ref paths_json [alias_paths — newline-separated maps]
_external_module_missing_any() {
    local dir="$1"
    local ref="$2"
    local paths_json="$3"
    local alias_paths="${4:-}"
    local missing more pj

    missing="$(_external_module_missing_paths "${dir}" "${ref}" "${paths_json}")"
    while IFS= read -r pj; do
        [[ -z "${pj}" ]] && continue
        [[ "${pj}" == "${paths_json}" ]] && continue
        more="$(_external_module_missing_paths "${dir}" "${ref}" "${pj}")"
        [[ -n "${more}" ]] && missing+="${more}"$'\n'
    done <<< "${alias_paths}"

    printf '%s' "${missing}"
}

# Does the checkout at <dest> come from <url>? Silent — the cheap freshness
# scan uses it; _checkout_belongs_to wraps it with the user-facing warnings.
# Args: dest url
_checkout_origin_matches() {
  local dest="$1"
  local url="$2"
  local origin

  origin="$(git -C "${dest}" config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "${origin}" ]] || return 1
  [[ "$(_normalize_remote_url "${origin}")" == "$(_normalize_remote_url "${url}")" ]]
}

# Is the checkout at <dest> a clone of <url>? Vendor paths drop the host, so an
# entry whose URL changed can land on a retained clone of a different repo.
# Comparing origin against the configured URL (protocol-normalized) is what
# stops the wrong code from being mirrored under this entry's name.
# Args: name dest url
_checkout_belongs_to() {
  local name="$1"
  local dest="$2"
  local url="$3"
  local origin

  origin="$(git -C "${dest}" config --get remote.origin.url 2>/dev/null || true)"

  if [[ -z "${origin}" ]]; then
    # No origin: an unknown repository. Provisioning it would mirror local
    # code of unknown provenance under this entry's name.
    _warn "${name}: ${dest} has no origin remote — skipping (remove that checkout to reinstall it)"
    return 1
  fi

  if ! _checkout_origin_matches "${dest}" "${url}"; then
    _warn "${name}: ${dest} belongs to $(_redact_url "${origin}"), not $(_redact_url "${url}") — skipping; remove that checkout to switch repos"
    return 1
  fi
  return 0
}

# Move a checkout from the legacy scp-style location into the canonical one.
# `git@host:owner/repo` used to derive a bare `vendor/repo`; it now derives
# `vendor/owner/repo`, so an existing install must be moved instead of cloned
# a second time. The origin check makes this a no-op for anything else.
# Args: modules_dir url dest
_external_module_migrate_legacy_checkout() {
    local modules_dir="$1"
    local url="$2"
    local dest="$3"
    local legacy

    [[ -d "${dest}/.git" ]] && return 0

    legacy="${modules_dir}/$(basename "${dest}")"
    [[ "${legacy}" != "${dest}" ]] || return 0
    [[ -d "${legacy}/.git" ]] || return 0
    _checkout_origin_matches "${legacy}" "${url}" || return 0

    mkdir -p "$(dirname "${dest}")"
    if _external_module_install_dir "${legacy}" "${dest}" && [[ -d "${dest}/.git" ]]; then
        _info "migrated legacy checkout ${legacy} → ${dest}"
    fi
    return 0
}

# A module name becomes a path component under the storage mirror and in a
# project's .agents links, so it must be exactly one component: a name like
# `../x` would otherwise write outside the managed tree.
# Args: name
_external_module_name_ok() {
    local name="$1"
    [[ -n "${name}" ]] || return 1
    [[ "${name}" != "." && "${name}" != ".." ]] || return 1
    [[ "${name}" != */* ]] || return 1
    # Control characters would split the newline/0x1f entry transport, letting
    # one crafted key smuggle a different URL or path into another entry.
    [[ ! "${name}" =~ [[:cntrl:]] ]] || return 1
    return 0
}

# Is a `paths` map well-formed? An object whose values are strings (directory
# paths) or objects (file mappings). Args: paths_json
_external_module_paths_ok() {
    python3 -c '
import json
import sys

try:
    paths = json.loads(sys.argv[1])
except ValueError:
    sys.exit(1)

def safe_rel(rel):
    """A repo-relative path that cannot escape its base: no absolute path, no
    `..` component (it becomes a symlink destination under the mirror)."""
    if not isinstance(rel, str) or not rel:
        return False
    if rel.startswith("/"):
        return False
    return ".." not in rel.split("/")


if not isinstance(paths, dict):
    sys.exit(1)
for path_type, value in paths.items():
    if not safe_rel(path_type):
        sys.exit(1)
    if not isinstance(value, (str, dict)):
        sys.exit(1)
    if isinstance(value, str):
        if not safe_rel(value):
            sys.exit(1)
    elif not all(safe_rel(k) and safe_rel(v) for k, v in value.items()):
        sys.exit(1)
' "$1" 2>/dev/null
}

# Move a finished scratch clone into place without replacing anything that
# appeared meanwhile. `mv` treats an existing directory as a container and
# nests the clone inside it; rename(2) fails on a non-empty directory, so two
# concurrent starts cannot both "install" and leave `dest/.git` absent.
# Args: src_dir dest
_external_module_install_dir() {
    python3 -c '
import os
import sys

try:
    os.rename(sys.argv[1], sys.argv[2])
except OSError:
    sys.exit(1)
' "$1" "$2" 2>/dev/null
}

# Sparse checkout: a module is consumed only through its declared paths.
# `set --no-cone` needs git 2.35; older gits keep the full tree.
_external_module_sparse_supported() {
    git version 2>/dev/null | awk '{
        split($3, v, ".")
        if (v[1] > 2 || (v[1] == 2 && v[2] >= 35)) exit 0
        exit 1
    }'
}

# Pathspecs a set of paths maps declare: configured directories, file-map source
# files, and the root lifecycle scripts. Args: paths-map JSON strings.
_external_module_sparse_patterns() {
    python3 - "$@" <<'PY'
import json, sys

seen = []
for raw in sys.argv[1:]:
    try:
        paths = json.loads(raw)
    except Exception:
        continue
    if not isinstance(paths, dict):
        continue
    for value in paths.values():
        if isinstance(value, str):
            sources = [value]
        elif isinstance(value, dict):
            sources = list(value)
        else:
            sources = []
        for source in sources:
            if source and source not in seen:
                seen.append(source)

for name in (
    "functions.sh",
    "pre.sh",
    "install.sh",
    "update.sh",
    "up.sh",
    "down.sh",
    "init.sh",
    "reset.sh",
    "uninstall.sh",
):
    if name not in seen:
        seen.append(name)

# Anchored, so a declared name cannot also match a same-named nested path.
print("\n".join("/" + p.lstrip("/") for p in seen))
PY
}

# Restrict <dir> to the paths it is linked from. Args: dir, then paths-map JSON
# strings. Falls back to a full checkout, so callers never lose a declared path.
_external_module_sparse_set() {
    local dir="$1"
    shift

    _external_module_sparse_supported || return 0

    local patterns_out
    patterns_out="$(_external_module_sparse_patterns "$@" 2>/dev/null || true)"
    [[ -n "${patterns_out}" ]] || return 0

    local -a patterns=()
    local line
    while IFS= read -r line; do
        [[ -n "${line}" ]] && patterns+=("${line}")
    done <<< "${patterns_out}"

    local cap
    cap="$(_external_module_fetch_timeout)"

    # Guarded like every other git call: a partial clone fetches blobs here.
    if ! _external_module_git_network "${cap}" git -C "${dir}" sparse-checkout set --no-cone "${patterns[@]}" >/dev/null 2>&1; then
        _warn "sparse checkout failed — falling back to the full tree in ${dir}"
        _external_module_git_network "${cap}" git -C "${dir}" sparse-checkout disable >/dev/null 2>&1 || true
    fi
}

# Clone or update a single git-sourced external module.
# Args:
#   $1  name        — module display name
#   $2  url         — git clone URL
#   $3  dest        — target directory (e.g., vendor/github.com/org/repo)
#   $4  paths_json  — JSON string of paths for README cleanup
#   $5  alias_paths — optional newline-separated paths maps of other entries
#                     sharing this clone; validated alongside $4
# Returns: 0 on success, 1 on failure
_install_one_module() {
    local name="$1"
    local url="$2"
    local dest="$3"
    local paths_json="$4"
    local alias_paths="${5:-}"

    if ! _external_module_name_ok "${name}"; then
        _error "${name}: invalid module name — names must be a single path component"
        return 1
    fi

    # The paths maps drive validation and rendering; a malformed one (not an
    # object of strings/objects) must stop the update before the reset, not
    # fail later in Python where a raised error would read as "no paths".
    local check_map
    while IFS= read -r check_map; do
        [[ -n "${check_map}" ]] || continue
        if ! _external_module_paths_ok "${check_map}"; then
            _error "${name}: invalid paths config (expected an object of paths) — refusing to update"
            return 1
        fi
    done <<< "${paths_json}"$'\n'"${alias_paths}"

    # Maps whose paths define the sparse checkout — this entry plus any alias
    # sharing the same clone.
    local -a sparse_maps=("${paths_json}")
    local alias_map
    while IFS= read -r alias_map; do
        [[ -n "${alias_map}" ]] && sparse_maps+=("${alias_map}")
    done <<< "${alias_paths}"

    local cap
    cap="$(_external_module_fetch_timeout)"

    if [[ -d "${dest}/.git" ]]; then
        # Never rewrite a retained checkout that belongs to another repository:
        # the vendor path drops the host, so a changed URL can land on it.
        if ! _checkout_belongs_to "${name}" "${dest}" "${url}"; then
            return 1
        fi
        _info "Updating ${name} ..."
        local branch
        branch="$(git -C "${dest}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        if [[ -z "${branch}" || "${branch}" == "HEAD" ]]; then
            _warn "Failed to update ${name}: checkout is not on a branch"
            return 1
        fi
        # Fetch from the CONFIGURED url, not the clone's origin: the update
        # check compares against the configured url, so fetching elsewhere
        # would report "update available" then fail on every start.
        if ! _external_module_git_network "${cap}" git -C "${dest}" fetch --depth 1 "${url}" \
            "+refs/heads/*:refs/remotes/origin/*" >/dev/null 2>&1; then
            _warn "Failed to update ${name}"
            return 1
        fi

        # Validate the incoming commit BEFORE the working tree moves. A config
        # path that no longer exists upstream cancels this update: the legacy
        # checkout — and every symlink into it — is left in place, so nothing
        # breaks and nothing is lost.
        local missing
        missing="$(_external_module_missing_any "${dest}" "origin/${branch}" "${paths_json}" "${alias_paths}")"
        if [[ -n "${missing}" ]]; then
            local entry
            while IFS= read -r entry; do
                [[ -z "${entry}" ]] && continue
                _error "${name}: configured path '${entry}' is missing in the incoming version"
            done <<< "${missing}"
            _error "${name}: update cancelled — keeping the current checkout"
            return 1
        fi

        # Guarded: a partial clone can fetch the reset's blobs here.
        if ! _external_module_git_network "${cap}" git -C "${dest}" reset --hard "origin/${branch}" >/dev/null 2>&1; then
            _warn "Failed to update ${name}"
            return 1
        fi
        # Applied on every update, so a checkout installed before sparse
        # support existed is narrowed once and stays that way.
        _external_module_sparse_set "${dest}" "${sparse_maps[@]}"
        _ok "${name} updated"
    else
        _info "Installing ${name} ..."
        local parent tmp_dest
        parent="$(dirname "${dest}")"
        mkdir -p "${parent}"
        if [[ -e "${dest}" ]]; then
            _warn "Failed to clone ${name}: ${dest} exists but is not a git checkout"
            return 1
        fi
        # Clone beside the destination and rename on success: a watchdog kill
        # mid-clone leaves a partial directory behind, and that would both
        # block a retry and masquerade as a checkout on the next start.
        # Name-free template: the module name is config input and must never
        # shape a filesystem path on its own.
        tmp_dest="$(mktemp -d "${parent}/.clone.XXXXXX")"
        local -a clone_flags=(--depth 1)
        if _external_module_sparse_supported; then
            clone_flags+=(--filter=blob:none --sparse)
        fi
        if _external_module_git_network "${cap}" git clone "${clone_flags[@]}" "${url}" "${tmp_dest}" >/dev/null 2>&1; then
            # Same validation for a first install: there is no legacy version to
            # keep, so a repository without the configured paths is refused.
            local missing
            missing="$(_external_module_missing_any "${tmp_dest}" "HEAD" "${paths_json}" "${alias_paths}")"
            if [[ -n "${missing}" ]]; then
                local entry
                while IFS= read -r entry; do
                    [[ -z "${entry}" ]] && continue
                    _error "${name}: configured path '${entry}' is missing in $(_redact_url "${url}")"
                done <<< "${missing}"
                _error "${name}: install cancelled — the repository does not provide the configured paths"
                rm -r "${tmp_dest}" 2>/dev/null || true
                return 1
            fi
            # Materialize only the declared paths; a failure here falls back to
            # the full tree inside the helper.
            _external_module_sparse_set "${tmp_dest}" "${sparse_maps[@]}"
            # Both steps are checked explicitly: this function runs as an `if`
            # condition, where `set -e` is suspended, so an unchecked failure
            # would still report a successful install with no checkout.
            # mktemp creates 700; a plain clone would inherit the umask.
            if chmod 755 "${tmp_dest}" &&
                _external_module_install_dir "${tmp_dest}" "${dest}" &&
                [[ -d "${dest}/.git" ]]; then
                _ok "${name} installed"
            else
                rm -r "${tmp_dest}" 2>/dev/null || true
                _warn "Failed to clone ${name}: could not install it at ${dest} (another start may have won)"
                return 1
            fi
        else
            rm -r "${tmp_dest}" 2>/dev/null || true
            _warn "Failed to clone ${name}"
            return 1
        fi
    fi

    _remove_readme_from_paths "${dest}" "${paths_json}"
    return 0
}

# Does a cloned module's tracked branch differ from the remote?
# `git ls-remote` advertises refs without transferring objects, so a start-up
# check stays cheap and only a module that actually diverged is fetched.
#
# Args:
#   $1  dest — module clone (must already exist)
#   $2  url  — remote to compare against
# Returns:
#   0  the remote moved — an update is available
#   1  the clone is at the remote commit — up to date
#   2  undecidable: detached HEAD, tracked branch gone upstream, or the remote
#      is unreachable. The caller warns and leaves the clone untouched.
_external_module_update_available() {
    local dest="$1"
    local url="$2"
    local branch local_sha remote_sha

    branch="$(git -C "${dest}" rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 2
    [[ -n "${branch}" && "${branch}" != "HEAD" ]] || return 2

    local_sha="$(git -C "${dest}" rev-parse HEAD 2>/dev/null)" || return 2

    remote_sha="$(_external_module_git_network "$(_external_module_fetch_timeout)" \
        git ls-remote "${url}" "refs/heads/${branch}" 2>/dev/null | cut -f1)" || return 2
    [[ -n "${remote_sha}" ]] || return 2

    # Any difference counts: ahead, behind or diverged all end in the same
    # hard reset to the remote commit.
    [[ "${remote_sha}" == "${local_sha}" ]] && return 1
    return 0
}

# Install or update every configured destination, then mirror each entry.
#
# This is the one implementation behind `devbot install`/`devbot update`
# (install.sh) and `devbot module install` (module.sh): both used to carry their
# own fetch/reset, and the unvalidated one won. Everything here goes through
# _install_one_module, so a configured path that vanished upstream cancels that
# destination's update and leaves its legacy checkout in place.
#
# Unlike the start-time check it always syncs — an explicit install/update asks
# for it, so there is no interval gate or compare-first step.
#
# Args: config_file dev_bot_root
# Returns 0 when every destination synced, 1 when any failed (a cancelled
# update, or a local module whose source directory is gone, counts as failed).
_external_module_install_all() {
    local config_file="$1"
    local dev_bot_root="$2"
    local modules_dir="${dev_bot_root}/vendor"
    local entries

    entries="$(_external_module_entries "${config_file}")"
    [[ -n "${entries}" ]] || return 0

    # ── Unique destinations; a destination is usable only when every entry
    # mapping onto it names the same repository (vendor paths drop the host).
    local plan="" seen="" index=0 failed=0
    local name url local_path paths_json dest identity
    while IFS=$'\x1f' read -r name url local_path paths_json; do
        [[ -z "${name}" ]] && continue

        if [[ "${name}" == $'\tINVALID' ]]; then
            _warn "invalid module name — names must be a single path component without control characters; skipping"
            failed=$((failed + 1))
            continue
        fi

        if ! _external_module_name_ok "${name}"; then
            _warn "${name}: invalid module name — names must be a single path component; skipping"
            failed=$((failed + 1))
            continue
        fi

        if [[ -n "${local_path}" ]]; then
            if [[ ! -d "${local_path}" ]]; then
                # Not installed, not mirrored: the contract is "every
                # destination synced", so this is a failure, not a note.
                _warn "${name}: local path not found (${local_path})"
                failed=$((failed + 1))
            else
                _skip "${name}: local module at ${local_path}"
                # Local modules have no checkout to sync, but their mirror is
                # still this script's job (as it always was).
                if ! _setup_external_module_storage "${local_path}" "${name}" "${paths_json}" "${dev_bot_root}"; then
                    _warn "${name}: mirror render failed"
                    failed=$((failed + 1))
                fi
            fi
            continue
        fi

        if [[ -z "${url}" ]]; then
            _warn "${name}: missing url and local_path — skipping"
            failed=$((failed + 1))
            continue
        fi

        local vendor_rel
        if ! vendor_rel="$(_derived_vendor_path "${url}")"; then
            _warn "${name}: URL does not map inside vendor/ — skipping ($(_redact_url "${url}"))"
            failed=$((failed + 1))
            continue
        fi
        dest="${modules_dir}/${vendor_rel}"
        identity="$(_normalize_remote_url "${url}")"

        if grep -Fq -- "${dest}"$'\x1f' <<< "${seen}"; then
            local known_identity
            known_identity="$(grep -F -- "${dest}"$'\x1f' <<< "${seen}" | head -1 | cut -d$'\x1f' -f2)"
            if [[ "${known_identity}" != "${identity}" ]]; then
                _warn "${name}: ${dest} is already used by another repository — skipping (two repos map to one vendor path)"
                failed=$((failed + 1))
            fi
            continue # an earlier entry already covers this clone
        fi
        seen+="${dest}"$'\x1f'"${identity}"$'\n'
        plan+="${dest}"$'\x1f'"${url}"$'\x1f'"${name}"$'\x1f'"${paths_json}"$'\x1f'"${index}"$'\n'
        index=$((index + 1))
    done <<< "${entries}"

    # ── Sync each destination once, under its clone lock.
    local entry_name entry_url entry_local entry_paths
    while IFS=$'\x1f' read -r dest url name paths_json index; do
        [[ -z "${dest}" ]] && continue

        # Every alias's map is validated with this destination's own, so an
        # update cannot silently drop a path another entry relies on.
        local alias_paths="" aliases=""
        while IFS=$'\x1f' read -r entry_name entry_url entry_local entry_paths; do
            [[ -z "${entry_name}" || -n "${entry_local}" ]] && continue
            [[ "$(_normalize_remote_url "${entry_url}")" == "$(_normalize_remote_url "${url}")" ]] || continue
            aliases+="${entry_name}"$'\x1f'"${entry_paths}"$'\n'
            [[ "${entry_paths}" == "${paths_json}" ]] && continue
            alias_paths+="${entry_paths}"$'\n'
        done <<< "${entries}"

        local lock_file="${dest}.lock"
        local cap="${DEV_BOT_MODULE_UPDATE_LOCK_WAIT:-120}"
        _devbot_lock_wait "${lock_file}" "${cap}" \
            "update lock held >${cap}s — continuing without it" || true

        _external_module_migrate_legacy_checkout "${modules_dir}" "${url}" "${dest}"

    if _install_one_module "${name}" "${url}" "${dest}" "${paths_json}" "${alias_paths}"; then
            local alias_name alias_paths_json
            while IFS=$'\x1f' read -r alias_name alias_paths_json; do
                [[ -z "${alias_name}" ]] && continue
                # _install_one_module pruned only the first entry's paths; a
                # co-tenant's READMEs must not be exposed through its mirror.
                _remove_readme_from_paths "${dest}" "${alias_paths_json}"
                if ! _setup_external_module_storage "${dest}" "${alias_name}" "${alias_paths_json}" "${dev_bot_root}"; then
                    _warn "${alias_name}: mirror render failed"
                    failed=$((failed + 1))
                fi
            done <<< "${aliases}"
        else
            failed=$((failed + 1))
        fi

        { exec 200>&-; } 2>/dev/null || true
    done <<< "${plan}"

    # A complete sync means the next start needs no check at all — for THIS
    # configuration (the fingerprint goes with the stamp).
    if [[ ${failed} -eq 0 ]]; then
        _stamp_check "$(_external_module_stamp_file "${dev_bot_root}")" \
            "$(_external_module_fingerprint "${entries}")"
    fi

    [[ ${failed} -eq 0 ]]
}

# Parse the configured entries into `<name><US><url><US><local_path><US><paths>`
# lines, skipping boolean enable/disable flags.
# Args: config_file
_external_module_entries() {
    local config_file="$1"

    printf '%s' "$(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${config_file}" external_modules 2>/dev/null || true)" |
        python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for name, entry in data.items():
    if not isinstance(entry, dict):
        continue  # boolean enable/disable flags are not module definitions
    # A control character in the key would split this record (or a field), so
    # emit a marker the consumer can report instead of mis-parsing the entry.
    invalid = (
        not isinstance(name, str)
        or not name
        or name in ('.', '..')
        or '/' in name
        or any(ord(c) < 32 for c in name)
    )
    if invalid:
        print('\tINVALID\x1f' + json.dumps(name)[1:-1] + '\x1f\x1f')
        continue
    url = entry.get('url', '')
    local_path = entry.get('local_path', '')
    paths = json.dumps(entry.get('paths', {}))
    print(f'{name}\x1f{url}\x1f{local_path}\x1f{paths}')
"
}
