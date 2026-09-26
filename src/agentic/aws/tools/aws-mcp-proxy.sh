#!/usr/bin/env bash
# src/agentic/aws/tools/aws-mcp-proxy.sh
# AWS MCP proxy launcher — execs `uvx mcp-proxy-for-aws` pinned to a resolved
# AWS profile, with the resolved default AWS region injected as metadata.
#
# Profile precedence (first non-empty wins):
#   1. AWS_PROFILE environment variable
#   2. aws_profile in the project's .devbot.project.jsonc
#   3. aws_profile in the global .devbot.global.jsonc
#
# A profile is REQUIRED — IAM on that profile's role is the read-only boundary,
# so the ambient default identity is never used implicitly.
#
# Region precedence (first non-empty wins):
#   1. AWS_REGION environment variable
#   2. aws_region in the project's .devbot.project.jsonc
#   3. aws_region in the global .devbot.global.jsonc
#   4. `aws configure get region` (ambient ~/.aws/config)
#   5. us-east-1
#
# Auth is delegated to the proxy, which signs every request with the resolved
# profile's credentials written by `aws login` (see install.sh / up.sh).
#
# This script is symlinked into .opencode/aws-mcp-proxy.sh (and
# .claude/aws-mcp-proxy.sh) by init.sh and invoked by the MCP server.
# It must print nothing to stdout (MCP speaks JSON-RPC over stdio).

set -euo pipefail

# Symlink-safe: resolve through any symlink to this real file's directory.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${SCRIPT_DIR}/../../../.." && pwd)}"
READ_JSONC="${SCRIPT_DIR}/../../../_shared/read_jsonc.py"

PROXY="mcp-proxy-for-aws@1.6.4"
ENDPOINT="https://aws-mcp.us-east-1.api.aws/mcp"

_resolve_region() {
  # 1. Environment variable
  if [[ -n "${AWS_REGION:-}" ]]; then
    echo "${AWS_REGION}"
    return
  fi

  # 2. Project config (.devbot.project.jsonc)
  local r
  r="$(python3 "${READ_JSONC}" "${PWD}/.devbot.project.jsonc" aws_region 2>/dev/null || true)"
  if [[ -n "${r}" && "${r}" != "null" ]]; then
    echo "${r}"
    return
  fi

  # 3. Global config (.devbot.global.jsonc)
  r="$(python3 "${READ_JSONC}" "${DEV_BOT_ROOT}/.devbot.global.jsonc" aws_region 2>/dev/null || true)"
  if [[ -n "${r}" && "${r}" != "null" ]]; then
    echo "${r}"
    return
  fi

  # 4. Ambient AWS config (~/.aws/config)
  if command -v aws &>/dev/null; then
    r="$(aws configure get region 2>/dev/null || true)"
    if [[ -n "${r}" ]]; then
      echo "${r}"
      return
    fi
  fi

  # 5. Default
  echo "us-east-1"
}

_resolve_profile() {
  # 1. Environment variable
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    echo "${AWS_PROFILE}"
    return
  fi

  # 2. Project config (.devbot.project.jsonc)
  local p
  p="$(python3 "${READ_JSONC}" "${PWD}/.devbot.project.jsonc" aws_profile 2>/dev/null || true)"
  if [[ -n "${p}" && "${p}" != "null" ]]; then
    echo "${p}"
    return
  fi

  # 3. Global config (.devbot.global.jsonc)
  p="$(python3 "${READ_JSONC}" "${DEV_BOT_ROOT}/.devbot.global.jsonc" aws_profile 2>/dev/null || true)"
  if [[ -n "${p}" && "${p}" != "null" ]]; then
    echo "${p}"
    return
  fi
}

PROFILE="$(_resolve_profile)"
REGION="$(_resolve_region)"

# stdout must stay clean (MCP speaks JSON-RPC over stdio) — diagnose on stderr.
if [[ -z "${PROFILE}" ]]; then
  echo "aws-mcp: no AWS profile resolved." >&2
  echo "  Set AWS_PROFILE, or aws_profile in .devbot.project.jsonc / .devbot.global.jsonc." >&2
  echo "  IAM on that profile's role is the read-only boundary — the ambient" >&2
  echo "  default identity is deliberately not used." >&2
  exit 1
fi

# AWS_MCP_PROXY_PROFILES takes precedence over --profile in the proxy, which
# would silently unpin the profile. Surface it rather than let it win quietly.
if [[ -n "${AWS_MCP_PROXY_PROFILES:-}" ]]; then
  echo "aws-mcp: WARNING AWS_MCP_PROXY_PROFILES is set and takes precedence over" >&2
  echo "  --profile — the agent may switch profiles. Unset it to keep the pin." >&2
fi

exec uvx "${PROXY}" "${ENDPOINT}" \
  --profile "${PROFILE}" \
  --metadata "INSTALL_SOURCE=agent-toolkit-core" \
  --metadata "AWS_REGION=${REGION}"
