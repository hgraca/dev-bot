#!/usr/bin/env bash
# =============================================================================
# src/tools/devbot-cli/reset.sh
# Cleans up devbot_dir/ symlinks created by init.sh (agents, commands, skills,
# tools). Leaves memory/ and logs/ untouched.
#
# Usage:
#   reset.sh                    # reset in current directory
#   reset.sh /path/to/project   # reset in specified project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

PROJECT_DIR="${1:-$(pwd)}"
AGENTS_DIR="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")"

_info "Resetting ${AGENTS_DIR} symlinks..."

for subdir in agents commands skills tools; do
  dir="${AGENTS_DIR}/${subdir}"
  if [[ -d "${dir}" ]]; then
    find "${dir}" -type l -delete 2>/dev/null || true
    find "${dir}" -type d -empty -delete 2>/dev/null || true
  fi
done

_ok "${AGENTS_DIR} symlinks cleaned up"
