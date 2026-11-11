#!/usr/bin/env bash
# =============================================================================
# bin/update.sh
# Updates the dev-bot agent kit to the newest RELEASE TAG, then refreshes the
# install's tooling against the new code.
#
# devbot update is release-tracked — it no longer pulls the current branch.
# Run with no argument to move to the newest release tag, or pass a tag name
# (devbot update <tag>) to move to that tag explicitly — pin or downgrade.
#   1. Fetch tags from origin. Target = the newest release tag (semver sort),
#      or the tag given as an argument (validated to exist).
#   2. Compare HEAD against the target tag:
#        exactly on it           -> "already on ...", exit 0
#        at / ahead of newest    -> "already on the latest version", exit 0
#                                  (auto mode only — explicit older tag moves)
#        strictly behind it      -> stash local changes, detach-checkout the tag,
#                                   then stash pop (conflict => ack prompt)
#        diverged branch         -> no implicit target: echo "not a release
#                                   checkout" and continue (an implicit update
#                                   never rewrites a branch). An EXPLICIT
#                                   `devbot update <tag>` rebases the branch onto
#                                   the tag; on conflict, abort the rebase,
#                                   restore state, exit 1.
#   3. Only when the checkout moved onto the new release:
#        python/flock checks, npm update, each tool's update.sh under
#        src/tools/, agentic pre.sh + update.sh, each harness's update.sh
#        (machine-wide provisioning only), the external module repos refresh
#        (module.sh install), the versioned config migrations for the range
#        crossed, the global config reconciliation, recording the release tag
#        in the global config's `version`, a parallel reinit of every
#        registered project, and the release notes of every version crossed.
#   4. A downgrade (`devbot update <older-tag>`) runs the matching down
#      migration for each crossed version in reverse.
#
# Safe to re-run at any time.
#
# Usage:
#   bin/update.sh              # update to the newest release tag
#   bin/update.sh <tag>        # update to a specific release tag (pin/downgrade)
#   bin/update.sh --auto       # quiet mode for the bare-`devbot` start: silent
#                              # when already on the newest release, never prompts
# =============================================================================

set -euo pipefail

# ── Resolve paths ─────────────────────────────────────────────────────────────
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"
source "${DEV_BOT_ROOT}/src/_shared/migrations.sh"

# ── PATH ──────────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:$PATH"

# ── Mode ──────────────────────────────────────────────────────────────────────
# AUTO_QUIET=1 (set by --auto) is the bare-`devbot` start path: suppress the
# progress chatter when there is nothing to do, and never prompt.
AUTO_QUIET=0

# ── Release discovery ─────────────────────────────────────────────────────────

# Fetch tags from origin. Non-zero when the fetch fails or stalls. Quiet in
# auto mode (still reports the failure).
_fetch_tags() {
  if [[ "${AUTO_QUIET}" -eq 0 ]]; then
    _header_2 "Fetching release tags"
  fi

  # Never block a start: GIT_TERMINAL_PROMPT=0 fails instead of prompting for
  # credentials, and a portable bash watchdog SIGTERMs a stalled fetch after
  # DEV_BOT_FETCH_TIMEOUT seconds (GNU `timeout` is absent on macOS).
  local cap="${DEV_BOT_FETCH_TIMEOUT:-20}"
  GIT_TERMINAL_PROMPT=0 git -C "${DEV_BOT_ROOT}" fetch --tags origin &
  local pid=$! waited=0
  while kill -0 "${pid}" 2>/dev/null; do
    if [[ "${waited}" -ge "${cap}" ]]; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      _error "Could not fetch tags from origin within ${cap}s — is the network available?"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  local rc=0
  wait "${pid}" || rc=$?
  if [[ ${rc} -ne 0 ]]; then
    _error "Could not fetch tags from origin — is the network available?"
    return 1
  fi
  if [[ "${AUTO_QUIET}" -eq 0 ]]; then
    _ok "Tags fetched from origin."
  fi
  return 0
}

# Print the newest release tag (version-sorted), or nothing when no tags exist.
_newest_release() {
  local newest=""
  # read the first line of the version-sorted list — piping into `head` would
  # SIGPIPE-kill `git tag` under pipefail once the list outgrows the buffer.
  read -r newest < <(git -C "${DEV_BOT_ROOT}" tag --sort=-v:refname) || true
  printf '%s\n' "${newest}"
}

