#!/usr/bin/env bash
# =============================================================================
# src/agentic/kafka/update.sh
# Bump the kafka module's server to npm latest and rewrite the machine pin.
#
# The pin lives in the gitignored versions.env so the next install uses the new
# version; the shipped default in versions.env.dist is never touched, since a
# tracked file there would leave the release checkout dirty.
#
# The allowlist is what makes this module read-only, and `--allow-tools` ignores
# an unknown name with a warning rather than failing — so an upgrade that renames
# a tool would quietly shrink the surface the skill promises. Every name is
# therefore proved present in the installed version before the pin moves; a name
# that disappeared puts the previous version back.
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# Put <version> back after a failed move, and say plainly when that also fails:
# the launcher resolves the executable, not the pin, so an unvalidated binary
# left behind is a live surface with a reassuring pin beside it.
_revert_or_report() {
  local version="$1" reason="$2"
  _error "${reason} — reverting to ${version}"
  if npm install -g "${MCP_PACKAGE}@${version}" >/dev/null 2>&1; then
    _ok "reverted to ${version}; the machine is consistent again"
  else
    _error "revert to ${version} FAILED — the installed ${MCP_BINARY} is not validated; reinstall ${MCP_PACKAGE}@${version} by hand before using kafka"
  fi
  return 1
}

main() {
  _info "kafka — update"

  if ! command -v npm >/dev/null 2>&1; then
    _error "npm not found — cannot update ${MCP_PACKAGE}. Install Node.js >= 22.23.4 first."
    return 1
  fi

  local previous latest missing
  previous="${MCP_CONFLUENT_VERSION}"
  if ! latest="$(npm view "${MCP_PACKAGE}" version 2>/dev/null)" || [[ -z "${latest}" ]]; then
    _warn "npm view failed (offline?) — keeping the existing install and pin"
    return 0
  fi

  if ! npm install -g "${MCP_PACKAGE}@${latest}" >/dev/null 2>&1; then
    _error "npm install -g ${MCP_PACKAGE}@${latest} failed — check network / npm registry access."
    return 1
  fi

  if ! missing="$(_kafka_missing_tools)"; then
    _revert_or_report "${previous}" "${latest} tool list could not be read (${MCP_BINARY} --list-tools)"
    return 1
  fi
  if [[ -n "${missing}" ]]; then
    _revert_or_report "${previous}" "${latest} no longer advertises:${missing}"
    _warn "review ALLOWED_TOOLS before updating again"
    return 1
  fi

  _ok "${MCP_PACKAGE} updated: ${latest} (allowlist intact)"

  # The pin is machine-local (gitignored): a writer needs a live copy to rewrite.
  # The binary is already replaced here, so a pin write that fails must put the
  # binary back — otherwise the machine runs a version no pin names.
  if ! _devbot_versions_env_seed "${MODULE_DIR}"; then
    _revert_or_report "${previous}" "could not create ${MODULE_DIR}/versions.env"
    return 1
  fi
  # sed->tmp->mv (no bare `sed -i`: macOS requires a backup suffix).
  if ! sed "s/^MCP_CONFLUENT_VERSION=.*/MCP_CONFLUENT_VERSION=${latest}/" \
    "${MODULE_DIR}/versions.env" >"${MODULE_DIR}/versions.env.tmp" ||
    ! mv "${MODULE_DIR}/versions.env.tmp" "${MODULE_DIR}/versions.env"; then
    rm -f "${MODULE_DIR}/versions.env.tmp"
    _revert_or_report "${previous}" "could not write the pin to versions.env"
    return 1
  fi
  if ! grep -qx "MCP_CONFLUENT_VERSION=${latest}" "${MODULE_DIR}/versions.env"; then
    # Put the pin back before reverting: the binary is about to match
    # `${previous}` again, and a file naming `${latest}` would mislead the next
    # install into thinking the newer version is the one in place.
    sed "s/^MCP_CONFLUENT_VERSION=.*/MCP_CONFLUENT_VERSION=${previous}/" \
      "${MODULE_DIR}/versions.env" >"${MODULE_DIR}/versions.env.tmp" 2>/dev/null &&
      mv "${MODULE_DIR}/versions.env.tmp" "${MODULE_DIR}/versions.env" ||
      _warn "could not rewrite the pin back to ${previous} — check versions.env by hand"
    _revert_or_report "${previous}" "the pin in versions.env did not take the new version"
    return 1
  fi
  _ok "pin bumped to ${latest} (versions.env)"
}

main "$@"
