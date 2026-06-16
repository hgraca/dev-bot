#!/usr/bin/env bash
# src/agentic/signoz/update.sh
# Update SigNoz MCP server and agent skills to latest.
#
# 1. Re-downloads the SigNoz MCP server binary from GitHub releases.
# 2. Re-installs SigNoz agent skills via npx.
#
# GATE: Requires curl (or wget), tar, npx.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

STORAGE_DIR="$(_signoz_storage_dir)"
BIN_DIR="${STORAGE_DIR}/bin"
SKILLS_DIR="${STORAGE_DIR}/skills"

main() {
  echo
  _info "SigNoz (update)"

  # ── Binary ───────────────────────────────────────────────────────────────────
  local archive_name
  archive_name="$(_signoz_archive_name)"
  local download_url="https://github.com/SigNoz/signoz-mcp-server/releases/latest/download/${archive_name}"

  _info "Updating SigNoz MCP server binary..."

  if command -v curl &>/dev/null; then
    curl -fsSL "${download_url}" 2>/dev/null | tar xz -C "${BIN_DIR}" 2>/dev/null && _ok "Binary updated" || _warn "Binary download failed"
  elif command -v wget &>/dev/null; then
    local tmpfile
    tmpfile="$(mktemp)"
    if wget -q -O "${tmpfile}" "${download_url}" 2>/dev/null; then
      tar xzf "${tmpfile}" -C "${BIN_DIR}" 2>/dev/null && _ok "Binary updated" || _warn "Binary extraction failed"
      rm -f "${tmpfile}"
    else
      _warn "Binary download failed"
      rm -f "${tmpfile}"
    fi
  else
    _error "Neither curl nor wget found — cannot update SigNoz MCP binary"
  fi

  if [[ -f "${BIN_DIR}/signoz-mcp-server" ]]; then
    chmod +x "${BIN_DIR}/signoz-mcp-server"
  fi

  # ── Skills ───────────────────────────────────────────────────────────────────
  _info "Updating SigNoz agent skills..."

  # Re-run skills install to get latest
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT

  printf '{"name":"signoz-skills-tmp","private":true}\n' > "${tmpdir}/package.json"

  if (cd "${tmpdir}" && npx --yes skills add SigNoz/agent-skills 2>&1) | sed 's/^/  /'; then
    # Find installed skills
    local installed_skills=""
    for dir in "${tmpdir}/.skills" "${tmpdir}/skills" "${tmpdir}/node_modules"; do
      if [[ -d "${dir}" ]]; then installed_skills="${dir}"; break; fi
    done

    if [[ -n "${installed_skills}" ]]; then
      rm -rf "${SKILLS_DIR}"
      mkdir -p "${SKILLS_DIR}"
      cp -r "${installed_skills}/"* "${SKILLS_DIR}"/ 2>/dev/null || true
      _ok "Skills updated"
    else
      _warn "Could not locate installed skills"
    fi
  else
    _warn "npx skills add failed — SigNoz skills update skipped"
  fi
}

main
