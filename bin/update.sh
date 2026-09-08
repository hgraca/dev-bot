#!/usr/bin/env bash
# =============================================================================
# bin/update.sh
# Updates the dev-bot agent kit and all its tools.
# 1. Git pull the project repo (stash local changes first)
# 2. Pin the legacy engine providers on existing installs (adds
#    codebase_index_provider=codebase-index / memory_search_provider=qmd to the
#    global config when absent, so an upgrade never silently flips engines)
# 3. Run each tool's update.sh under src/tools/<tool>/
# 4. Re-run `devbot reinit --all` so every registered project re-wires
#
# Safe to re-run at any time. Skip the final reinit with
# DEV_BOT_UPDATE_SKIP_REINIT=1.
#
# Usage:
#   bin/update.sh              # full update
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

# ── Git pull ──────────────────────────────────────────────────────────────────
_update_git() {
  _header_2 "Git update"

  local stashed=0

  if git -C "${DEV_BOT_ROOT}" diff --quiet && git -C "${DEV_BOT_ROOT}" diff --cached --quiet; then
    _ok "No local changes to stash."
  else
    _info "Stashing local changes..."
    if git -C "${DEV_BOT_ROOT}" stash push --include-untracked -m "update.sh auto-stash"; then
      stashed=1
      _ok "Changes stashed."
    else
      _warn "git stash failed — skipping rebase."
    fi
  fi

  if git -C "${DEV_BOT_ROOT}" pull --rebase; then
    _ok "Rebased onto origin/$(git -C "${DEV_BOT_ROOT}" rev-parse --abbrev-ref HEAD)."
  else
    _warn "git pull --rebase failed — resolve conflicts, then run 'git stash pop' if needed."
  fi

  if [[ "${stashed}" -eq 1 ]]; then
    _info "Restoring stashed changes..."
    if git -C "${DEV_BOT_ROOT}" stash pop; then
      _ok "Stash restored."
    else
      _warn "git stash pop failed — resolve conflicts manually."
    fi
  fi
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
  echo -e "  ${TEXT_BOLD}Updated:${TEXT_CLEAR} ${UPDATED:-0}"
  [[ "${FAILED:-0}" -gt 0 ]] && echo -e "  ${TEXT_BOLD}Failed :${TEXT_CLEAR} ${FAILED}"
  echo -e "  ${TEXT_BOLD}Module Updated:${TEXT_CLEAR} ${MODULE_UPDATED:-0}"
  [[ "${MODULE_FAILED:-0}" -gt 0 ]] && echo -e "  ${TEXT_BOLD}Failed :${TEXT_CLEAR} ${MODULE_FAILED}"
  echo -e "  ${TEXT_BOLD}Harness Updated:${TEXT_CLEAR} ${HARNESS_UPDATED:-0}"
  [[ "${HARNESS_FAILED:-0}" -gt 0 ]] && echo -e "  ${TEXT_BOLD}Failed :${TEXT_CLEAR} ${HARNESS_FAILED}"
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
  local harness_count=0 harness_failed=0

  _header_1 "DevBot Update"

  _update_git
  _check_python3
  _check_flock
  _update_dependencies

  # Pin the legacy engines on existing installs (before anything re-wires).
  _ensure_legacy_providers

  _header_2 "Tools"
  _update_modules "${DEV_BOT_ROOT}/src/tools"
  tool_count="${MODULE_SCRIPT_COUNT:-0}"
  tool_failed="${MODULE_SCRIPT_FAILED:-0}"

  _header_2 "Agentic Modules"
  _run_module_prereqs
  _update_modules "${DEV_BOT_ROOT}/src/agentic"
  module_count="${MODULE_SCRIPT_COUNT:-0}"
  module_failed="${MODULE_SCRIPT_FAILED:-0}"

  _header_2 "Harnesses"
  _update_modules "${DEV_BOT_ROOT}/src/harnesses"
  harness_count="${MODULE_SCRIPT_COUNT:-0}"
  harness_failed="${MODULE_SCRIPT_FAILED:-0}"

  _header_2 "External Modules"
  if [[ -d "${DEV_BOT_ROOT}/storage/external-agentic-modules" ]]; then
    _update_modules "${DEV_BOT_ROOT}/storage/external-agentic-modules"
  fi

  UPDATED="${tool_count}" FAILED="${tool_failed}"
  MODULE_UPDATED="${module_count}" MODULE_FAILED="${module_failed}"
  HARNESS_UPDATED="${harness_count}" HARNESS_FAILED="${harness_failed}"
  print_summary

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo

  # Final step: re-wire every registered project so the provider pins and any
  # new module wiring take effect.
  _reinit_all_projects
}

main "$@"
