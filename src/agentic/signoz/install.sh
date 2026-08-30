#!/usr/bin/env bash
# src/agentic/signoz/install.sh
# Install SigNoz MCP server and agent skills.
#
# 1. Downloads the SigNoz MCP server binary from GitHub releases.
# 2. Extracts the binary and README into storage/signoz/bin/.
# 3. Installs SigNoz agent skills via npx into storage/signoz/skills/.
#
# Idempotent — skips if binary already present and skills already installed.
#
# GATE: Requires curl (or wget), tar, npx.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

STORAGE_DIR="$(_signoz_storage_dir)"
BIN_DIR="${STORAGE_DIR}/bin"
SKILLS_DIR="${STORAGE_DIR}/skills"

# ── Download helpers ───────────────────────────────────────────────────────────

_download_binary() {
  local archive_name="$1"
  local download_url="https://github.com/SigNoz/signoz-mcp-server/releases/latest/download/${archive_name}"

  mkdir -p "${BIN_DIR}"

  if command -v curl >/dev/null 2>&1; then
    _info "Downloading SigNoz MCP server (${download_url})..."
    curl -fsSL "${download_url}" 2>/dev/null | tar xz --strip-components=2 -C "${BIN_DIR}" 2>/dev/null
    return $?
  elif command -v wget >/dev/null 2>&1; then
    _info "Downloading SigNoz MCP server (${download_url})..."
    local tmpfile
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/devbot.XXXXXX")"
    if wget -q -O "${tmpfile}" "${download_url}" 2>/dev/null; then
      tar xzf "${tmpfile}" --strip-components=2 -C "${BIN_DIR}" 2>/dev/null
      rm -f "${tmpfile}"
      return $?
    fi
    rm -f "${tmpfile}"
    return 1
  else
    _error "Neither curl nor wget found — cannot download SigNoz MCP binary"
    return 1
  fi
}

_install_skills() {
  _info "Installing SigNoz agent skills via npx..."

  # Run npx skills add in non-interactive mode to a temp dir, then move to storage
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devbot.XXXXXX")"
  trap 'rm -rf "${tmpdir}"' EXIT

  # Create a minimal package.json so npx has a project context (prevents interactive prompts)
  printf '{"name":"signoz-skills-tmp","private":true}\n' > "${tmpdir}/package.json"

  # Run npx skills add from the temp dir (cwd-based, avoid --dir flag which may not exist)
  if (cd "${tmpdir}" && npx --yes skills add --yes SigNoz/agent-skills 2>&1) | sed 's/^/  /'; then
    _info "Skills fetched to temp dir. Moving to storage..."

    # Find where npx put the skills (typically node_modules or .skills)
    local installed_skills=""
    if [[ -d "${tmpdir}/.agents/skills" ]]; then
      installed_skills="${tmpdir}/.agents/skills"
    elif [[ -d "${tmpdir}/.agents" ]]; then
      installed_skills="${tmpdir}/.agents"
    elif [[ -d "${tmpdir}/.skills" ]]; then
      installed_skills="${tmpdir}/.skills"
    elif [[ -d "${tmpdir}/skills" ]]; then
      installed_skills="${tmpdir}/skills"
    elif [[ -d "${tmpdir}/node_modules" ]]; then
      # Some versions of skills CLI install into node_modules
      # Search for the actual skill directories
      installed_skills="${tmpdir}/node_modules"
    fi

    if [[ -n "${installed_skills}" && -d "${installed_skills}" ]]; then
      rm -rf "${SKILLS_DIR}"
      mkdir -p "${SKILLS_DIR}"
      cp -r "${installed_skills}/"* "${SKILLS_DIR}"/ 2>/dev/null || true
      _ok "Skills installed to ${SKILLS_DIR}"
    else
      _warn "Could not locate installed skills in temp dir. Contents:"
      ls -la "${tmpdir}" 2>/dev/null | sed 's/^/    /' || true
    fi
  else
    _warn "npx skills add failed — SigNoz skills may not be available."
    _warn "  Try manually: npx skills add SigNoz/agent-skills"
  fi

  # Clean up temp dir immediately and remove trap so it doesn't fire with stale variable reference
  rm -rf "${tmpdir}"
  trap - EXIT
}

# ── Main ───────────────────────────────────────────────────────────────────────

main() {
  echo
  _info "SigNoz (observability MCP server + agent skills)"

  local archive_name
  archive_name="$(_signoz_archive_name)"

  # ── Binary ───────────────────────────────────────────────────────────────────
  if [[ -x "${BIN_DIR}/signoz-mcp-server" ]]; then
    _skip "SigNoz MCP server binary already installed (${BIN_DIR}/signoz-mcp-server)"
  else
    _download_binary "${archive_name}" && _ok "SigNoz MCP server installed to ${BIN_DIR}" || _warn "Binary download failed."
    # Make binary executable if present
    if [[ -f "${BIN_DIR}/signoz-mcp-server" ]]; then
      chmod +x "${BIN_DIR}/signoz-mcp-server"
    fi
  fi

  # ── Skills ───────────────────────────────────────────────────────────────────
  if [[ -d "${SKILLS_DIR}" ]] && [[ -n "$(ls -A "${SKILLS_DIR}" 2>/dev/null)" ]]; then
    _skip "SigNoz agent skills already installed (${SKILLS_DIR}/)"
  else
    _install_skills
  fi
}

main
