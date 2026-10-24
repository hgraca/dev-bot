#!/usr/bin/env bash
# =============================================================================
# src/agentic/datasources/init.sh
# Wire this project's SELECTED datasources into its harness.
#
# Datasources are declared once in .devbot.global.jsonc and opted into per
# project by name in .devbot.project.jsonc. For each selected name this script
# writes the harness's dynamic MCP manifest, pointing at the gateway's
# per-datasource toolset URL (http://127.0.0.1:18510/mcp/<name>).
#
# Scoping is by URL, not by the gateway: one container holds every source, so a
# project sees only the toolsets its manifest names. Deselected datasources are
# pruned, so removing one from the project config takes effect on the next init.
#
# Manifests are emitted rather than written into the harness config directly —
# modules stay harness-agnostic and the harness applies them (same contract as
# the jetbrains module). A config change needs a reinit to take effect, which
# the next bare `devbot` start performs automatically.
#
# Usage:
#   init.sh                         # init in current directory
#   init.sh /path/to/project        # init in specified project
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
# Shared helpers live beside this module, never under DEV_BOT_ROOT — which is
# overridden to a sandbox root in tests (see _devbot_get_disabled_modules).
READER="${MODULE_DIR}/../../_shared/read_jsonc.py"
REMOVE_KEY="${MODULE_DIR}/../../_shared/remove_mcp_key.py"

# Server names and manifest files are prefixed, so a datasource can never
# collide with a module-declared MCP server of the same name.
PREFIX="datasources-"

# Sidecar datasources are served by their own http listener rather than by the
# shared gateway, so their manifest URL carries the port render_compose.py
# allocated. Filled in main() from the catalogue; the same allocation the
# rendered compose uses, so the two cannot drift.
SIDECAR_PORTS="{}"

# ── helpers ───────────────────────────────────────────────────────────────────

# The URL this datasource's manifest points at: a sidecar's own listener, or its
# toolset on the shared gateway.
_datasources_url() {
  local name="$1" port
  port="$(python3 -c '
import json, sys
try:
    ports = json.loads(sys.argv[1])
except Exception:
    ports = {}
print(ports.get(sys.argv[2], ""))
' "${SIDECAR_PORTS}" "${name}" 2>/dev/null || true)"
  if [[ -n "${port}" ]]; then
    printf 'http://127.0.0.1:%s/mcp' "${port}"
  else
    printf '%s/%s' "$(_datasources_gateway_url)" "${name}"
  fi
}

# Write the dynamic MCP manifests for one datasource. opencode's shape is
# opencode-native (what _register_dynamic_mcps merges verbatim); claudecode's
# matches the .mcp.json contract. Both mirror the jetbrains module.
#
# The gateways are optional per project, so the opencode manifest ships the
# server disabled by default — one flag turns it on without a reinit. The
# claudecode entry keeps `true`: .mcp.json has no per-server on/off, and
# _wire_mcp reads `enabled` as a wire/don't-wire gate, so `false` there would
# silently drop the server from that harness.
_datasources_write_manifests() {
  local name="$1"
  local url server
  url="$(_datasources_url "${name}")"
  server="${PREFIX}${name}"

  if ! _datasources_harness_disabled "${PROJECT_DIR}" opencode; then
    local dir="${PROJECT_DIR}/.opencode"
    mkdir -p "${dir}"
    printf '{"%s": {"type": "remote", "url": "%s", "enabled": false}}\n' \
      "${server}" "${url}" > "${dir}/${PREFIX}${name}.mcp.json"
  fi

  if ! _datasources_harness_disabled "${PROJECT_DIR}" claudecode; then
    local dir="${PROJECT_DIR}/.claude"
    mkdir -p "${dir}"
    printf '{"mcpServers": {"%s": {"type": "http", "url": "%s", "enabled": true}}}\n' \
      "${server}" "${url}" > "${dir}/${PREFIX}${name}.mcp.json"
  fi
}

# Reconcile the opencode config with the selection. The harness merges dynamic
# manifests APPEND-ONLY into opencode.jsonc (merge_mcp_jsonc.py is
# insert/skip-exists) and nothing removes them, so deleting a manifest is not
# enough: the key stays live and the project keeps a server for a datasource it
# has removed. Scanning the CONFIG rather than the manifests also cleans up a
# key left behind by an earlier init. claudecode needs nothing — its .mcp.json
# is regenerated from scratch.
_datasources_reconcile_opencode() {
  local selected="$1" config="${PROJECT_DIR}/opencode.jsonc"
  [[ -f "${config}" ]] || return 0

  local key name
  for key in $(
    python3 "${READER}" "${config}" mcp 2>/dev/null |
      python3 -c '
import json, sys
try:
    print(" ".join(json.load(sys.stdin)))
except Exception:
    pass
' 2>/dev/null
  ); do
    case "${key}" in
      "${PREFIX}"*) ;;
      *) continue ;; # a server this module does not own
    esac
    name="${key#"${PREFIX}"}"
    if ! printf ' %s ' "${selected}" | grep -Fq " ${name} "; then
      python3 "${REMOVE_KEY}" "${config}" "${key}" \
        >/dev/null 2>&1 || true
      _skip "datasources — unregistered ${key} (no longer selected)"
    fi
  done
}

# Remove manifests for datasources no longer selected. Without this, dropping a
# datasource from the project config would leave its server registered forever.
_datasources_prune() {
  local dir="$1" selected="$2" file name
  [[ -d "${dir}" ]] || return 0

  for file in "${dir}/${PREFIX}"*.mcp.json; do
    [[ -e "${file}" ]] || continue
    name="$(basename "${file}")"
    name="${name#"${PREFIX}"}"
    name="${name%.mcp.json}"
    if ! printf ' %s ' "${selected}" | grep -Fq " ${name} "; then
      rm -f "${file}"
      _skip "datasources — pruned ${name} (no longer selected)"
    fi
  done
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  _header_3 "datasources init — $(basename "${PROJECT_DIR}")"

  # The manifest must point where the gateway will actually listen, and
  # `DATASOURCES_PORT` may live in the repo .env that bin/init.sh never reads.
  # Load it before any URL is built: a manifest on the default port while
  # compose binds the configured one is a server the client can never reach.
  _devbot_load_env

  local selected declared name
  selected="$(_datasources_selected "${PROJECT_DIR}")"
  declared="$(_datasources_declared)"
  SIDECAR_PORTS="$(_datasources_sidecar_ports "${PROJECT_DIR}")"

  for name in ${selected}; do
    if ! printf ' %s ' "${declared}" | grep -Fq " ${name} "; then
      # A typo would otherwise register a server that answers 200 and then a
      # JSON-RPC error — visible only at call time, never at connect time.
      _warn "datasources — '${name}' is selected but not declared in .devbot.global.jsonc"
    fi
  done

  if [[ -z "${selected}" ]]; then
    _skip "datasources — none selected in .devbot.project.jsonc"
  else
    for name in ${selected}; do
      _datasources_write_manifests "${name}"
      _ok "datasources — ${PREFIX}${name} -> $(_datasources_url "${name}")"
    done
  fi

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  if ! _datasources_harness_disabled "${PROJECT_DIR}" opencode; then
    _datasources_reconcile_opencode "${selected}"
    _datasources_prune "${PROJECT_DIR}/.opencode" "${selected}"
  fi
  if ! _datasources_harness_disabled "${PROJECT_DIR}" claudecode; then
    _datasources_prune "${PROJECT_DIR}/.claude" "${selected}"
  fi

  return 0
}

main "$@"
