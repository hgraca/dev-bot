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
#        diverged branch         -> rebase the branch onto the tag; on conflict,
#                                   abort the rebase, restore state, exit 1
#   3. Only when the checkout moved onto the new release:
#        python/flock checks, legacy engine pins, npm update, each tool's
#        update.sh under src/tools/, agentic pre.sh + update.sh, and a refresh
#        of the external module repos (module.sh install). Harnesses are never
#        touched here.
#   4. Re-run `devbot reinit --all` so every registered project re-wires.
#
# Safe to re-run at any time. Skip the final reinit with
# DEV_BOT_UPDATE_SKIP_REINIT=1.
#
# Usage:
#   bin/update.sh              # update to the newest release tag
#   bin/update.sh <tag>        # update to a specific release tag (pin/downgrade)
# =============================================================================

set -euo pipefail

# ── Resolve paths ─────────────────────────────────────────────────────────────
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── PATH ──────────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:$PATH"

# ── Release discovery ─────────────────────────────────────────────────────────

# Fetch tags from origin. Prints nothing; non-zero when the fetch fails.
_fetch_tags() {
  _header_2 "Fetching release tags"
  if ! git -C "${DEV_BOT_ROOT}" fetch --tags origin; then
    _error "Could not fetch tags from origin — is the network available?"
    return 1
  fi
  _ok "Tags fetched from origin."
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
  if git -C "${DEV_BOT_ROOT}" merge-base --is-ancestor "${tag_head}" HEAD; then
    echo "ahead"       # tag is an ancestor of HEAD
  elif git -C "${DEV_BOT_ROOT}" merge-base --is-ancestor HEAD "${tag_head}"; then
    echo "behind"      # HEAD is an ancestor of the tag
  else
    echo "diverged"
  fi
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
    exec 200>&- 2>/dev/null || true
  fi
  _ok "npm dependencies updated"
}

# ── Legacy engine pins (upgrade guard) ───────────────────────────────────────
# Existing installs predate the codebase_index_provider / memory_search_provider
# keys. On update, pin them to the PRE-SWAP engines (codebase-index, qmd) when
# absent, so an upgrade never silently flips an install onto the new defaults
# (codebase-memory / mdctx). A key that is already set — including one an
# install deliberately chose — is left untouched.
_ensure_legacy_providers() {
  _header_2 "Legacy engine pins"

  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  local reader="${DEV_BOT_ROOT}/src/_shared/read_jsonc.py"
  local pinned=0 current=""

  # codebase_index_provider → codebase-index (the pre-swap engine)
  current="$(python3 "${reader}" "${config}" codebase_index_provider 2>/dev/null || true)"
  if [[ -n "${current}" ]]; then
    _skip "codebase_index_provider already set (${current}) — left untouched"
  elif _devbot_ensure_global_default codebase_index_provider codebase-index; then
    _ok "codebase_index_provider pinned to codebase-index (legacy default)"
    pinned=1
  else
    _warn "could not pin codebase_index_provider — no global config at ${config}"
  fi

  # memory_search_provider → qmd (the pre-swap engine)
  current="$(python3 "${reader}" "${config}" memory_search_provider 2>/dev/null || true)"
  if [[ -n "${current}" ]]; then
    _skip "memory_search_provider already set (${current}) — left untouched"
  elif _devbot_ensure_global_default memory_search_provider qmd; then
    _ok "memory_search_provider pinned to qmd (legacy default)"
    pinned=1
  else
    _warn "could not pin memory_search_provider — no global config at ${config}"
  fi

  if [[ "${pinned}" -eq 0 ]]; then
    _skip "no provider keys needed pinning"
  fi
}

# ── External module repos (vendor) ───────────────────────────────────────────
# Refresh the registered external module git repos (clone or pull) via the
# module manager — `devbot module install`. Harnesses are deliberately not
# updated here.
_update_external_modules() {
  _header_2 "External Modules"
  local module_tool="${DEV_BOT_ROOT}/src/tools/external-modules/tools/module.sh"
  if [[ ! -f "${module_tool}" ]]; then
    _skip "module manager not found — skipping external module refresh"
    return 0
  fi
  if bash "${module_tool}" install; then
    _ok "external modules refreshed"
  else
    _warn "external modules refresh reported issues — see output above"
  fi
}

