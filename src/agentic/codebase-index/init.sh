#!/usr/bin/env bash
# =============================================================================
# src/agentic/codebase-index/init.sh
# Copies codebase-index.dist.json to the project's .opencode/ as the
# per-project config. Idempotent — skips if already exists.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  Directory '${1:-.}' does not exist or cannot be resolved." >&2
  exit 1
fi

_upsert_opencode_plugin "${PROJECT_DIR}/opencode.jsonc" "opencode-codebase-index"

DIST_CONFIG="${MODULE_DIR}/codebase-index.dist.json"
TARGET="${PROJECT_DIR}/.opencode/codebase-index.json"

if [[ -f "${TARGET}" ]]; then
  _skip ".opencode/codebase-index.json already exists"
  exit 0
fi

if [[ ! -f "${DIST_CONFIG}" ]]; then
  echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  Dist config not found at ${DIST_CONFIG}" >&2
  exit 1
fi

mkdir -p "$(dirname "${TARGET}")"

ollama_api="${OLLAMA_LOCAL_API:-http://localhost:18434}"
# Append /v1 if not already present
[[ "${ollama_api}" != */v1 ]] && ollama_api="${ollama_api}/v1"

sed "s|__OLLAMA_API_URL__|${ollama_api}|g" "${DIST_CONFIG}" > "${TARGET}"
_ok ".opencode/codebase-index.json written"
