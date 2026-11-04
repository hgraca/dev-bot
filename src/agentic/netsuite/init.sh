#!/usr/bin/env bash
# =============================================================================
# src/agentic/netsuite/init.sh
# Register this project's NetSuite MCP server.
#
# NetSuite's AI Connector endpoint is per-account, so its URL is built from
# `netsuite.account_id` (project over global) and emitted as a harness-native
# dynamic manifest rather than declared in a canonical mcp.json. The server is
# named `netsuite-<account>`: opencode keys MCP auth by server name, so one
# account per name lets production and a sandbox coexist.
#
# The server ships disabled (`netsuite.enabled`, default false): opencode keeps
# it wired but not started, so it is connected from the harness; claudecode
# omits a disabled server from .mcp.json, matching the per-server-enabled
# contract.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"
GLOBAL_CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
PROJECT_CONFIG="${PROJECT_DIR}/.devbot.project.jsonc"
READER="${MODULE_DIR}/../../_shared/read_jsonc.py"
REMOVE_KEY="${MODULE_DIR}/../../_shared/remove_mcp_key.py"

PREFIX="netsuite"
URL_SUFFIX="suitetalk.api.netsuite.com/services/mcp/v1/all"

# ── helpers ───────────────────────────────────────────────────────────────────

# One value of the `netsuite` config object. The project's value wins; the
# global one is the fallback. Booleans print as `true`/`false`.
_netsuite_config() {
  local key="$1" cfg value
  for cfg in "${PROJECT_CONFIG}" "${GLOBAL_CONFIG}"; do
    [[ -f "${cfg}" ]] || continue
    value="$(python3 "${READER}" "${cfg}" "${PREFIX}" 2>/dev/null |
      NETSUITE_KEY="${key}" python3 -c '
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = None
value = data.get(os.environ["NETSUITE_KEY"]) if isinstance(data, dict) else None
if isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, str) and value:
    print(value)
' 2>/dev/null || true)"
    if [[ -n "${value}" ]]; then
      printf '%s' "${value}"
      return 0
    fi
  done
  return 0
}

# Is a module (or harness) turned off for this project?
_netsuite_disabled() {
  _devbot_get_disabled_modules "${PROJECT_DIR}" |
    jq -e --arg m "$1" 'index($m) != null' >/dev/null 2>&1
}

# NetSuite's account-specific hostname lowercases the ID and turns every
# underscore into a hyphen — the form Company Information shows keeps both.
_netsuite_normalize_account() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '_' '-'
}

# Write both harness manifests. Dynamic manifests are harness-native (never
# translated), so each carries the shape its harness merges verbatim.
_netsuite_write_manifests() {
  local server="$1" enabled="$2" url="$3" dir

  if ! _netsuite_disabled opencode; then
    dir="${PROJECT_DIR}/.opencode"
    mkdir -p "${dir}"
    printf '{"%s": {"type": "remote", "url": "%s", "enabled": %s}}\n' \
      "${server}" "${url}" "${enabled}" > "${dir}/${server}.mcp.json"
  fi

  if ! _netsuite_disabled claudecode; then
    dir="${PROJECT_DIR}/.claude"
    mkdir -p "${dir}"
    printf '{"mcpServers": {"%s": {"type": "http", "url": "%s", "enabled": %s}}}\n' \
      "${server}" "${url}" "${enabled}" > "${dir}/${server}.mcp.json"
  fi
}

# Remove every netsuite artifact that is not the current server. The account can
# change, and the harness merges dynamic manifests append-only, so a dropped
# account must take its manifest and its live key with it.
_netsuite_prune() {
  local keep="$1" dir file name key

  for dir in "${PROJECT_DIR}/.opencode" "${PROJECT_DIR}/.claude"; do
    [[ -d "${dir}" ]] || continue
    for file in "${dir}/${PREFIX}"*.mcp.json; do
      [[ -e "${file}" ]] || continue
      name="$(basename "${file}" .mcp.json)"
      [[ "${name}" == "${keep}" ]] && continue
      rm -f "${file}"
    done
  done

  local config="${PROJECT_DIR}/opencode.jsonc"
  [[ -f "${config}" ]] || return 0
  for key in $(python3 "${READER}" "${config}" mcp 2>/dev/null |
    python3 -c '
import json, sys
try:
    print(" ".join(json.load(sys.stdin)))
except Exception:
    pass
' 2>/dev/null); do
    [[ "${key}" == "${PREFIX}" || "${key}" == "${PREFIX}-"* ]] || continue
    [[ "${key}" == "${keep}" ]] && continue
    python3 "${REMOVE_KEY}" "${config}" "${key}" >/dev/null 2>&1 || true
  done
}

# ── main ──────────────────────────────────────────────────────────────────────

if _netsuite_disabled "${PREFIX}"; then
  _netsuite_prune ""
  exit 0
fi

raw_account="$(_netsuite_config account_id)"

if [[ -z "${raw_account}" ]]; then
  _netsuite_prune ""
  _skip "netsuite — set netsuite.account_id in .devbot.global.jsonc (or .devbot.project.jsonc) to register the MCP server"
  exit 0
fi

if [[ ! "${raw_account}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  _netsuite_prune ""
  _warn "netsuite — '${raw_account}' is not a valid NetSuite account ID (letters, digits, '-' and '_' only)"
  exit 0
fi

account="$(_netsuite_normalize_account "${raw_account}")"
server="${PREFIX}-${account}"
enabled="$(_netsuite_config enabled)"
[[ "${enabled}" == "true" ]] || enabled="false"

_netsuite_prune "${server}"
_netsuite_write_manifests "${server}" "${enabled}" "https://${account}.${URL_SUFFIX}"

if [[ "${enabled}" == "true" ]]; then
  _ok "netsuite — MCP server '${server}' registered (enabled)"
else
  _ok "netsuite — MCP server '${server}' registered (disabled; connect it from the harness)"
fi