# ── Reinit all registered projects ───────────────────────────────────────────
# After the update + pins, re-wire every registered project so the provider
# selection and new module wiring take effect. Skippable with
# DEV_BOT_UPDATE_SKIP_REINIT=1 (CI/sandbox).
_reinit_all_projects() {
  if [[ "${DEV_BOT_UPDATE_SKIP_REINIT:-}" == "1" ]]; then
    _skip "DEV_BOT_UPDATE_SKIP_REINIT=1 — skipping devbot reinit --all"
    return 0
  fi
  _header_2 "Reinit all registered projects"
  if bash "${DEV_BOT_ROOT}/bin/reinit.sh" --all; then
    _ok "devbot reinit --all completed"
  else
    _warn "devbot reinit --all reported issues — inspect the output above"
    return 1
  fi
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
  echo -e "  ${TEXT_BOLD}Prereqs:${TEXT_CLEAR} ${MODULE_PREREQ_PASSED:-0} passed, ${MODULE_PREREQ_FAILED:-0} failed, ${MODULE_PREREQ_SKIPPED:-0} without pre-reqs"
  echo
  echo -e "  ${TEXT_BOLD}Verify:${TEXT_CLEAR}"
  echo "    devbot update  (safe to re-run)"
  echo
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  local total_start=${SECONDS}
  local tool_count=0 tool_failed=0
  local module_count=0 module_failed=0

  _header_1 "DevBot Update"

  if ! _fetch_tags; then
    exit 1
  fi

  # Target: an explicitly requested tag (pin/downgrade) or the newest tag
  # (release-tracked update).
  local target="" explicit=0
  if [[ $# -gt 0 ]]; then
    target="$1"
    explicit=1
    if ! _ensure_tag_exists "${target}"; then
      exit 1
    fi
  else
    target="$(_newest_release)"
    if [[ -z "${target}" ]]; then
      _skip "No release tags found — nothing to update."
      exit 0
    fi
  fi

  local state
  state="$(_head_vs_tag "${target}")"
  case "${state}" in
    at)
      if [[ "${explicit}" -eq 1 ]]; then
        _ok "Already on ${target}."
      else
        _ok "Already on the latest version (${target})."
      fi
      exit 0
      ;;
    ahead)
      # Auto mode: ahead of the newest tag = dev line, nothing to update.
      # Explicit mode: the user asked for an older tag — move to it.
      if [[ "${explicit}" -eq 1 ]]; then
        _jump_to_release "${target}" || exit 1
      else
        _ok "Already on the latest version (${target})."
        exit 0
      fi
      ;;
    behind)
      _jump_to_release "${target}" || exit 1
      ;;
    diverged)
      local rebase_rc=0
      _rebase_onto_release "${target}" || rebase_rc=$?
      [[ "${rebase_rc}" -eq 2 ]] && exit 0
      [[ "${rebase_rc}" -eq 1 ]] && exit 1
      ;;
  esac

  # Only reached when the checkout moved onto the new release.
  _check_python3
  _check_flock
  _ensure_legacy_providers
  _update_dependencies

  _header_2 "Tools"
  _update_modules "${DEV_BOT_ROOT}/src/tools"
  tool_count="${MODULE_SCRIPT_COUNT:-0}"
  tool_failed="${MODULE_SCRIPT_FAILED:-0}"

  _header_2 "Agentic Modules"
  _run_module_prereqs
  _update_modules "${DEV_BOT_ROOT}/src/agentic"
  module_count="${MODULE_SCRIPT_COUNT:-0}"
  module_failed="${MODULE_SCRIPT_FAILED:-0}"

  _update_external_modules

  UPDATED="${tool_count}" FAILED="${tool_failed}"
  MODULE_UPDATED="${module_count}" MODULE_FAILED="${module_failed}"
  print_summary

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo

  # Final step: re-wire every registered project so the provider pins and any
  # new module wiring take effect.
  _reinit_all_projects
}

main "$@"
