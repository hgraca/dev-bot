#!/usr/bin/env bash
# =============================================================================
# src/_shared/migrations.sh
# Versioned config migrations for `devbot update`.
#
# A migration is a function named `migration_up-<MAJOR.MINOR.PATCH>` whose
# version is the release that introduced it, with a matching
# `migration_down-<MAJOR.MINOR.PATCH>` that reverses it. `migrate <from> <to>`
# runs every up migration in `(from, to]` ascending; a downgrade runs the down
# migrations in `(to, from]` descending. The global config path is passed to
# every function as `$1`; a migration iterates the registered projects itself.
#
# Dotted function names are legal with the `function` keyword (unquoted), and
# compgen/declare -F/dispatch all handle them. Never use the `name() {}` form.
#
# Every up must have a down: `_migration_parity` reports a missing half and
# src/_shared/tests/migrations_tests.bats fails when it does.
# =============================================================================

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export DEV_BOT_ROOT

# ── Logging (falls back when sourced without the shared library, as in tests) ──
_migration_ok() { if declare -F _ok >/dev/null; then _ok "$@"; else printf 'ok: %s\n' "$*"; fi; }
_migration_warn() { if declare -F _warn >/dev/null; then _warn "$@"; else printf 'WARN: %s\n' "$*" >&2; fi; }
_migration_skip() { if declare -F _skip >/dev/null; then _skip "$@"; else printf 'skip: %s\n' "$*"; fi; }
_migration_header() { if declare -F _header_2 >/dev/null; then _header_2 "$@"; else printf '\n== %s ==\n' "$*"; fi; }

# ── Version helpers ───────────────────────────────────────────────────────────

# _migration_valid_version <v> — dot-separated numeric segments, optionally
# prefixed with `v` (a recorded install tag keeps whatever the tag says).
_migration_valid_version() {
  [[ "${1#v}" =~ ^[0-9]+(\.[0-9]+)*$ ]]
}

