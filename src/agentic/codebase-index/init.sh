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

# Plugin registration is declared in plugin.opencode.json and applied by the
# opencode harness init — this module init stays harness-agnostic.

# The config is host-specific: .opencode/codebase-index.json for the opencode
# harness, .claude/codebase-index.json for claudecode — the MCP launch passes
# --host opencode|claude and the server looks in the matching location. Write
# it for every enabled harness; skip the disabled ones so their dirs aren't
# recreated.
_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"

DIST_CONFIG="${MODULE_DIR}/codebase-index.dist.json"
if [[ ! -f "${DIST_CONFIG}" ]]; then
  echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  Dist config not found at ${DIST_CONFIG}" >&2
  exit 1
fi

ollama_api="${OLLAMA_LOCAL_API:-http://localhost:18434}"
# Append /v1 if not already present
[[ "${ollama_api}" != */v1 ]] && ollama_api="${ollama_api}/v1"

for harness in opencode claudecode; do
  if echo "${_disabled_raw}" | jq -e --arg h "${harness}" 'index($h) != null' >/dev/null 2>&1; then
    _skip "${harness} disabled — skipping its codebase-index config"
    continue
  fi

  # Harness dir: opencode → .opencode, claudecode → .claude (module name ≠ dir)
  case "${harness}" in
    opencode) harness_dir=".opencode" ;;
    claudecode) harness_dir=".claude" ;;
  esac

  target="${PROJECT_DIR}/${harness_dir}/codebase-index.json"
  if [[ -f "${target}" ]]; then
    _skip "${harness_dir}/codebase-index.json already exists"
    continue
  fi

  mkdir -p "$(dirname "${target}")"
  sed "s|__OLLAMA_API_URL__|${ollama_api}|g" "${DIST_CONFIG}" > "${target}"
  _ok "${harness_dir}/codebase-index.json written"
done

# ── Symlink the EPIPE-swallowing MCP wrapper (claudecode only) ───────────────
# The npx-launched server crashes with an unhandled EPIPE when the client
# closes stdio at session teardown (audit-19 FAIL). The shared wrapper
# (src/_shared/mcp-stdio-wrapper.js) swallows it. opencode integrates the
# package as a plugin (plugin.opencode.json) with its own launch path, so only
# the claudecode MCP launch needs the wrapper.
if echo "${_disabled_raw}" | jq -e 'index("claudecode") != null' >/dev/null 2>&1; then
  _skip "claudecode disabled — skipping codebase-index MCP wrapper symlink"
else
  DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
  mkdir -p "${PROJECT_DIR}/.claude"
  ln -sf "${DEV_BOT_ROOT}/src/_shared/mcp-stdio-wrapper.js" \
    "${PROJECT_DIR}/.claude/codebase-index-mcp-wrapper.js"
  _log "Symlinked .claude/codebase-index-mcp-wrapper.js"
fi
