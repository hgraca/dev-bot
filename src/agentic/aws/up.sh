#!/usr/bin/env bash
# src/agentic/aws/up.sh
# Verify the machine's declared AWS connections before the harness starts.
#
# Runs on `devbot up` / `devbot` (auto-discovered by bin/up.sh, and skipped
# automatically when this module is disabled for the project).
#
# VERIFY-ONLY: it never logs in and never opens a browser. Connections carry
# static credentials (see tools/aws-mcp-proxy.sh), so each is checked with a real
# `sts get-caller-identity` — and against its account pin when it declares one.
# A failure is reported, never fatal: a broken connection must not block the boot.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
# Exported so the launcher resolves the same root (GLOBAL_CONFIG / .env).
export DEV_BOT_ROOT

GLOBAL_CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
READ_JSONC="${MODULE_DIR}/../../_shared/read_jsonc.py"
LAUNCHER="${MODULE_DIR}/tools/aws-mcp-proxy.sh"

# The connection names the machine declares (keys of the global catalogue).
_declared() {
  [[ -f "${GLOBAL_CONFIG}" ]] || return 0
  python3 "${READ_JSONC}" "${GLOBAL_CONFIG}" aws_connections 2>/dev/null |
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = None
print(" ".join(data) if isinstance(data, dict) else "")
' 2>/dev/null || true
}

main() {
  _info "aws — verifying connections"

  if ! command -v aws &>/dev/null; then
    _skip "aws CLI not installed — run 'devbot install' first"
    return 0
  fi

  local names
  names="$(_declared)"
  if [[ -z "${names}" ]]; then
    _skip "no aws_connections declared in .devbot.global.jsonc"
    return 0
  fi

  local name
  for name in ${names}; do
    # Reuse the launcher's own resolution (env XOR profile, ${VAR} loading,
    # account pin) so verification cannot drift from what the server will do.
    if bash "${LAUNCHER}" --check "${name}" >/dev/null 2>&1; then
      _ok "connection '${name}' — credentials valid"
    else
      _warn "connection '${name}' — credentials unusable (check its env references or profile)"
    fi
  done

  return 0
}

main "$@"