# _migration_version_lt <a> <b> — true when a < b, comparing dot-separated
# numeric segments. Missing segments count as 0, so `0.1.2` == `0.1.2.0`.
# `sort -V` is deliberately avoided: macOS sort does not support it.
_migration_version_lt() {
  local a="${1#v}" b="${2#v}"
  local -a av=() bv=()
  IFS='.' read -r -a av <<< "${a}"
  IFS='.' read -r -a bv <<< "${b}"
  local i max="${#av[@]}" x y
  (( ${#bv[@]} > max )) && max="${#bv[@]}"
  for (( i = 0; i < max; i++ )); do
    x="${av[i]:-0}"
    y="${bv[i]:-0}"
    # A non-numeric segment cannot be ordered; the entry points reject it.
    if [[ ! "${x}" =~ ^[0-9]+$ || ! "${y}" =~ ^[0-9]+$ ]]; then return 1; fi
    # 10# keeps 08 from being read as an invalid octal literal.
    if (( 10#${x} < 10#${y} )); then return 0; fi
    if (( 10#${x} > 10#${y} )); then return 1; fi
  done
  return 1
}

# _migration_tools_dir — the tool directory for a run. Normally the checkout's
# src/_shared; a downgrade points it at the tools captured before the checkout,
# because the target checkout predates the down modes.
_migration_tools_dir() {
  printf '%s' "${DEV_BOT_MIGRATION_TOOLS_DIR:-${DEV_BOT_ROOT}/src/_shared}"
}

# Version list on stdin → ascending on stdout. The set is tiny, so a bash
# insertion sort is enough and keeps the comparison in one place.
_migration_sort_versions() {
  local -a input=() sorted=()
  local line value tmp i
  while IFS= read -r line; do
    if [[ -n "${line}" ]]; then input+=("${line}"); fi
  done
  for value in "${input[@]}"; do
    sorted+=("${value}")
    i="$(( ${#sorted[@]} - 1 ))"
    while (( i > 0 )) && _migration_version_lt "${sorted[i]}" "${sorted[i - 1]}"; do
      tmp="${sorted[i]}"
      sorted[i]="${sorted[i - 1]}"
      sorted[i - 1]="${tmp}"
      i="$(( i - 1 ))"
    done
  done
  if (( ${#sorted[@]} )); then printf '%s\n' "${sorted[@]}"; fi
}

# _migration_versions <up|down> — the versions that define that half.
_migration_versions() {
  local kind="$1"
  compgen -A function | sed -n "s/^migration_${kind}-//p"
}

# _migration_range <kind> <lower(exclusive)> <upper(inclusive)> <asc|desc>
_migration_range() {
  local kind="$1" lower="$2" upper="$3" direction="$4"
  local -a versions=() selected=()
  local v i
  while IFS= read -r v; do
    if [[ -n "${v}" ]]; then versions+=("${v}"); fi
  done < <(_migration_versions "${kind}" | _migration_sort_versions)

  for v in "${versions[@]}"; do
    if _migration_version_lt "${lower}" "${v}" && ! _migration_version_lt "${upper}" "${v}"; then
      selected+=("${v}")
    fi
  done

  if [[ "${direction}" == "desc" ]]; then
    for (( i = ${#selected[@]} - 1; i >= 0; i-- )); do
      printf '%s\n' "${selected[i]}"
    done
  elif (( ${#selected[@]} )); then
    printf '%s\n' "${selected[@]}"
  fi
}

# _migration_parity — print a MISSING line for every half without its pair.
_migration_parity() {
  local v missing=0
  while IFS= read -r v; do
    if [[ -n "${v}" ]] && ! declare -F "migration_down-${v}" >/dev/null; then
      printf 'MISSING: migration_down-%s\n' "${v}"
      missing=1
    fi
  done < <(_migration_versions up | _migration_sort_versions)

  while IFS= read -r v; do
    if [[ -n "${v}" ]] && ! declare -F "migration_up-${v}" >/dev/null; then
      printf 'MISSING: migration_up-%s\n' "${v}"
      missing=1
    fi
  done < <(_migration_versions down | _migration_sort_versions)

  return "${missing}"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

_migration_call() {
  local fn="$1" config="$2" output
  if ! declare -F "${fn}" >/dev/null; then
    _migration_warn "${fn} is missing — its pair is out of parity"
    return 1
  fi
  if output="$("${fn}" "${config}" 2>&1)"; then
    _migration_ok "${fn}"
  else
    _migration_warn "${fn} failed"
    if [[ -n "${output}" ]]; then printf '%s\n' "${output}" | sed 's/^/    /'; fi
    return 1
  fi
  if [[ -n "${output}" ]]; then printf '%s\n' "${output}" | sed 's/^/    /'; fi
  return 0
}

# migrate <from> <to> [global-config]
#   Runs `(from, to]` ascending. When to < from it delegates to migrate_down, so
#   the updater calls one function for an upgrade and a downgrade alike.
migrate() {
  local from="${1:-0.0.0}" to="${2:-0.0.0}" config="${3:-$(_devbot_global_config)}"
  from="${from:-0.0.0}"
  to="${to:-0.0.0}"
  if ! _migration_valid_version "${from}" || ! _migration_valid_version "${to}"; then
    _migration_warn "non-numeric version range '${from}' → '${to}' — skipping migrations"
    return 1
  fi

  if _migration_version_lt "${to}" "${from}"; then
    migrate_down "${from}" "${to}" "${config}"
    return $?
  fi
  if ! _migration_version_lt "${from}" "${to}"; then
    _migration_skip "no version change (${from})"
    return 0
  fi

  local -a versions=()
  local v
  while IFS= read -r v; do
    if [[ -n "${v}" ]]; then versions+=("${v}"); fi
  done < <(_migration_range up "${from}" "${to}" asc)

  if (( ${#versions[@]} == 0 )); then
    _migration_skip "no config migrations for ${from} → ${to}"
    return 0
  fi

  _migration_header "Config migrations ${from} → ${to}"
  local failed=0
  for v in "${versions[@]}"; do
    if ! _migration_call "migration_up-${v}" "${config}"; then
      failed=1
      break
    fi
  done
  return "${failed}"
}

# migrate_down <from> <to> [global-config] — `[to, from)` descending.
migrate_down() {
  local from="${1:-0.0.0}" to="${2:-0.0.0}" config="${3:-$(_devbot_global_config)}"
  from="${from:-0.0.0}"
  to="${to:-0.0.0}"
  if ! _migration_valid_version "${from}" || ! _migration_valid_version "${to}"; then
    _migration_warn "non-numeric version range '${from}' → '${to}' — skipping rollback"
    return 1
  fi

  local -a versions=()
  local v
  while IFS= read -r v; do
    if [[ -n "${v}" ]]; then versions+=("${v}"); fi
  done < <(_migration_range down "${to}" "${from}" desc)

  if (( ${#versions[@]} == 0 )); then
    _migration_skip "no config rollback migrations for ${from} → ${to}"
    return 0
  fi

  _migration_header "Config rollback migrations ${from} → ${to}"
  local failed=0
  for v in "${versions[@]}"; do
    if ! _migration_call "migration_down-${v}" "${config}"; then
      failed=1
      break
    fi
  done
  return "${failed}"
}

# _migration_run_phase <from> <to> <config> <migrations-source> [tools-dir]
#   Run the migration phase in a fresh shell so the migration set comes from the
#   given file — the target checkout on an upgrade, the pre-checkout capture on
#   a downgrade — not from the function table of the pre-update script.
_migration_run_phase() {
  local from="$1" to="$2" config="$3" source_file="$4" tools_dir="${5:-}"
  DEV_BOT_MIGRATION_TOOLS_DIR="${tools_dir}" \
    bash -c 'source "${DEV_BOT_ROOT}/src/_shared/functions.sh" 2>/dev/null || true; source "$1"; migrate "$2" "$3" "$4"' \
      _ "${source_file}" "${from}" "${to}" "${config}"
}

# ── Project config discovery ──────────────────────────────────────────────────

# _migration_project_dirs <global-config> — every registered project directory.
_migration_project_dirs() {
  local global_config="$1"
  python3 - "${global_config}" "$(_migration_tools_dir)" <<'PY'
import json
import os
import subprocess
import sys

reader = os.path.join(sys.argv[2], "read_jsonc.py")
config = sys.argv[1]
try:
    raw = subprocess.check_output(["python3", reader, config, "projects"], text=True)
    projects = json.loads(raw)
except Exception:
    projects = []
if not isinstance(projects, list):
    projects = []
base = os.path.dirname(os.path.abspath(config))
for project in projects:
    if isinstance(project, str) and project:
        print(os.path.abspath(os.path.join(base, project)))
PY
}

# _migration_config_paths <global-config> — global config plus every project
# config that exists.
_migration_config_paths() {
  local global_config="$1" project
  if [[ -f "${global_config}" ]]; then printf '%s\n' "${global_config}"; fi
  while IFS= read -r project; do
    if [[ -n "${project}" && -f "${project}/.devbot.project.jsonc" ]]; then
      printf '%s\n' "${project}/.devbot.project.jsonc"
    fi
  done < <(_migration_project_dirs "${global_config}")
}

# ── Migrations ────────────────────────────────────────────────────────────────
# Each function receives the global config path as $1. Keep up/down pairs
# together and named for the release that introduced the up.

# 1.9.0 — the retired boolean `worktrees` became the `workflow` name.
function migration_up-1.9.0 {
  local config="${1:?global config path required}"
  if [[ ! -f "${config}" ]]; then
    _migration_skip "no global config at ${config} — nothing to migrate"
    return 0
  fi
  python3 "$(_migration_tools_dir)/migrate_workflow_config.py" "${config}"
}

function migration_down-1.9.0 {
  local config="${1:?global config path required}"
  if [[ ! -f "${config}" ]]; then
    _migration_skip "no global config at ${config} — nothing to roll back"
    return 0
  fi
  python3 "$(_migration_tools_dir)/migrate_workflow_config.py" --down "${config}"
}

# 1.15.0 — flat `commit_memory` / `workflow` / `monorepo` (and the older
# `supervisor`) moved into the `workspace` block.
function migration_up-1.15.0 {
  local config="${1:?global config path required}"
  local -a paths=()
  local path
  while IFS= read -r path; do
    if [[ -n "${path}" ]]; then paths+=("${path}"); fi
  done < <(_migration_config_paths "${config}")
  if (( ${#paths[@]} == 0 )); then
    _migration_skip "no config files to migrate"
    return 0
  fi
  python3 "$(_migration_tools_dir)/migrate_workspace_config.py" "${paths[@]}"
}

function migration_down-1.15.0 {
  local config="${1:?global config path required}"
  local -a paths=()
  local path
  while IFS= read -r path; do
    if [[ -n "${path}" ]]; then paths+=("${path}"); fi
  done < <(_migration_config_paths "${config}")
  if (( ${#paths[@]} == 0 )); then
    _migration_skip "no config files to roll back"
    return 0
  fi
  python3 "$(_migration_tools_dir)/migrate_workspace_config.py" --down "${paths[@]}"
}
