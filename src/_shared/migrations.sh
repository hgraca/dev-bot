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

# 1.17.0 — every project config gains the default `autobot` block, so the options
# are discoverable without anyone hand-writing them. The block is inert: the
# follow-up pollers are off and there are no prompts. The down half therefore
# leaves it alone rather than risk deleting a configuration someone has tuned.
function migration_up-1.17.0 {
  local config="${1:?global config path required}"
  local path added=0 failed=0
  while IFS= read -r path; do
    # `_migration_config_paths` also yields the global config; `autobot` is a
    # project key, so seeding it there would be wrong.
    [[ "${path}" == */.devbot.project.jsonc ]] || continue
    case "$(python3 "${DEV_BOT_ROOT}/src/_shared/ensure_autobot_block.py" "${path}" 2>/dev/null || true)" in
      injected) added=$((added + 1)) ;;
      present) ;;
      *)
        _migration_warn "could not seed the autobot block in ${path}"
        failed=1
        ;;
    esac
  done < <(_migration_config_paths "${config}")
  _migration_ok "autobot block added to ${added} project config(s)"
  return "${failed}"
}

function migration_down-1.17.0 {
  local config="${1:?global config path required}"
  _migration_skip "autobot defaults are inert — leaving ${config} untouched"
  return 0
}

# 1.18.0 — the `autobot` block gains the Slack conversation keys. 1.17.0 seeded
# the block before they existed, and `ensure_autobot_block.py` answers `present`
# for a block it finds, so a project that ran it keeps a block that never
# mentions `poll_slack`. They go in commented out, like the rest: the migration
# is discoverability, not configuration. A project on a global profile, or one
# that opted out with `null`, is left alone. The down half is inert for the same
# reason 1.17.0's is: nothing functional was added to remove.
function migration_up-1.18.0 {
  local config="${1:?global config path required}"
  local path added=0 present=0 failed=0
  while IFS= read -r path; do
    # Project configs only, for the same reason as 1.17.0.
    [[ "${path}" == */.devbot.project.jsonc ]] || continue
    case "$(python3 "${DEV_BOT_ROOT}/src/_shared/ensure_autobot_slack_keys.py" "${path}" 2>/dev/null || true)" in
      injected) added=$((added + 1)) ;;
      present) present=$((present + 1)) ;;
      *)
        _migration_warn "could not add the slack keys to ${path}"
        failed=1
        ;;
    esac
  done < <(_migration_config_paths "${config}")
  _migration_ok "slack keys added to ${added} project config(s), ${present} already had them"
  return "${failed}"
}

function migration_down-1.18.0 {
  local config="${1:?global config path required}"
  _migration_skip "the slack keys are comments — leaving ${config} and its projects untouched"
  return 0
}

# 1.19.0 — the shipped guard rules gain the kubectl prohibition (cluster access
# is MCP-only from this release). A rule only reaches an install through its
# dist config, and a runtime config is never overwritten: both the global
# `.devbot.global.jsonc` (installed once) and every project config keep
# whatever they had. Without this half an upgraded machine reads a memory file
# that says a guard blocks kubectl while no rule exists.
#
# The rule TEXT is read from the shipped dist, so the message is not restated
# here; only the regexes this release introduces are considered, so a dist that
# gains an unrelated rule later is not retro-applied by this migration. The
# down half removes exactly those two regexes and leaves anything else alone.
function migration_up-1.19.0 {
  local config="${1:?global config path required}"
  local dist="${DEV_BOT_ROOT}/.devbot.global.dist.jsonc"
  local helper="${DEV_BOT_ROOT}/src/_shared/ensure_guard_rules.py"
  local path added=0 present=0 failed=0

  if [[ ! -f "${dist}" ]]; then
    _migration_warn "no shipped dist at ${dist} — guard rules not seeded"
    return 1
  fi

  while IFS= read -r path; do
    case "$(python3 "${helper}" --from "${dist}" \
      --only-regex '(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*/)?kubectl(?:\s|$)' \
      --only-regex '(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*/)?devbot\s+kctl\s+(?:run|exec)\b' \
      "${path}" 2>/dev/null || true)" in
      added\ *) added=$((added + 1)) ;;
      present) present=$((present + 1)) ;;
      *)
        _migration_warn "could not seed the kubectl guard rule in ${path}"
        failed=1
        ;;
    esac
  done < <(_migration_config_paths "${config}")
  _migration_ok "kubectl guard rule added to ${added} config(s), ${present} already had it"
  return "${failed}"
}

