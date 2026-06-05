#!/usr/bin/env bash
# =============================================================================
# src/agentic/qmd/reset.sh
# Resets QMD project data. Without --full this is a no-op (nothing to remove
# at config level). With --full, removes the project's QMD collection and
# context entry so reinit can register them fresh.
#
# Usage:
#   reset.sh /path/to/project            # no-op
#   reset.sh /path/to/project --full     # remove project collection + context
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

# Without --full there's nothing to do at config level (QMD has no per-project
# config files, only the collection registered during init).
if [[ "${FULL_RESET}" != "true" ]]; then
  exit 0
fi

# ── Full reset: remove project collection + context ─────────────────────────

_header_3 "QMD Reset"

# Resolve project name (same logic as init.sh)
PROJECT_NAME=""
local_config="${PROJECT_DIR}/.devbot.project.jsonc"
if [[ -f "${local_config}" ]]; then
  PROJECT_NAME=$(python3 -c "
import json
try:
    with open('${local_config}') as f:
        raw = f.read()
    stripped = '\n'.join(l for l in raw.split('\n') if not l.strip().startswith('//'))
    data = json.loads(stripped)
    print(data.get('project_name', ''))
except:
    print('')
" 2>/dev/null || echo "")
fi
PROJECT_NAME="${PROJECT_NAME:-$(basename "${PROJECT_DIR}")}"

if ! command -v qmd &>/dev/null; then
  _warn "qmd CLI not found — skipping QMD reset"
  exit 0
fi

# Remove project collection
if qmd collection show "${PROJECT_NAME}" >/dev/null 2>&1; then
  qmd collection remove "${PROJECT_NAME}"
  _ok "Removed QMD collection '${PROJECT_NAME}'"
else
  _skip "No QMD collection '${PROJECT_NAME}'"
fi

# Remove project context entry
if qmd context list 2>/dev/null | grep -qw "${PROJECT_NAME}"; then
  qmd context rm "qmd://${PROJECT_NAME}" 2>/dev/null || true
  _ok "Removed QMD context '${PROJECT_NAME}'"
else
  _skip "No QMD context '${PROJECT_NAME}'"
fi
