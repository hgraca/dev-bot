#!/usr/bin/env bash
# =============================================================================
# src/tools/external-modules/up.sh
# Bring external module clones up to date on start.
#
# bin/up.sh merges every module's external-modules.json declarations into
# .devbot.global.jsonc and then runs this script, so a bare `devbot` start
# (and `devbot up`) checks each git-backed module against its remote. The check
# is a single `git ls-remote` per clone — refs only, no objects — and all the
# checks run at once, because the serial cost is what made a start wait on N
# network round trips. A clone is fetched and hard-reset only when its remote
# actually diverged; its storage mirror is re-rendered afterwards, so lifecycle
# scripts added upstream appear too.
#
# The whole check runs at most once per interval (default 24h), recorded in
# storage/run/external-modules.checked: a warm start inside the interval pays
# nothing at all. DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL overrides it in
# seconds; 0 checks on every start.
#
# Local-path modules are left untouched: there is no remote to compare with.
#
# Opt out with `auto_update: false` in .devbot.global.jsonc — the same switch
# that keeps the dev-bot install itself from updating on start, so a pinned or
# offline machine pays no network cost here either.
#
# Never fails the start: an unreachable remote, a deleted upstream branch or a
# failed update is a warning, not an abort.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# Entries this run provisioned without an existing mirror — bin/init.sh ran
# BEFORE this phase and skipped them, so each needs its project link built at
# the end of the run. One `name<US>dest<US>paths_json` line each.
ENTRIES_TO_WIRE=""

# Render the cheap, idempotent parts of one config entry's provisioning.
# READMEs are pruned on every run because any reset of a shared clone restores
# them. The mirror is rendered when it is absent — so an entry sharing a clone
# still gets one — or when the clone was updated in this run (a lifecycle
# script gained upstream must reach every co-tenant's mirror).
# Args: name dest paths_json dev_bot_root force_mirror
_provision_entry() {
  local name="$1"
  local dest="$2"
  local paths_json="$3"
  local dev_bot_root="$4"
  local force_mirror="$5"

  local mirror="${dev_bot_root}/storage/external-agentic-modules/${name}"
  local need_wiring=0
  [[ -d "${mirror}" ]] || need_wiring=1

  _remove_readme_from_paths "${dest}" "${paths_json}"
  if [[ "${force_mirror}" == "1" || ${need_wiring} -eq 1 ]]; then
    if ! _setup_external_module_storage "${dest}" "${name}" "${paths_json}" "${dev_bot_root}"; then
      _warn "${name}: mirror render failed"
      return 1
    fi
  fi

  # Queue the project link only after the mirror exists: a failed render must
  # never expose the vendor checkout directly through `.agents`.
  if [[ ${need_wiring} -eq 1 ]]; then
    ENTRIES_TO_WIRE+="${name}"$'\x1f'"${dest}"$'\x1f'"${paths_json}"$'\n'
  fi
  return 0
}

# Outcome of the last _sync_destination call: synced | current | unavailable |
# failed.
DEST_STATUS=""


# Wire the entries this run provisioned without a pre-existing mirror into the
# project. Only those: the broad init pass would also act on entries this run
# rejected (a colliding URL, or a checkout owned by another repo). Non-fatal: a
# wiring failure must not fail the start (the next start, or `devbot reinit`,
# retries).
# Args: project_dir
_wire_provisioned_entries() {
  local project_dir="$1"
  [[ -n "${project_dir}" && -d "${project_dir}" ]] || return 0

  _info "wiring external modules into the project..."
  # shellcheck disable=SC2034  # read by _wire_one_module in functions.sh
  PROJECT_DIR="${project_dir}"

  # Provisioning the shared clone and mirror is enablement-independent, but a
  # per-project `.agents` link is not: init.sh refuses to wire a module the
  # project disables (directly, or through every umbrella that declares it),
  # and this pass must apply the same two checks.
  local disabled_modules disabled_externals
  disabled_modules="$(printf '%s' "$(_devbot_get_disabled_modules "${project_dir}")" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    data = []
print("\n".join(data))
' 2>/dev/null || true)"
  disabled_externals="$(_devbot_disabled_external_names "${project_dir}")"

  local name dest paths_json
  while IFS=$'\x1f' read -r name dest paths_json; do
    [[ -z "${name}" ]] && continue
    if grep -Fxq -- "${name}" <<< "${disabled_modules}" ||
      grep -Fxq -- "${name}" <<< "${disabled_externals}"; then
      _skip "${name}: disabled — skipping wiring"
      continue
    fi
    _wire_one_module "${name}" "${dest}" "${paths_json}" ||
      _warn "${name}: wiring failed — run 'devbot reinit' to retry"
  done <<< "${ENTRIES_TO_WIRE}"
}