function migration_down-1.19.0 {
  local config="${1:?global config path required}"
  local helper="${DEV_BOT_ROOT}/src/_shared/ensure_guard_rules.py"
  local path removed=0 failed=0

  while IFS= read -r path; do
    case "$(python3 "${helper}" \
      --remove-regex '(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*/)?kubectl(?:\s|$)' \
      --remove-regex '(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:\S*/)?devbot\s+kctl\s+(?:run|exec)\b' \
      "${path}" 2>/dev/null || true)" in
      removed\ *) removed=$((removed + 1)) ;;
      absent) ;;
      *)
        _migration_warn "could not remove the kubectl guard rule from ${path}"
        failed=1
        ;;
    esac
  done < <(_migration_config_paths "${config}")
  _migration_ok "kubectl guard rule removed from ${removed} config(s)"
  return "${failed}"
}

# 1.20.0 — `kubectl.clusters` became an object. The key names the MCP server
# (`kctl-<key>`) and everything generated from it; `name` is the AWS EKS cluster
# the API is asked for. The array gave one string to four jobs — the AWS
# cluster, the kubeconfig cluster object, the `devbot-<name>` user and the
# `kctl-<key>` server — so the two could not differ. The up half keys by the old
# name and keeps it as `name`, which is why no `kctl-*` server renames, and the
# project selection (also the old name) needs no change.
#
# The down half rebuilds the array from each entry's AWS `name` and repoints
# every project's selection from the key to that name, because a key that
# differs from the AWS cluster does not exist in the array form.
function migration_up-1.20.0 {
  local config="${1:?global config path required}"
  _migration_kubectl_catalogue "${config}"
}

function migration_down-1.20.0 {
  local config="${1:?global config path required}"
  _migration_kubectl_catalogue "${config}" --down
}

_migration_kubectl_catalogue() {
  local config="$1" down="${2:-}"
  local -a args=()
  [[ -n "${down}" ]] && args+=("${down}")
  # A downgrade repoints every project's selection: it lists keys, and a key that
  # differs from its AWS cluster name does not exist in the array form.
  local -a projects=()
  if [[ -n "${down}" ]]; then
    local path
    while IFS= read -r path; do
      [[ "${path}" == */.devbot.project.jsonc ]] && projects+=("${path}")
    done < <(_migration_config_paths "${config}")
  fi
  local out
  if ! out="$(python3 "$(_migration_tools_dir)/migrate_kubectl_clusters.py" \
    ${args[@]+"${args[@]}"} "${config}" ${projects[@]+"${projects[@]}"} 2>&1)"; then
    _migration_warn "kubectl catalogue: ${out}"
    return 1
  fi
  case "${out}" in
    migrated*)
      if [[ -n "${down}" ]]; then
        _migration_ok "kubectl catalogue reverted to the array form"
      else
        _migration_ok "kubectl catalogue keyed by cluster name"
      fi
      ;;
    *)
      _migration_skip "kubectl catalogue already in the target shape"
      ;;
  esac
  return 0
}

# 1.25.0 — the `herdr` and `ghostty` tool modules ship DISABLED. A module the
# config never names reads as enabled, and the module scripts run before the
# reconciler writes the dist defaults, so the gate would provision both on the
# update that crosses this release. The migration writes the explicit `false`
# first, and only where the config names the module NOWHERE: a machine that set
# either value itself keeps that choice, which is the contract the module gate
# documents.
#
# The down half does nothing: neither module exists below 1.25.0, so the keys this
# migration wrote are inert there and undoing them would only guess at a value.
function migration_up-1.25.0 {
  local config="${1:?global config path required}"
  _migration_module_flag "${config}" false
}

function migration_down-1.25.0 {
  _migration_skip "herdr and ghostty do not exist below 1.25.0 — nothing to undo"
  return 0
}

# _migration_module_flag <config> <true|false> — write both tool-module defaults.
_migration_module_flag() {
  local config="$1" value="$2" helper
  helper="$(_migration_tools_dir)/set_module_flags.py"

  if [[ ! -f "${config}" ]]; then
    _migration_skip "no global config at ${config} — herdr/ghostty defaults not written"
    return 0
  fi
  if [[ ! -f "${helper}" ]]; then
    _migration_warn "missing ${helper} — herdr/ghostty defaults not written"
    return 1
  fi

  local out
  # --if-absent: never overwrite a value the machine chose for itself.
  if ! out="$(python3 "${helper}" --if-absent "${config}" "herdr=${value}" "ghostty=${value}" 2>&1)"; then
    _migration_warn "could not set the herdr/ghostty module defaults in ${config}: ${out}"
    return 1
  fi
  _migration_ok "herdr and ghostty modules ${value} in ${config}"
  return 0
}
