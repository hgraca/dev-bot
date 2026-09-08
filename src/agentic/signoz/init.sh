#!/usr/bin/env bash
# src/agentic/signoz/init.sh
# Set up SigNoz in a project:
#   1. Symlink the MCP binary from devbot storage into each ENABLED harness dir
#      (.opencode/signoz-mcp-server and .claude/signoz-mcp-server)
#   2. Symlink agent skills from devbot storage to project's .opencode/skills/signoz/
#
# MCP auto-registration is handled by the harness inits from the single
# canonical manifest (src/agentic/signoz/mcp.json): the command resolves
# {harness-dir}/signoz-mcp-server to the symlink created in step 1, and the
# SIGNOZ_API_KEY env comes from {env:SIGNOZ_AUTH_TOKEN} — resolved natively by
# opencode at launch, and by the claudecode adapter at registration (.mcp.json
# cannot interpolate).
#
# Idempotent — safe to re-run.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
#
# GATE: Must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

STORAGE_DIR="$(_signoz_storage_dir)"
BIN_DIR="${STORAGE_DIR}/bin"
SKILLS_DIR="${STORAGE_DIR}/skills"

_header_3 "SigNoz Init"

# ── Validation ─────────────────────────────────────────────────────────────────

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "Project directory '${1:-.}' does not exist."
  exit 1
fi

if [[ ! -x "${BIN_DIR}/signoz-mcp-server" ]]; then
  _warn "SigNoz MCP binary not found at ${BIN_DIR}/signoz-mcp-server"
  _warn "  Run 'devbot install' first to download the binary."
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_DIR}")"
_disabled_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"

# ── Per-harness MCP binary symlink ─────────────────────────────────────────────
# Registration comes from the canonical mcp.json ({harness-dir} token), so the
# binary must exist in every enabled harness dir. Skills are opencode-only.

_link_mcp_binary() {
  local harness_dir="$1" # .opencode | .claude
  local bin_symlink="${PROJECT_DIR}/${harness_dir}/signoz-mcp-server"

  mkdir -p "${PROJECT_DIR}/${harness_dir}"
  if [[ -L "${bin_symlink}" ]]; then
    _skip "MCP binary already symlinked: ${harness_dir}/signoz-mcp-server"
  elif [[ -f "${bin_symlink}" ]]; then
    _warn "${harness_dir}/signoz-mcp-server exists but is not a symlink — replacing."
    rm -f "${bin_symlink}"
    ln -sf "${BIN_DIR}/signoz-mcp-server" "${bin_symlink}"
    _ok "MCP binary symlinked to ${harness_dir}/signoz-mcp-server"
  else
    ln -sf "${BIN_DIR}/signoz-mcp-server" "${bin_symlink}"
    _ok "MCP binary symlinked: ${harness_dir}/signoz-mcp-server → storage/signoz/bin/signoz-mcp-server"
  fi
}

if echo "${_disabled_raw}" | jq -e 'index("opencode") != null' >/dev/null 2>&1; then
  _skip "opencode disabled — skipping .opencode wiring"
else
  _link_mcp_binary ".opencode"

  # ── Agent skills (opencode-only) ────────────────────────────────────────────
  SKILLS_SYMLINK="${PROJECT_DIR}/.opencode/skills/signoz"

  if [[ -L "${SKILLS_SYMLINK}" ]]; then
    _skip "SigNoz skills already symlinked: .opencode/skills/signoz"
  elif [[ -d "${SKILLS_SYMLINK}" ]]; then
    _warn ".opencode/skills/signoz exists but is not a symlink — replacing."
    rm -rf "${SKILLS_SYMLINK}"
    ln -sf "${SKILLS_DIR}" "${SKILLS_SYMLINK}"
    _ok "SigNoz skills symlinked: .opencode/skills/signoz"
  elif [[ -d "${SKILLS_DIR}" ]] && [[ -n "$(ls -A "${SKILLS_DIR}" 2>/dev/null)" ]]; then
    mkdir -p "$(dirname "${SKILLS_SYMLINK}")"
    ln -sf "${SKILLS_DIR}" "${SKILLS_SYMLINK}"
    _ok "SigNoz skills symlinked: .opencode/skills/signoz → storage/signoz/skills"
  else
    _warn "SigNoz skills not found at ${SKILLS_DIR} — skipping skills wiring."
    _warn "  Run 'devbot install' first to download the skills."
  fi
fi

if echo "${_disabled_raw}" | jq -e 'index("claudecode") != null' >/dev/null 2>&1; then
  _skip "claudecode disabled — skipping .claude MCP binary wiring"
else
  _link_mcp_binary ".claude"
fi

_log "SigNoz init complete for ${PROJECT_NAME}"

cat <<'EOF'

  SigNoz MCP server wired into every enabled harness.
  Auto-registered by the harness inits from src/agentic/signoz/mcp.json.
  Auth env (SIGNOZ_URL, SIGNOZ_API_KEY, SIGNOZ_SSL_VERIFY, LOG_LEVEL) lives in
  that manifest's "env" block. SIGNOZ_API_KEY is set from the SIGNOZ_AUTH_TOKEN
  environment variable via {env:SIGNOZ_AUTH_TOKEN}:
    - opencode resolves it natively at launch
    - claudecode resolves it at registration (.mcp.json cannot interpolate);
      if SIGNOZ_AUTH_TOKEN is unset at init the key is omitted with a warning
EOF