# Verify an explicitly requested tag exists (exact ref match — no globbing).
# Non-zero when it does not; the available tags are listed for the user.
_ensure_tag_exists() {
  local tag="$1"
  if ! git -C "${DEV_BOT_ROOT}" rev-parse --verify --quiet "refs/tags/${tag}^{commit}" >/dev/null; then
    _error "Tag '${tag}' does not exist. Available tags:"
    while IFS= read -r t; do
      echo "    ${t}"
    done < <(git -C "${DEV_BOT_ROOT}" tag --sort=-v:refname)
    return 1
  fi
}

# True when the checkout is a shallow clone (install.sh clones --depth 1).
_is_shallow_repo() {
  [[ "$(git -C "${DEV_BOT_ROOT}" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]
}

# Classify HEAD against an already-resolved tag commit: ahead/behind/diverged.
_classify_vs_tag() {
  local tag_head="$1"
  if git -C "${DEV_BOT_ROOT}" merge-base --is-ancestor "${tag_head}" HEAD 2>/dev/null; then
    echo "ahead"       # tag is an ancestor of HEAD
  elif git -C "${DEV_BOT_ROOT}" merge-base --is-ancestor HEAD "${tag_head}" 2>/dev/null; then
    echo "behind"      # HEAD is an ancestor of the tag
  else
    echo "diverged"
  fi
}

# Deepen a shallow clone so ancestry can be resolved. Best-effort and bounded:
# returns non-zero (the caller keeps its pre-deepen classification) on failure.
_deepen_shallow_repo() {
  local cap="${DEV_BOT_UNSHALLOW_TIMEOUT:-60}"
  GIT_TERMINAL_PROMPT=0 git -C "${DEV_BOT_ROOT}" fetch --unshallow --tags origin >/dev/null 2>&1 &
  local pid=$! waited=0
  while kill -0 "${pid}" 2>/dev/null; do
    if [[ "${waited}" -ge "${cap}" ]]; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "${pid}" 2>/dev/null || return 1
  return 0
}

# Print HEAD's position relative to a release tag:
#   at        HEAD is exactly on the tag
#   ahead     the tag is an ancestor of HEAD (HEAD is newer / on a dev line)
#   behind    HEAD is an ancestor of the tag (an update is available)
#   diverged  neither is an ancestor of the other (branch has its own commits)
_head_vs_tag() {
  local ref="$1"
  local head tag_head
  head="$(git -C "${DEV_BOT_ROOT}" rev-parse HEAD)"
  tag_head="$(git -C "${DEV_BOT_ROOT}" rev-parse "${ref}^{commit}")"

  [[ "${head}" == "${tag_head}" ]] && { echo "at"; return; }

  local state
  state="$(_classify_vs_tag "${tag_head}")"
  # install.sh clones with --depth 1. A shallow clone's truncated history
  # cannot connect an ahead-of-tag branch to the tag, so a genuine "ahead" is
  # misread as "diverged". Deepen once and re-classify before concluding
  # diverged; if the deepen fails, keep the (safe) diverged result.
  if [[ "${state}" == "diverged" ]] && _is_shallow_repo; then
    if _deepen_shallow_repo; then
      state="$(_classify_vs_tag "${tag_head}")"
    fi
  fi
  echo "${state}"
}

_git_dirty() {
  ! (git -C "${DEV_BOT_ROOT}" diff --quiet && git -C "${DEV_BOT_ROOT}" diff --cached --quiet)
}

# Describe where HEAD is now, for the "updated X → Y" summary line.
_describe_head() {
  git -C "${DEV_BOT_ROOT}" describe --tags --abbrev=0 HEAD 2>/dev/null \
    || git -C "${DEV_BOT_ROOT}" rev-parse --short HEAD
}

# Ask the user to acknowledge a conflict left in the working tree. Best-effort:
# in a non-interactive run (no stdin) this returns immediately.
_acknowledge_conflict() {
  echo
  _warn "Reapplying your stashed changes hit conflicts — they are left in the"
  _warn "working tree for you to resolve."
  # Auto mode is non-interactive — never block the start waiting for a keypress.
  [[ "${AUTO_QUIET}" -eq 1 ]] && return 0
  _info "Press any key to acknowledge and continue the update (fix conflicts later)..."
  read -r -n 1 -s 2>/dev/null || true
  _ok "Continuing."
}

# ── Path A: strictly behind -> stash, detach-jump, reapply ───────────────────
_jump_to_release() {
  local release="$1"
  local old stashed=0
  old="$(_describe_head)"

  _header_2 "Updating to release ${release}"

  if _git_dirty; then
    _info "Stashing local changes..."
    if ! git -C "${DEV_BOT_ROOT}" stash push --include-untracked -m "update.sh auto-stash"; then
      _warn "git stash failed — commit or stash your local changes, then re-run devbot update."
      return 1
    fi
    stashed=1
    _ok "Changes stashed."
  fi

  if ! git -C "${DEV_BOT_ROOT}" checkout --detach "${release}"; then
    _error "Could not check out release ${release}."
    if [[ "${stashed}" -eq 1 ]]; then
      _info "Restoring stashed changes..."
      if ! git -C "${DEV_BOT_ROOT}" stash pop; then
        _warn "Could not restore stashed changes — see 'git stash list'."
      fi
    fi
    return 1
  fi
  _ok "Moved onto release ${release} (was ${old})."

  if [[ "${stashed}" -eq 1 ]]; then
    _info "Restoring stashed changes..."
    if ! git -C "${DEV_BOT_ROOT}" stash pop; then
      _acknowledge_conflict
    else
      _ok "Stash restored."
    fi
  fi

  UPDATE_OLD="${old}" UPDATE_NEW="${release}"
}

# ── Path B: diverged branch -> rebase onto the tag ────────────────────────────
# Returns: 0 rebased, 1 rebase failed (aborted + state restored), 2 detached
# HEAD that cannot be rebased (skip).
_rebase_onto_release() {
  local release="$1"
  local branch old stashed=0
  branch="$(git -C "${DEV_BOT_ROOT}" rev-parse --abbrev-ref HEAD)"

  if [[ "${branch}" == "HEAD" ]]; then
    _warn "Detached HEAD with commits not in ${release} — cannot rebase safely. Skipping version update."
    return 2
  fi

  old="$(_describe_head)"
  _header_2 "Rebasing ${branch} onto release ${release}"

  if _git_dirty; then
    _info "Stashing local changes..."
    if ! git -C "${DEV_BOT_ROOT}" stash push --include-untracked -m "update.sh auto-stash"; then
      _warn "git stash failed — commit or stash your local changes, then re-run devbot update."
      return 1
    fi
    stashed=1
    _ok "Changes stashed."
  fi

  if ! git -C "${DEV_BOT_ROOT}" rebase "${release}"; then
    _warn "Rebase of ${branch} onto ${release} failed (conflicts)."
    if git -C "${DEV_BOT_ROOT}" rebase --abort; then
      _ok "Rebase aborted — branch state restored."
    else
      _warn "git rebase --abort failed — inspect the repository state manually."
    fi
    if [[ "${stashed}" -eq 1 ]]; then
      _info "Restoring stashed changes..."
      if ! git -C "${DEV_BOT_ROOT}" stash pop; then
        _warn "Could not restore stashed changes — see 'git stash list'."
      fi
    fi
    _error "Attempted to rebase ${branch} onto release ${release}, but conflicts occurred;"
    _error "the rebase was aborted and your branch is exactly as it was before. Resolve the"
    _error "conflicts manually (e.g. git rebase --continue after fixing, or redo the branch),"
    _error "then re-run devbot update."
    return 1
  fi
  _ok "Rebased ${branch} onto release ${release} (was ${old})."

  if [[ "${stashed}" -eq 1 ]]; then
    _info "Restoring stashed changes..."
    if ! git -C "${DEV_BOT_ROOT}" stash pop; then
      _acknowledge_conflict
    else
      _ok "Stash restored."
    fi
  fi

  UPDATE_OLD="${old}" UPDATE_NEW="${release}"
}

# ── npm dependencies (package.json) ──────────────────────────────────────────
_update_dependencies() {
  _header_2 "npm Dependencies"

  if [[ ! -f "${DEV_BOT_ROOT}/package.json" ]]; then
    _skip "No package.json found"
    return 0
  fi

  _info "Updating npm dependencies..."
  # Serialize across concurrent updates sharing the npm cache (see
  # bin/install.sh's _install_dependencies — same reify contention).
  local npm_cache="${npm_config_cache:-$HOME/.npm}" locked=false
  if _devbot_lock_wait "${npm_cache}/.devbot-install.lock" 600 \
    "npm cache lock held >600s by another dev-bot install — proceeding without it"; then
    locked=true
  fi
  npm update --prefix "${DEV_BOT_ROOT}"
  if [[ "${locked}" == true ]]; then
    { exec 200>&-; } 2>/dev/null || true
  fi
  _ok "npm dependencies updated"
}

# ── External module repos (vendor) ───────────────────────────────────────────
# An explicit `devbot update` promises everything is current, external module
# clones included. A moving release refreshes them through the module update
# loop (src/tools/external-modules/update.sh runs install.sh); the no-move exits
# below never reach that loop, so refresh there instead.
#
# `--auto` (the bare-`devbot` start) deliberately does NOT: the start-time check
# in external-modules/up.sh has its own 24h gate, and a full fetch here would
# defeat it on every start.
_sync_external_modules_on_noop() {
  [[ "${AUTO_QUIET}" -eq 1 ]] && return 0

  local script="${DEV_BOT_ROOT}/src/tools/external-modules/update.sh"
  [[ -f "${script}" ]] || return 0

  _header_2 "External Modules"
  if bash "${script}"; then
    _ok "external modules refreshed"
  else
    _warn "external modules refresh reported issues — see output above"
  fi
  return 0
}

# ── Capture the pre-checkout migration tooling ───────────────────────────────
# A downgrade checks out an older release whose own tools predate the down
# modes, so the down half must run the tools the running release shipped. Copy
# them aside before the checkout; an upgrade ignores the copy and uses the
# target checkout's tools.
_capture_migration_tools() {
  local dir="${DEV_BOT_ROOT}/storage/run/migrate-tools"
  local file
  rm -rf "${dir}"
  mkdir -p "${dir}"
  for file in migrations.sh read_jsonc.py migrate_workflow_config.py migrate_workspace_config.py; do
    if [[ -f "${DEV_BOT_ROOT}/src/_shared/${file}" ]]; then
      cp "${DEV_BOT_ROOT}/src/_shared/${file}" "${dir}/${file}"
    fi
  done
  printf '%s' "${dir}"
}

# ── Record the installed release ──────────────────────────────────────────────
# Write the release tag into the global config's `version` and seed the
# `auto_update` key (default true) for installs that predate it. This runs after
# a clean migrate + reconcile; the updater then reinits every registered
# project. Also drop the retired global baseline (.devbot.global.sha) if an
# older install left one behind.
_record_installed_version() {
  local release="$1"
  _header_2 "Recording installed version"

  _devbot_ensure_global_value auto_update true \
    || _warn "could not seed auto_update in the global config"

  if _devbot_set_global_value version "\"${release}\""; then
    _ok "version → ${release}"
  else
    _warn "could not record version ${release} in the global config"
  fi

  local stale_sha="${DEV_BOT_ROOT}/.devbot.global.sha"
  if [[ -e "${stale_sha}" ]]; then
    rm -f "${stale_sha}"
    _ok "removed retired global config baseline"
  fi
}

# ── Global config reconciliation ──────────────────────────────────────────────
# Realign the runtime global config with the shipped schema after an upgrade:
# add top-level properties the dist template gained, drop the ones it retired.
# A key present in both keeps its runtime value and comment (the machine's
# choice wins); nested objects are otherwise never touched — except the
# catalogue/default maps (`external_modules`, `modules`), which are merged
# additively so a newly shipped module reaches existing installs with the dist
# default while an explicit machine value always wins. The tool is a no-op when
# the key sets already match. See src/_shared/reconcile_global_config.py.
_reconcile_global_config() {
  _header_2 "Global config reconciliation"

  local dist="${DEV_BOT_ROOT}/.devbot.global.dist.jsonc"
  local runtime="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  local tool="${DEV_BOT_ROOT}/src/_shared/reconcile_global_config.py"

  if [[ ! -f "${dist}" ]]; then
    _skip "no dist config at ${dist} — nothing to reconcile"
    return 0
  fi
  if [[ ! -f "${runtime}" ]]; then
    _skip "no global config at ${runtime} — nothing to reconcile"
    return 0
  fi
  if [[ ! -f "${tool}" ]]; then
    _warn "reconciler not found — skipping global config reconciliation"
    return 0
  fi

  local report=""
  if ! report="$(python3 "${tool}" "${dist}" "${runtime}" 2>&1)"; then
    _warn "global config reconciliation failed — left as-is"
    [[ -n "${report}" ]] && echo "  ${report}" >&2
    return 0
  fi

  if [[ "${report}" == *NOCHANGE* ]]; then
    _skip "global config already matches the dist schema"
    return 0
  fi

  local line
  while IFS= read -r line; do
    [[ -n "${line}" ]] && _ok "${line}"
  done <<< "${report}"
}

# ── Retry a bootstrap that needs attention ───────────────────────────────────
# The one-release 1.15.0 bootstrap runs from the devbot-cli module, and the
# pre-1.15 updater records the target even when a module fails. A failed
# bootstrap leaves a marker; retry it here so a recorded version never hides an
# unmigrated config. The run is idempotent.
_retry_pending_bootstrap() {
  local marker="${DEV_BOT_ROOT}/storage/run/migrate-bootstrap-pending"
  local source="${DEV_BOT_ROOT}/src/_shared/migrations.sh"
  local config newest
  [[ -f "${marker}" && -f "${source}" ]] || return 0
  newest="$(_devbot_install_version)"
  [[ -n "${newest}" ]] || return 0
  config="$(_devbot_global_config)"
  _warn "retrying the pending config bootstrap from 0.0.0"
  if _migration_run_phase 0.0.0 "${newest}" "${config}" "${source}"; then
    rm -f "${marker}"
    return 0
  fi
  return 1
}

# ── Reinitialise the registered projects ─────────────────────────────────────
# A migration or a version bump only takes full effect once each project is
# rewired. `devbot init --all` does that sequentially; a migration can touch
# every registered checkout, so run one init per project in parallel. Each run
# writes only its own project, and add_project.py is a no-op for an already
# registered project, so the runs do not race on the global config. Output is
# captured per project and surfaced only on failure.
_reinit_registered_projects() {
  local global_config="$1"
  local -a dirs=() pids=() names=()
  local dir name log log_dir index=0 failed=0
  REINIT_FAILED=0

  if [[ ! -f "${DEV_BOT_ROOT}/bin/init.sh" ]]; then
    _warn "bin/init.sh not found — skipping project reinit"
    return 0
  fi

  while IFS= read -r dir; do
    if [[ -n "${dir}" && -d "${dir}" ]]; then dirs+=("${dir}"); fi
  done < <(_migration_project_dirs "${global_config}")

  if (( ${#dirs[@]} == 0 )); then
    _skip "no registered projects to reinitialise"
    return 0
  fi

  _header_2 "Reinitialising ${#dirs[@]} registered project(s)"
  log_dir="${DEV_BOT_ROOT}/storage/run/reinit"
  mkdir -p "${log_dir}"

  # `init --all` defers the env-var dialog; a parallel per-project run must do
  # the same or every child would block on the same prompt.
  export DEV_BOT_DEFER_ENV_DIALOG=1
  for dir in "${dirs[@]}"; do
    index=$(( index + 1 ))
    name="$(basename "${dir}")"
    log="${log_dir}/${index}-${name}.log"
    bash "${DEV_BOT_ROOT}/bin/init.sh" "${dir}" </dev/null >"${log}" 2>&1 &
    pids+=("$!")
    names+=("${name}")
  done

  local i
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
      _ok "reinitialised ${names[$i]}"
    else
      _warn "reinit failed for ${names[$i]} — see ${log_dir}"
      REINIT_FAILED=$(( REINIT_FAILED + 1 ))
      failed=1
    fi
  done
  unset DEV_BOT_DEFER_ENV_DIALOG
  return "${failed}"
}

# ── Summary ────────────────────────────────────────────────────────────────────
print_summary() {
  _header_2 "✔  DevBot update complete"

  echo -e "  ${TEXT_BOLD}Root   :${TEXT_CLEAR} ${DEV_BOT_ROOT}"
  if [[ -n "${UPDATE_OLD:-}" && -n "${UPDATE_NEW:-}" ]]; then
    echo -e "  ${TEXT_BOLD}Release:${TEXT_CLEAR} ${UPDATE_OLD} → ${UPDATE_NEW}"
  fi
  echo -e "  ${TEXT_BOLD}Updated:${TEXT_CLEAR} ${UPDATED:-0}"
  [[ "${FAILED:-0}" -gt 0 ]] && echo -e "  ${TEXT_BOLD}Failed :${TEXT_CLEAR} ${FAILED}"
  echo -e "  ${TEXT_BOLD}Module Updated:${TEXT_CLEAR} ${MODULE_UPDATED:-0}"
  [[ "${MODULE_FAILED:-0}" -gt 0 ]] && echo -e "  ${TEXT_BOLD}Failed :${TEXT_CLEAR} ${MODULE_FAILED}"
  [[ "${REINIT_FAILED:-0}" -gt 0 ]] && echo -e "  ${TEXT_BOLD}Reinit failures:${TEXT_CLEAR} ${REINIT_FAILED}"
  echo -e "  ${TEXT_BOLD}Prereqs:${TEXT_CLEAR} ${MODULE_PREREQ_PASSED:-0} passed, ${MODULE_PREREQ_FAILED:-0} failed, ${MODULE_PREREQ_SKIPPED:-0} without pre-reqs"
  echo
  echo -e "  ${TEXT_BOLD}Verify:${TEXT_CLEAR}"
  echo "    devbot update  (safe to re-run)"
  echo
}

# ── Release notes ─────────────────────────────────────────────────────────────
# Print the notes of every release between $1 and $2: strictly newer than $1,
# up to and including $2, oldest first. A release stores its notes as the
# annotated tag message (tag.sh writes release.v<VERSION>.no-vcs.md with -F),
# which _fetch_tags has already brought down — the file itself is local-only.
_print_release_notes() {
  local from="$1" to="$2"
  [[ -n "${from}" && -n "${to}" ]] || return 0

  local tags=() tag body kind i
  while IFS= read -r tag; do
    # Release tags: X.Y.Z stable, 0.X.Y.Z unstable.
    [[ "${tag}" =~ ^([0-9]*[1-9][0-9]*\.[0-9]+\.[0-9]+|0\.[0-9]+\.[0-9]+\.[0-9]+)$ ]] || continue
    tags+=("${tag}")
  done < <(git -C "${DEV_BOT_ROOT}" tag --sort=v:refname)

  local from_idx=-1 to_idx=-1
  for i in "${!tags[@]}"; do
    [[ "${tags[$i]}" == "${from}" ]] && from_idx=$i
    [[ "${tags[$i]}" == "${to}" ]] && to_idx=$i
  done
  [[ "${to_idx}" -lt 0 ]] && return 0

  # An unknown source tag or a downgrade leaves no range: show the target only.
  local start=$(( from_idx + 1 ))
  if [[ "${from_idx}" -lt 0 || "${start}" -gt "${to_idx}" ]]; then
    start="${to_idx}"
  fi

  _header_2 "Release Notes"
  if [[ "${from_idx}" -lt 0 ]]; then
    _info "the version being left is not a release tag — showing ${to} only"
  fi
  for (( i = start; i <= to_idx; i++ )); do
    tag="${tags[$i]}"
    # Lightweight tags hold a commit message, not notes.
    kind="$(git -C "${DEV_BOT_ROOT}" cat-file -t "${tag}" 2>/dev/null || true)"
    body="$(git -C "${DEV_BOT_ROOT}" tag -l --format='%(contents)' "${tag}")"
    if [[ "${kind}" != "tag" || "${body}" != "# Release v"* ]]; then
      _skip "${tag} — no release notes recorded"
      continue
    fi
    while [[ "${body}" == *$'\n' ]]; do body="${body%$'\n'}"; done
    echo
    while IFS= read -r line; do
      if [[ -z "${line}" ]]; then
        echo
      else
        echo "  ${line}"
      fi
    done <<< "${body}"
  done
  echo
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  local total_start=${SECONDS}
  local tool_count=0 tool_failed=0
  local module_count=0 module_failed=0

  # Args may appear in any order: `--auto` (quiet, non-interactive) and one
  # optional explicit tag. `--` ends flag parsing (a following arg is a tag).
  local tag="" end_of_flags=0 arg=""
  while [[ $# -gt 0 ]]; do
    arg="$1"
    if [[ "${end_of_flags}" -eq 0 ]]; then
      case "${arg}" in
        --auto)
          AUTO_QUIET=1
          shift
          continue
          ;;
        --)
          end_of_flags=1
          shift
          continue
          ;;
        -*)
          _error "Unknown option: ${arg}"
          exit 1
          ;;
      esac
    fi
    if [[ -n "${tag}" ]]; then
      _error "Unexpected extra argument: ${arg}"
      exit 1
    fi
    tag="${arg}"
    shift
  done

  # Serialize the git move across concurrent starts. The lock lives on fd 200
  # and is released before the refresh block, which reuses fd 200 for the npm
  # lock. A contender that cannot take the lock skips this update and continues
  # the start on the current version.
  local lock_file="${DEV_BOT_ROOT}/storage/run/update.lock"
  if ! _devbot_lock_wait "${lock_file}" "${DEV_BOT_UPDATE_LOCK_WAIT:-60}" \
    "another devbot update is in progress — skipping this one"; then
    _skip "another devbot update is in progress — skipping"
    exit 0
  fi

  # Interactive mode announces itself up front; auto mode stays silent until it
  # knows there is something to do.
  [[ "${AUTO_QUIET}" -eq 0 ]] && _header_1 "DevBot Update"

  if ! _fetch_tags; then
    exit 1
  fi

  # Target: an explicitly requested tag (pin/downgrade) or the newest tag
  # (release-tracked update).
  local target="" explicit=0
  if [[ -n "${tag}" ]]; then
    target="${tag}"
    explicit=1
    if ! _ensure_tag_exists "${target}"; then
      exit 1
    fi
  else
    target="$(_newest_release)"
    if [[ -z "${target}" ]]; then
      _skip "No release tags found — nothing to update."
      _sync_external_modules_on_noop
      exit 0
    fi
  fi

  local state migration_capture
  state="$(_head_vs_tag "${target}")"
  # Capture the running release's migration tooling before the checkout: a
  # downgrade needs the down modes that the older target lacks.
  migration_capture="$(_capture_migration_tools)"
  # A bootstrap left pending by the introducing release is retried on every run,
  # including the already-on-target no-op path.
  _retry_pending_bootstrap || true
  case "${state}" in
    at)
      if [[ "${explicit}" -eq 1 ]]; then
        _ok "Already on ${target}."
      else
        _ok "Already on the latest version (${target})."
      fi
      _sync_external_modules_on_noop
      exit 0
      ;;
    ahead)
      # Auto mode: ahead of the newest tag = dev line, nothing to update.
      # Explicit mode: the user asked for an older tag — move to it.
      if [[ "${explicit}" -eq 1 ]]; then
        [[ "${AUTO_QUIET}" -eq 1 ]] && _header_1 "DevBot Update"
        _jump_to_release "${target}" || exit 1
      else
        _ok "Already on the latest version (${target})."
        _sync_external_modules_on_noop
        exit 0
      fi
      ;;
    behind)
      [[ "${AUTO_QUIET}" -eq 1 ]] && _header_1 "DevBot Update"
      _jump_to_release "${target}" || exit 1
      ;;
    diverged)
      # A branch with commits of its own — neither an ancestor nor a descendant
      # of the release — is a development line, not a release checkout. An
      # implicit update (newest tag) must never rewrite it: only an explicit
      # `devbot update <tag>` rebases. Echo and continue on the current version.
      # (install.sh clones with --depth 1, whose truncated history makes an
      # ahead-of-tag branch look diverged here — this path is the safe one for
      # those shallow installs too.)
      if [[ "${explicit}" -eq 1 ]]; then
        [[ "${AUTO_QUIET}" -eq 1 ]] && _header_1 "DevBot Update"
        local rebase_rc=0
        _rebase_onto_release "${target}" || rebase_rc=$?
        [[ "${rebase_rc}" -eq 2 ]] && exit 0
        [[ "${rebase_rc}" -eq 1 ]] && exit 1
      else
        local dev_branch
        dev_branch="$(git -C "${DEV_BOT_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
        if [[ "${dev_branch}" == "HEAD" ]]; then
          _ok "Detached HEAD is not a release checkout — skipping update."
        else
          _ok "Branch '${dev_branch}' is not a release checkout — skipping update."
        fi
        _sync_external_modules_on_noop
        exit 0
      fi
      ;;
  esac

  # The git move is done — release the update lock so the npm step below can
  # take fd 200 for its own lock.
  { exec 200>&-; } 2>/dev/null || true

  # Only reached when the checkout moved onto the new release.
  _check_python3
  _check_flock
  _update_dependencies

  # GPU detection re-runs on update (devbot level, not the ollama module) so
  # gpu_enabled tracks the machine even when the ollama module is disabled.
  _header_2 "GPU Detection"
  _devbot_detect_gpu

  _header_2 "Tools"
  _update_modules "${DEV_BOT_ROOT}/src/tools"
  tool_count="${MODULE_SCRIPT_COUNT:-0}"
  tool_failed="${MODULE_SCRIPT_FAILED:-0}"

  _header_2 "Agentic Modules"
  _run_module_prereqs
  _update_modules "${DEV_BOT_ROOT}/src/agentic"
  module_count="${MODULE_SCRIPT_COUNT:-0}"
  module_failed="${MODULE_SCRIPT_FAILED:-0}"

  # Harness update.sh scripts do machine-wide provisioning only (e.g. the
  # opencode harness's pinned Intelephense); per-project wiring is handled at
  # the end of this run by _reinit_registered_projects.
  _header_2 "Harnesses"
  _update_modules "${DEV_BOT_ROOT}/src/harnesses"
  module_count=$(( module_count + ${MODULE_SCRIPT_COUNT:-0} ))
  module_failed=$(( module_failed + ${MODULE_SCRIPT_FAILED:-0} ))

  # Migrate every retired config key over the range this update crossed,
  # before the reconciler drops the old keys. The phase runs in a fresh shell
  # so an upgrade loads the target checkout's migration set; a downgrade uses
  # the tools captured before the checkout. On failure, keep the old recorded
  # version so the same range runs again on the next update.
  local global_config from_version migration_source migration_tools=""
  global_config="$(_devbot_global_config)"
  from_version="$(python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${global_config}" version 2>/dev/null || true)"
  if [[ -z "${from_version}" ]]; then
    from_version="${UPDATE_OLD:-0.0.0}"
  fi
  local bootstrap_marker="${DEV_BOT_ROOT}/storage/run/migrate-bootstrap-pending"
  if [[ -f "${bootstrap_marker}" ]]; then
    _warn "config bootstrap still pending — retrying over the full range"
    from_version="0.0.0"
  fi
  if _migration_version_lt "${target}" "${from_version}"; then
    migration_source="${migration_capture}/migrations.sh"
    migration_tools="${migration_capture}"
  else
    migration_source="${DEV_BOT_ROOT}/src/_shared/migrations.sh"
  fi

  if _migration_run_phase "${from_version}" "${target}" "${global_config}" "${migration_source}" "${migration_tools}"; then
    rm -f "${bootstrap_marker}"
    _reconcile_global_config
    _record_installed_version "${target}"
    _reinit_registered_projects "${global_config}" || true
  else
    _warn "config migrations need attention — version not recorded; resolve them and run devbot update again"
  fi

  UPDATED="${tool_count}" FAILED="${tool_failed}"
  MODULE_UPDATED="${module_count}" MODULE_FAILED="${module_failed}"
  print_summary
  _print_release_notes "${UPDATE_OLD:-}" "${UPDATE_NEW:-}"

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