# Check, update and provision every config entry that shares one destination.
# The clone lock is held across the network call AND all the aliases'
# provisioning: several entries can reserve the same repo (the react umbrella
# declares three collections of one mindrally/skills clone), and a concurrent
# start resetting the checkout mid-render would leave a mirror half-built.
# Never fails: sets DEST_STATUS.
# Args: dest url first_name first_paths_json entries_blob dev_bot_root project_dir compare_rc force_provision
# compare_rc is the precomputed parallel check (0 moved, 1 current, 2 could not
# compare) — this function does the writing, so it never waits on the network
# for a comparison another destination's job is still making. force_provision
# re-renders the mirrors even when the clone did not move: a configuration
# change can make an existing mirror stale.
_sync_destination() {
  local dest="$1"
  local url="$2"
  local first_name="$3"
  local first_paths_json="$4"
  local entries="$5"
  local dev_bot_root="$6"
  local project_dir="$7"
  local compare_rc="$8"
  local force_provision="${9:-0}"
  local lock_file="${dest}.lock"
  local cap="${DEV_BOT_MODULE_UPDATE_LOCK_WAIT:-120}"
  local updated=0 alias_paths="" render_failed=0
  local -a sparse_maps=("${first_paths_json}")

  # A failed acquire warns and proceeds — that is the helper's contract, and
  # the unguarded behaviour is the fallback.
  _devbot_lock_wait "${lock_file}" "${cap}" \
    "update lock held >${cap}s — continuing without it" || true

  # A checkout installed under the legacy scp-derived path moves into the
  # canonical one, still under this destination's lock.
  _external_module_migrate_legacy_checkout "$(dirname "$(dirname "${dest}")")" "${url}" "${dest}"

  # Every other entry sharing this clone contributes paths the incoming
  # version must keep: an update is validated against all of them, not just the
  # first entry's map.
  local entry_name entry_url entry_local entry_paths
  while IFS=$'\x1f' read -r entry_name entry_url entry_local entry_paths; do
    [[ -z "${entry_name}" || -n "${entry_local}" ]] && continue
    [[ "$(_normalize_remote_url "${entry_url}")" == "$(_normalize_remote_url "${url}")" ]] || continue
    [[ "${entry_paths}" == "${first_paths_json}" ]] && continue
    alias_paths+="${entry_paths}"$'\n'
    sparse_maps+=("${entry_paths}")
  done <<< "${entries}"

  # A module that is not cloned yet is installed here rather than warned
  # about: a release can declare a new external module, and the start that
  # picks the declaration up should come out usable.
  local mismatch=0
  if [[ ! -d "${dest}/.git" ]]; then
    _info "${first_name}: not installed — cloning"
    if _install_one_module "${first_name}" "${url}" "${dest}" "${first_paths_json}" "${alias_paths}"; then
      updated=1
      DEST_STATUS="synced"
    else
      DEST_STATUS="failed"
    fi
  elif ! _checkout_belongs_to "${first_name}" "${dest}" "${url}"; then
    # A retained clone from another repo at the same derived path: never
    # compare, update or mirror it under this entry's name.
    DEST_STATUS="failed"
    mismatch=1
  else
    case "${compare_rc}" in
      0)
        _info "${first_name}: remote moved — updating"
        if _install_one_module "${first_name}" "${url}" "${dest}" "${first_paths_json}" "${alias_paths}"; then
          updated=1
          DEST_STATUS="synced"
        else
          # The clone is still usable at its current commit, and the entries
          # below are still provisioned from it.
          DEST_STATUS="failed"
        fi
        ;;
      1)
        _skip "${first_name}: up to date"
        DEST_STATUS="current"
        ;;
      *)
        _warn "${first_name}: could not compare with the remote (unreachable, or the tracked branch is gone) — left as-is"
        DEST_STATUS="unavailable"
        ;;
    esac
  fi

  # Provision every entry on this destination — the first one's update must
  # reach all of them, under the lock taken above.
  if [[ ${mismatch} -eq 0 && -d "${dest}/.git" ]]; then
    # A sparse checkout carries only the paths it was last told to. A config
    # edit can declare a path it was never materialized with, and an unchanged
    # remote skips the update that would refresh it — so re-narrow here, before
    # the mirror render reads the tree.
    _external_module_sparse_set "${dest}" "${sparse_maps[@]}"
    local name entry_url local_path paths_json
    while IFS=$'\x1f' read -r name entry_url local_path paths_json; do
      [[ -z "${name}" ]] && continue
      [[ -n "${local_path}" ]] && continue
      # Normalized identity, not just the derived path: the path drops the
      # host, so github.com/acme/repo and gitlab.com/acme/repo share one
      # destination. Protocol spellings of one repo are the same remote.
      [[ "$(_normalize_remote_url "${entry_url}")" == "$(_normalize_remote_url "${url}")" ]] || continue
      local force="${updated}"
      [[ "${force_provision}" == "1" ]] && force=1
      _provision_entry "${name}" "${dest}" "${paths_json}" "${dev_bot_root}" "${force}" || render_failed=1
    done <<< "${entries}"
  fi
  if [[ ${render_failed} -eq 1 ]]; then
    # A half-rendered mirror must not be recorded as a complete check.
    DEST_STATUS="failed"
  fi

  # Release, including a descriptor left open by a failed acquire. Grouped so
  # the redirect does not permanently silence this shell's stderr.
  { exec 200>&-; } 2>/dev/null || true
}

