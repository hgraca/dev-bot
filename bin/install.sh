#!/usr/bin/env bash
# =============================================================================
# bin/install.sh
# Idempotent installer for the dev-bot agent kit.
# Loops through all directories under src/tools/ and runs any install.sh found.
# Safe to re-run at any time — each tool's install.sh handles idempotency.
#
# Usage:
#   bin/install.sh              # full install
#
# Adding a new tool:
#   Create src/tools/<tool>/install.sh
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

# ── Prerequisite checks ───────────────────────────────────────────────────────
_check_prerequisites() {
  _header_2 "Prerequisites"

  local ok=true

  if ! command -v git >/dev/null 2>&1; then
    _error "git is required but not installed."
    ok=false
  fi

  if ! command -v docker >/dev/null 2>&1; then
    _error "docker is required but not installed."
    ok=false
  fi

  if ! command -v npm >/dev/null 2>&1; then
    _error "npm is required but not installed."
    ok=false
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    _error "python3 is required but not installed."
    ok=false
  fi

  if [[ "$(uname -s)" == "Darwin" ]] && ! command -v brew >/dev/null 2>&1; then
    _error "Homebrew is required on macOS but not installed."
    ok=false
  fi

  if [[ "${ok}" == false ]]; then
    echo
    _fatal "Missing prerequisites. Install them and re-run."
    echo "  • git:   https://git-scm.com/downloads"
    echo "  • docker: https://docs.docker.com/engine/install/"
    echo "  • npm:   https://nodejs.org/download/"
    echo "  • python3: https://www.python.org/downloads/"
    echo "  • homebrew: https://brew.sh"
    exit 1
  fi

  _ok "git:    $(git --version 2>/dev/null || echo 'found')"
  _ok "docker: $(docker --version 2>/dev/null || echo 'found')"
  _ok "npm:    $(npm --version 2>/dev/null || echo 'found')"
  _ok "python3: $(python3 --version 2>/dev/null || echo 'found')"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    _ok "brew: $(brew --version 2>/dev/null || echo 'found')"
  fi
}

# ── Environment file (.env from .env.dist) ─────────────────────────────────────
_setup_env() {
  _header_2 "Environment"

  local env="${DEV_BOT_ROOT}/.env"
  local dist="${DEV_BOT_ROOT}/.env.dist"

  if [[ ! -f "${dist}" ]]; then
    _skip ".env.dist not found — skipping"
    return 0
  fi

  if [[ -f "${env}" ]]; then
    _skip ".env already exists"
    return 0
  fi

  _info "Creating .env from .env.dist..."
  cp "${dist}" "${env}"
  _ok ".env created (edit it to add your API keys if you are using LiteLLM)"
}

# ── DevBot root config (.devbot.global.jsonc) ─────────────────────────────────────────
_setup_devbot_config() {
  _header_2 "DevBot Config"

  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"

  if [[ -f "${config}" ]]; then
    _skip ".devbot.global.jsonc already exists"
    return 0
  fi

  local dist="${DEV_BOT_ROOT}/.devbot.global.dist.jsonc"
  if [[ ! -f "${dist}" ]]; then
    _error "Distribution template not found at ${dist}"
    return 1
  fi
  _info "Writing .devbot.global.jsonc from $(basename "${dist}")..."
  cp "${dist}" "${config}"
  _ok ".devbot.global.jsonc created"
}

# ── npm dependencies (package.json) ──────────────────────────────────────────
_install_dependencies() {
  _header_2 "npm Dependencies"

  if [[ ! -f "${DEV_BOT_ROOT}/package.json" ]]; then
    _skip "No package.json found"
    return 0
  fi

  _info "Installing npm dependencies..."
  npm install --prefix "${DEV_BOT_ROOT}"
  _ok "npm dependencies installed"
}

# ── Summary ────────────────────────────────────────────────────────────────────
print_summary() {
  _header_2 "✔  DevBot install complete"

  echo -e "  ${TEXT_BOLD}Root  :${TEXT_CLEAR} ${DEV_BOT_ROOT}"
  echo -e "  ${TEXT_BOLD}Tools :${TEXT_CLEAR} ${TOOL_COUNT:-0} installed"
  echo -e "  ${TEXT_BOLD}Modules :${TEXT_CLEAR} ${MODULE_COUNT:-0} installed"
  echo -e "  ${TEXT_BOLD}Harnesses :${TEXT_CLEAR} ${HARNESS_COUNT:-0} installed"
  echo -e "  ${TEXT_BOLD}Prereqs:${TEXT_CLEAR} ${MODULE_PREREQ_PASSED:-0} passed, ${MODULE_PREREQ_FAILED:-0} failed, ${MODULE_PREREQ_SKIPPED:-0} without pre-reqs"
  echo
  echo -e "  ${TEXT_BOLD}Adding a tool:${TEXT_CLEAR}"
  echo "    Create src/tools/<tool>/install.sh"
  echo
  echo -e "  ${TEXT_BOLD}Adding an agentic module:${TEXT_CLEAR}"
  echo "    Create src/agentic/<module>/install.sh"
  echo
  echo -e "  ${TEXT_BOLD}Adding a harness:${TEXT_CLEAR}"
  echo "    Create src/harnesses/<name>/install.sh"
  echo
  echo -e "  ${TEXT_BOLD}Verify:${TEXT_CLEAR}"
  echo "    bin/install.sh  (idempotent — safe to re-run)"
  echo
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  local total_start=${SECONDS}
  local tool_count=0
  local module_count=0
  local harness_count=0

  _header_1 "DevBot Install"

  _setup_env
  _check_prerequisites
  _run_module_prereqs
  _setup_devbot_config
  _install_dependencies

  _header_2 "Tools"
  _install_modules "${DEV_BOT_ROOT}/src/tools"
  tool_count="${MODULE_SCRIPT_COUNT:-0}"

  _header_2 "Agentic Modules"
  _install_modules "${DEV_BOT_ROOT}/src/agentic"
  module_count="${MODULE_SCRIPT_COUNT:-0}"

  _header_2 "Harnesses"
  _install_modules "${DEV_BOT_ROOT}/src/harnesses"
  harness_count="${MODULE_SCRIPT_COUNT:-0}"

  _header_2 "External Modules"
  if [[ -d "${DEV_BOT_ROOT}/storage/external-agentic-modules" ]]; then
    _install_modules "${DEV_BOT_ROOT}/storage/external-agentic-modules"
  fi

  TOOL_COUNT="${tool_count}" MODULE_COUNT="${module_count}" HARNESS_COUNT="${harness_count}" print_summary

  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
