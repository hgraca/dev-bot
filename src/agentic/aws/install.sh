#!/usr/bin/env bash
# src/agentic/aws/install.sh
# Install the AWS CLI v2 and uv, and materialize the AWS agent rules into
# storage.
#
# NON-INTERACTIVE by design: it never prompts, never opens a browser and never
# logs in. Connections authenticate with static credentials (see init.sh and
# tools/aws-mcp-proxy.sh), so there is nothing to authenticate here — the
# ambient identity is only reported, never changed.
#
# Idempotent — skips anything already installed.
#
# Skills are NOT handled here — the aws external-modules.json declaration is
# cloned/wired by the external-modules module during `devbot install`/`init`.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"

AWS_CLI_INSTALLER='https://awscli.amazonaws.com/v2/install.sh'
RULES_URL='https://raw.githubusercontent.com/aws/agent-toolkit-for-aws/refs/heads/main/rules/aws-agent-rules.md'

# ── PATH ───────────────────────────────────────────────────────────────────────
_ensure_path() {
  export PATH="$HOME/.local/bin:$PATH"

  local rc="$HOME/.bashrc"
  [[ "$(basename "${SHELL:-}")" == "zsh" ]] && rc="$HOME/.zshrc"

  if [[ -f "${rc}" ]] && ! grep -q 'PATH="\$HOME/.local/bin:\$PATH"' "${rc}" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${rc}"
    _log "Added \$HOME/.local/bin to ${rc}"
  fi
}

# ── Dependencies ───────────────────────────────────────────────────────────────
_install_unzip() {
  [[ "$(uname -s)" != "Linux" ]] && return 0
  if command -v unzip &>/dev/null; then
    _skip "unzip (required by AWS CLI installer)"
    return 0
  fi
  _info "Installing unzip..."
  if command -v dnf &>/dev/null; then
    sudo dnf install -y unzip
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y unzip
  else
    _warn "No supported package manager found — install unzip manually"
  fi
}

_install_uv() {
  if command -v uv &>/dev/null; then
    _skip "uv ($(uv --version 2>/dev/null | head -1 || echo 'installed'))"
    return 0
  fi
  _info "Installing uv (Python package manager — required for the AWS MCP proxy)..."
  if command -v curl &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh || {
      _error "uv installation failed. Install manually: curl -LsSf https://astral.sh/uv/install.sh | sh"
      exit 1
    }
    export PATH="$HOME/.local/bin:$PATH"
  elif command -v brew &>/dev/null; then
    brew install uv || { _error "uv installation failed."; exit 1; }
  else
    _error "uv is required but not installed. Install via: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
  fi
  _ok "uv installed"
}

_install_aws_cli() {
  if command -v aws &>/dev/null; then
    _skip "aws ($(aws --version 2>&1 | head -1))"
    return 0
  fi
  if ! command -v curl &>/dev/null; then
    _error "curl is required to install the AWS CLI"
    exit 1
  fi
  _info "Installing AWS CLI v2..."
  curl -fsSL "${AWS_CLI_INSTALLER}" | bash
  export PATH="$HOME/.local/bin:$PATH"
  if command -v aws &>/dev/null; then
    _ok "aws ($(aws --version 2>&1 | head -1))"
  else
    _warn "AWS CLI installed but 'aws' not on PATH — check \$HOME/.local/bin"
  fi
}

# ── Identity (report only) ─────────────────────────────────────────────────────
# Informational: connections carry their own static credentials, so a working
# ambient identity is neither required nor modified here.
_report_identity() {
  if ! command -v aws &>/dev/null; then
    return 0
  fi
  if aws sts get-caller-identity &>/dev/null; then
    local who
    who="$(aws sts get-caller-identity 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("Account","?"), d.get("Arn","?"))' 2>/dev/null || echo 'authenticated')"
    _ok "Ambient AWS identity — ${who}"
  else
    _notice "No working ambient AWS credentials. Connections use static credentials:"
    _notice "  declare them in .devbot.global.jsonc → aws_connections (see the devbot:aws skill)."
  fi
}

# ── Rules ──────────────────────────────────────────────────────────────────────
_fetch_rules() {
  local rules_dir="${DEV_BOT_ROOT}/storage/aws/rules"
  mkdir -p "${rules_dir}"
  _info "Fetching AWS agent rules..."
  if curl -fsSL "${RULES_URL}" -o "${rules_dir}/aws-agent-rules.md"; then
    _ok "Stored ${rules_dir}/aws-agent-rules.md"
  else
    _warn "Failed to fetch rules from ${RULES_URL}"
  fi
}

# ── main ───────────────────────────────────────────────────────────────────────
main() {
  _info "aws"

  if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    _error "Neither curl nor wget is available — cannot install AWS CLI"
    exit 1
  fi

  _install_unzip
  _install_uv
  _install_aws_cli
  _ensure_path
  _report_identity
  _fetch_rules

  _ok "aws install complete — skills install via external-modules (devbot install/init)"
}

main "$@"
