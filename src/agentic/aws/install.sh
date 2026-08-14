#!/usr/bin/env bash
# src/agentic/aws/install.sh
# Install the AWS CLI v2 and uv, authenticate via `aws login`, configure the
# Agent Toolkit for AWS, and materialize the AWS agent rules into storage.
#
# Idempotent — skips anything already installed. Interactive auth steps run
# inline when stdin is a TTY; otherwise they print the exact command for the
# human and continue with the non-interactive parts.
#
# Skills are NOT handled here — the aws external-modules.json declaration is
# cloned/wired by the external-modules module during `devbot install`/`init`.
#
# GATE: This module must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# Resolve DEV_BOT_ROOT. functions.sh sources _shared which computes it one
# level too deep, so compute it here (respecting any pre-set value).
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
GLOBAL_CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
READ_JSONC="${MODULE_DIR}/../../_shared/read_jsonc.py"
SET_JSONC_KEY="${MODULE_DIR}/../../_shared/set_jsonc_key.py"

AWS_CLI_INSTALLER='https://awscli.amazonaws.com/v2/install.sh'
RULES_URL='https://raw.githubusercontent.com/aws/agent-toolkit-for-aws/refs/heads/main/rules/aws-agent-rules.md'
TOOLKIT_REGION='us-east-1'

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

# ── Region ─────────────────────────────────────────────────────────────────────
# NOTE: this function is called in command substitution ($(...)) — stdout MUST
# carry only the resolved region. All diagnostics go to stderr.
_resolve_region() {
  # 1. Environment variable
  if [[ -n "${AWS_REGION:-}" ]]; then
    echo "${AWS_REGION}"
    return
  fi

  # 2. Existing global config value
  local existing
  existing="$(python3 "${READ_JSONC}" "${GLOBAL_CONFIG}" aws_region 2>/dev/null || true)"
  if [[ -n "${existing}" && "${existing}" != "null" ]]; then
    echo "${existing}"
    return
  fi

  # 3. Prompt (interactive) or default
  if [[ ! -t 0 ]]; then
    echo -e "  ${TEXT_BOLD}${TEXT_ORANGE}⚠⚠  No TTY and no AWS_REGION/aws_region set — defaulting to us-east-1 ${TEXT_CLEAR}" >&2
    echo "us-east-1"
    return
  fi

  echo -e "\n  ${TEXT_BOLD}── Select default AWS Region ──${TEXT_CLEAR}" >&2
  echo "  1) us-east-1      (N. Virginia)" >&2
  echo "  2) us-east-2      (Ohio)" >&2
  echo "  3) us-west-2      (Oregon)" >&2
  echo "  4) eu-west-1      (Ireland)" >&2
  echo "  5) eu-central-1   (Frankfurt)" >&2
  echo "  6) ap-southeast-2 (Sydney)" >&2
  echo "  7) type a custom region" >&2
  local choice
  read -r -p "  Choose [1-7] (default: 1): " choice
  case "${choice}" in
    2) echo "us-east-2" ;;
    3) echo "us-west-2" ;;
    4) echo "eu-west-1" ;;
    5) echo "eu-central-1" ;;
    6) echo "ap-southeast-2" ;;
    7) local custom; read -r -p "  Region: " custom; echo "${custom:-us-east-1}" ;;
    *) echo "us-east-1" ;;
  esac
}

_set_region() {
  local region="$1"
  _info "Setting default AWS region to ${region}..."
  if aws configure set region "${region}"; then
    _ok "aws configure set region ${region}"
  else
    _warn "Could not set region via 'aws configure' — continuing"
  fi
  python3 "${SET_JSONC_KEY}" "${GLOBAL_CONFIG}" aws_region "\"${region}\"" >/dev/null
  _ok "aws_region=${region} written to .devbot.global.jsonc"
}

# ── Auth & toolkit ─────────────────────────────────────────────────────────────
_aws_login() {
  _header_3 "AWS Login"
  if [[ ! -t 0 ]]; then
    _warn "No interactive terminal — skipping 'aws login'."
    _notice "Run in your terminal: aws login --region ${REGION}"
    _notice "Credentials are valid 12 hours and renewable for 90 days without re-authenticating."
    return 1
  fi
  _step "Running 'aws login --region ${REGION}' — a browser window will open..."
  if aws login --region "${REGION}"; then
    _ok "AWS login complete"
    return 0
  fi
  _warn "aws login did not complete (browser closed or timed out). Re-run: aws login --region ${REGION}"
  return 1
}

_verify_identity() {
  if aws sts get-caller-identity &>/dev/null; then
    local who
    who="$(aws sts get-caller-identity 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("Account","?"), d.get("Arn","?"))' 2>/dev/null || echo 'authenticated')"
    _ok "AWS credentials working — ${who}"
    return 0
  fi
  _warn "aws sts get-caller-identity failed — run 'aws login' first"
  return 1
}

_configure_toolkit() {
  _header_3 "Agent Toolkit for AWS"
  if [[ ! -t 0 ]]; then
    _notice "Run in your terminal (one-time interactive wizard, ~30s):"
    _notice "  aws configure agent-toolkit --region ${TOOLKIT_REGION}"
    return 0
  fi
  if aws configure agent-toolkit --yes --region "${TOOLKIT_REGION}"; then
    _ok "Agent Toolkit configured (MCP + default skills for detected agents)"
  else
    _warn "agent-toolkit wizard needs an interactive terminal. Run: aws configure agent-toolkit --region ${TOOLKIT_REGION}"
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

  REGION="$(_resolve_region)"
  _set_region "${REGION}"

  if _aws_login; then
    _verify_identity || true
  fi

  _configure_toolkit
  _fetch_rules

  _ok "aws install complete — skills install via external-modules (devbot install/init)"
}

main "$@"
