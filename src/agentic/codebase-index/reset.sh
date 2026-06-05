#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-index/reset.sh
# Removes codebase-index files for a project: config files by default,
# or index data only when --full is passed (config preserved).
#
# Usage:
#   reset.sh /path/to/project            # remove config files only
#   reset.sh /path/to/project --full     # remove index data only (preserve config)
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="${1:-}"
FULL_RESET=false

# Parse optional second arg
case "${2:-}" in
  --full) FULL_RESET=true ;;
esac

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  echo "Usage: reset.sh <project_dir> [--full]" >&2
  exit 1
fi

_header_3 "Codebase Index Reset"

OPENCODE_CONFIG="${PROJECT_DIR}/.opencode/codebase-index.json"
CLAUDE_CONFIG="${PROJECT_DIR}/.claude/codebase-index.json"
OPENCODE_INDEX="${PROJECT_DIR}/.opencode/index"
CLAUDE_INDEX="${PROJECT_DIR}/.claude/index"

removed=0

if [[ "${FULL_RESET}" == "true" ]]; then
  # Full reset: remove index data only, preserve config files
  if [[ -d "${OPENCODE_INDEX}" ]]; then
    rm -rf "${OPENCODE_INDEX}"
    _ok "Removed .opencode/index/"
    removed=$((removed + 1))
  else
    _skip "No .opencode/index/"
  fi

  if [[ -d "${CLAUDE_INDEX}" ]]; then
    rm -rf "${CLAUDE_INDEX}"
    _ok "Removed .claude/index/"
    removed=$((removed + 1))
  else
    _skip "No .claude/index/"
  fi
else
  # Default: remove config files only
  if [[ -f "${OPENCODE_CONFIG}" ]]; then
    rm -f "${OPENCODE_CONFIG}"
    _ok "Removed .opencode/codebase-index.json"
    removed=$((removed + 1))
  else
    _skip "No .opencode/codebase-index.json"
  fi

  if [[ -f "${CLAUDE_CONFIG}" ]]; then
    rm -f "${CLAUDE_CONFIG}"
    _ok "Removed .claude/codebase-index.json"
    removed=$((removed + 1))
  else
    _skip "No .claude/codebase-index.json"
  fi
fi

if [[ ${removed} -eq 0 ]]; then
  _skip "Nothing to reset"
fi
