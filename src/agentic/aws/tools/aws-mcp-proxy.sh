#!/usr/bin/env bash
# src/agentic/aws/tools/aws-mcp-proxy.sh
# AWS MCP proxy launcher — execs `uvx mcp-proxy-for-aws` with the resolved
# default AWS region injected as metadata.
#
# Region precedence (first non-empty wins):
#   1. AWS_REGION environment variable
#   2. aws_region in the project's .devbot.project.jsonc
#   3. aws_region in the global .devbot.global.jsonc
#   4. `aws configure get region` (ambient ~/.aws/config)
#   5. us-east-1
#
# Auth is delegated to the proxy via --skip-auth, which uses the ambient AWS
# credentials written by `aws login` (see install.sh / up.sh).
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

REGION="$(_resolve_region)"

exec uvx "${PROXY}" "${ENDPOINT}" \
  --skip-auth \
  --metadata "INSTALL_SOURCE=agent-toolkit-core" \
  --metadata "AWS_REGION=${REGION}"