main() {
  _info "external-modules — check for updates"

  # bin/up.sh passes the project dir; it is only needed to re-wire the project
  # after a startup clone.
  local project_dir="${1:-}"

  local dev_bot_root config_file modules_dir
  dev_bot_root="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
  config_file="${DEV_BOT_GLOBAL_CONFIG:-${dev_bot_root}/.devbot.global.jsonc}"
  modules_dir="${dev_bot_root}/vendor"

  if ! _devbot_auto_update_enabled "${config_file}"; then
    _skip "auto_update=false — external modules not checked"
    return 0
  fi

  if [[ ! -f "${config_file}" ]]; then
    _skip ".devbot.global.jsonc not found — nothing to check"
    return 0
  fi

  local entries
  entries="$(_external_module_entries "${config_file}")"
  if [[ -z "${entries}" ]]; then
    _skip "No external modules configured in .devbot.global.jsonc"
    return 0
  fi

  # ── Interval gate inputs ────────────────────────────────────────────────
  # The stamp is only trusted for the exact configuration it covered: a newly
  # declared module, an edited URL/paths, or a deleted checkout/mirror must be
  # processed now rather than silently wait out the interval.
  local stamp_file interval fingerprint fresh=0 config_changed=0 missing_work=0
  stamp_file="$(_external_module_stamp_file "${dev_bot_root}")"
  interval="$(_check_interval)"
  fingerprint="$(_external_module_fingerprint "${entries}")"
  if _check_is_fresh "${stamp_file}" "${interval}" "${fingerprint}"; then
    fresh=1
  elif [[ -f "${stamp_file}" ]]; then
    # A stamp exists but for another configuration (or one predating
    # fingerprints): its mirrors may be stale, so re-render them below.
    config_changed=1
  fi

  if [[ ${fresh} -eq 1 ]]; then
    # A checkout that went missing needs a clone, and a mirror that lost an
    # entry (not just its root) needs a local re-render.
    local need_name need_url need_local need_rel
    while IFS=$'\x1f' read -r need_name need_url need_local _; do
      [[ -z "${need_name}" ]] && continue
      if [[ -z "${need_local}" ]]; then
        if need_rel="$(_derived_vendor_path "${need_url}")"; then
          if [[ ! -d "${modules_dir}/${need_rel}/.git" ]]; then
            missing_work=1
          elif ! _checkout_origin_matches "${modules_dir}/${need_rel}" "${need_url}"; then
            # A repointed origin must be caught now, not after the interval:
            # the sync path reports it and refuses to mirror it.
            missing_work=1
          fi
        else
          missing_work=1
        fi
      fi
    done <<< "${entries}"
  fi

  # Mirror completeness is checked on EVERY run: a stamp-less run (or one whose
  # stamp was pruned) with an existing mirror root would otherwise accept an
  # up-to-date checkout, skip provisioning because the root exists, and stamp a
  # half-rendered mirror as complete.
  local probe=""
  local probe_name probe_url probe_local probe_paths probe_rel
  while IFS=$'\x1f' read -r probe_name probe_url probe_local probe_paths; do
    [[ -z "${probe_name}" ]] && continue
    _external_module_name_ok "${probe_name}" || continue
    if [[ -n "${probe_local}" ]]; then
      probe+="${probe_name}"$'\x1f'"${probe_local}"$'\x1f'"${probe_paths}"$'\n'
    elif probe_rel="$(_derived_vendor_path "${probe_url}")"; then
      probe+="${probe_name}"$'\x1f'"${modules_dir}/${probe_rel}"$'\x1f'"${probe_paths}"$'\n'
    fi
  done <<< "${entries}"
  if _external_module_mirror_incomplete "${dev_bot_root}" "${probe}"; then
    missing_work=1
    # The mirror needs re-rendering, exactly like a configuration change.
    config_changed=1
  fi

  # ── Pass 1: unique destinations, local only ─────────────────────────────
  # Vendors paths drop the host, so a destination is only usable when every
  # entry mapping onto it names the same repository.
  local plan="" seen="" skipped=0 failed=0 index=0
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
        # A missing source cannot be provisioned: fail (no stamp) so the next
        # start retries instead of going quiet for the interval.
        _warn "${name}: local path not found (${local_path})"
        failed=$((failed + 1))
        continue
      fi
      _skip "${name}: local path — nothing to update"
      skipped=$((skipped + 1))
      if [[ -d "${local_path}" ]] &&
        { [[ ${config_changed} -eq 1 ]] || [[ ! -d "${dev_bot_root}/storage/external-agentic-modules/${name}" ]]; }; then
        _setup_external_module_storage "${local_path}" "${name}" "${paths_json}" "${dev_bot_root}" ||
          failed=$((failed + 1))
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
      _warn "${name}: URL does not map inside vendor/ — skipping"
      failed=$((failed + 1))
      continue
    fi
    dest="${modules_dir}/${vendor_rel}"
    identity="$(_normalize_remote_url "${url}")"

    # Here-string, not `printf | grep -q`: under `pipefail`, grep's early exit
    # can SIGPIPE the writer and turn a match into a failed pipeline.
    if grep -Fq -- "${dest}"$'\x1f' <<< "${seen}"; then
      local known_identity
      known_identity="$(grep -F -- "${dest}"$'\x1f' <<< "${seen}" | head -1 | cut -d$'\x1f' -f2)"
      if [[ "${known_identity}" != "${identity}" ]]; then
        # Two different repos want the same directory: provisioning the second
        # from the first's checkout would silently install the wrong code.
        _warn "${name}: ${dest} is already used by another repository — skipping (two repos map to one vendor path)"
        failed=$((failed + 1))
      fi
      continue # an earlier entry already covers this clone
    fi
    seen+="${dest}"$'\x1f'"${identity}"$'\n'
    plan+="${dest}"$'\x1f'"${url}"$'\x1f'"${name}"$'\x1f'"${paths_json}"$'\x1f'"${index}"$'\n'
    index=$((index + 1))
  done <<< "${entries}"

  if [[ ${fresh} -eq 1 && ${missing_work} -eq 0 ]]; then
    local ago
    ago="$(_seconds_ago $(( $(date +%s) - $(cat "${stamp_file}") )))"
    _skip "last check ${ago} ago — next check in ${interval}s (DEV_BOT_EXTERNAL_MODULES_CHECK_INTERVAL)"
    return 0
  fi

  # ── Pass 2: check every destination at once ─────────────────────────────
  # `ls-remote` is read-only and takes no lock, so the whole set runs in
  # parallel: a start pays one round trip instead of one per module. The
  # result lands in a per-destination file (the index keeps the name safe).
  local check_dir
  check_dir="$(mktemp -d "${TMPDIR:-/tmp}/devbot-extcheck.XXXXXX")"
  local pid pids=""
  if [[ ${fresh} -eq 1 ]]; then
    # Only a missing checkout or mirror brought us here; the rest are current.
    while IFS=$'\x1f' read -r dest url name paths_json index; do
      [[ -z "${dest}" ]] && continue
      echo 1 > "${check_dir}/${index}"
    done <<< "${plan}"
  else
    while IFS=$'\x1f' read -r dest url name paths_json index; do
      [[ -z "${dest}" ]] && continue
      [[ -d "${dest}/.git" ]] || continue # nothing to compare — it will be cloned
      (
        local rc=0
        _external_module_update_available "${dest}" "${url}" || rc=$?
        echo "${rc}" > "${check_dir}/${index}"
      ) &
      pids+="$! "
    done <<< "${plan}"
    for pid in ${pids}; do
      wait "${pid}" 2>/dev/null || true
    done
  fi

  # ── Pass 3: apply, serially, under each clone's lock ────────────────────
  local synced=0 current=0 unavailable=0
  while IFS=$'\x1f' read -r dest url name paths_json index; do
    [[ -z "${dest}" ]] && continue

    local compare_rc=2
    if [[ -f "${check_dir}/${index}" ]]; then
      compare_rc="$(cat "${check_dir}/${index}")"
    fi

    DEST_STATUS=""
    _sync_destination "${dest}" "${url}" "${name}" "${paths_json}" \
      "${entries}" "${dev_bot_root}" "${project_dir}" "${compare_rc}" "${config_changed}"
    case "${DEST_STATUS}" in
      synced) synced=$((synced + 1)) ;;
      current) current=$((current + 1)) ;;
      unavailable) unavailable=$((unavailable + 1)) ;;
      *) failed=$((failed + 1)) ;;
    esac
  done <<< "${plan}"
  rm -r "${check_dir}" 2>/dev/null || true

  if [[ -n "${ENTRIES_TO_WIRE}" ]]; then
    _wire_provisioned_entries "${project_dir}"
  fi

  # Counted per clone, not per config entry: entries sharing one repo are one
  # checkout with one sync result.
  local summary="${synced} updated, ${current} up to date, ${skipped} local"
  if [[ ${unavailable} -gt 0 ]]; then
    summary+=", ${unavailable} uncomparable"
  fi
  if [[ ${failed} -gt 0 ]]; then
    summary+=", ${failed} failed"
  fi
  if [[ ${unavailable} -gt 0 || ${failed} -gt 0 ]]; then
    _warn "external modules: ${summary}"
  else
    _ok "external modules: ${summary}"
    # Only a complete check buys the quiet interval, and only for this
    # configuration: an unreachable remote (or a cancelled update) must retry
    # on the next start, not go silent for a day.
    _stamp_check "${stamp_file}" "${fingerprint}"
  fi
}

main "$@"
