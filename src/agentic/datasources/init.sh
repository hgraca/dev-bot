#!/usr/bin/env bash
# =============================================================================
# src/agentic/datasources/init.sh
# Wire this project's SELECTED datasources into its harness.
#
# Datasources are declared once in .devbot.global.jsonc and opted into per
# project by name in .devbot.project.jsonc. For each selected name this script
# writes the harness's dynamic MCP manifest, pointing at the gateway's
# per-datasource toolset URL (http://127.0.0.1:18510/mcp/<name>), and carrying
# its MCP client timeout (`mcp_timeout_ms`, default 60s).
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

# The MCP client timeout (milliseconds) a manifest carries when its datasource
# does not set `mcp_timeout_ms`. opencode applies it to connecting, fetching
# tools and tool calls alike, so a long analytical query needs headroom here.
DEFAULT_MCP_TIMEOUT_MS=60000

# Sidecar datasources are served by their own http listener rather than by the
# shared gateway, so their manifest URL carries the port render_compose.py
# allocated. Filled in main() from the catalogue; the same allocation the
# rendered compose uses, so the two cannot drift.
SIDECAR_PORTS="{}"

# Per-datasource MCP client timeouts (milliseconds), filled in main() from the
# catalogue. The renderer validates the values, so a bad entry fails the init
# loudly instead of silently defaulting at call time.
MCP_TIMEOUTS="{}"

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

# Each datasource's MCP client timeout (milliseconds) from the catalogue. One
# validated read for the whole catalogue: render_tools_yaml.py rejects a
# non-positive or non-integer `mcp_timeout_ms` and names the datasource, so the
# failure surfaces here rather than as a silent default.
_datasources_mcp_timeouts() {
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc" catalogue
  [[ -f "${global_config}" ]] || { echo "{}"; return 0; }
  # An omitted `datasources` key is valid — the catalogue is optional. The
  # reader then prints nothing and exits 0, which must become an empty
  # catalogue rather than the renderer's "no catalogue on stdin" failure. A
  # parse error exits non-zero and still aborts through `set -e`.
  catalogue="$(python3 "${READER}" "${global_config}" datasources)"
  [[ -n "${catalogue}" ]] || { echo "{}"; return 0; }
  printf '%s' "${catalogue}" |
    python3 "${MODULE_DIR}/render_tools_yaml.py" --mcp-timeouts
}

# This datasource's MCP client timeout in milliseconds.
_datasources_mcp_timeout() {
  jq -r --arg name "${1}" --argjson default "${DEFAULT_MCP_TIMEOUT_MS}" \
    '.[$name] // $default' <<<"${MCP_TIMEOUTS}"
}

# Publish the datasource canonically; the selected harness applies it. The
# gateways are optional per project, so the server ships disabled — one flag
# turns it on without a reinit.
_datasources_write_manifests() {
  local name="$1"
  local url server timeout
  url="$(_datasources_url "${name}")"
  server="${PREFIX}${name}"
  timeout="$(_datasources_mcp_timeout "${name}")"
  _devbot_publish_runtime_mcp "${PROJECT_DIR}" "${server}" \
    "$(jq -nc --arg u "${url}" --argjson t "${timeout}" \
      "{($server): {type: \"http\", url: \$u, enabled: false, timeout: \$t}}")"
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
  MCP_TIMEOUTS="$(_datasources_mcp_timeouts)"

  for name in ${selected}; do
    if ! _list_has_word "${name}" "${declared}"; then
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
  local -a keep=()
  for name in ${selected}; do keep+=("${PREFIX}${name}"); done
  _devbot_prune_runtime_mcp "${PROJECT_DIR}" "${PREFIX}" ${keep[@]+"${keep[@]}"}
  _devbot_apply_runtime_mcps "${PROJECT_DIR}"

  return 0
}

main "$@"
