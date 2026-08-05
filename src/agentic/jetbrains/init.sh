#!/usr/bin/env bash
# =============================================================================
# src/agentic/jetbrains/init.sh
# Detects running JetBrains IDE and registers its MCP server in both
# opencode.jsonc and .mcp.json (Claude Code). Fully automatic — no prompts.
#
# Strategy:
#   1. Detect the IDE's MCP port via `ss` + stream endpoint probing
#   2. Register as remote (type: "remote" — "sse" not accepted by OpenCode)
#   3. If STDIO is preferred, uses the SAME detected port (not random)
#
# The IDE assigns the port; using a random port causes "Connection closed".
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_PATH="${PROJECT_DIR}"
MERGE_SCRIPT="${DEV_BOT_ROOT}/src/_shared/merge_mcp_jsonc.py"

# Known JetBrains IDE process names
IDE_NAMES=(
  phpstorm idea idea64 pycharm pycharm64 webstorm webstorm64
  goland goland64 clion clion64 rider rider64 datagrip datagrip64
  rubymine rubymine64 dataspell dataspell64
)

# ── helpers ───────────────────────────────────────────────────────────────────

_detect_ide_pid() {
  for name in "${IDE_NAMES[@]}"; do
    local pid
    pid=$(pgrep -x "${name}" 2>/dev/null | head -1) || true
    if [[ -n "${pid}" ]]; then
      echo "${pid}"
      return 0
    fi
  done
  return 1
}

_detect_ide_binary() {
  for name in "${IDE_NAMES[@]}"; do
    local binary
    binary=$(pgrep -a -x "${name}" 2>/dev/null | head -1 | awk '{print $2}')
    if [[ -n "${binary}" && -x "${binary}" ]]; then
      echo "${binary}"
      return 0
    fi
  done
  return 1
}

_detect_mcp_port() {
  # Probe IDE listen ports for the MCP SSE endpoint. Returns port or empty.
  local ide_pid="${1:-}"

  local ports
  if command -v ss &>/dev/null; then
    local filter="${ide_pid}"
    if [[ -z "${filter}" ]]; then
      filter=$(pgrep -d'|' -f "$(IFS='|'; echo "${IDE_NAMES[*]}")" 2>/dev/null || true)
      [[ -z "${filter}" ]] && return 1
      filter="(${filter})"
    fi
    ports=$(ss -tlnp 2>/dev/null \
      | awk -v f="${filter}" '$0 ~ f && /127\.0\.0\.1/ {for(i=1;i<=NF;i++) if($i~/:([0-9]+)$/){split($i,a,":"); print a[length(a)]}}' \
      | sort -nu)
  elif command -v lsof &>/dev/null; then
    ports=$(lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null \
      | awk -v pid="${ide_pid}" '$2==pid && /127\.0\.0\.1/ {split($9,a,":"); print a[length(a)]}' \
      | sort -nu)
  fi

  # Probe each port for SSE
  for port in ${ports}; do
    python3 -c '
import socket, sys
s = socket.socket()
s.settimeout(0.5)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
    s.send(b"GET /stream HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n")
    resp = s.recv(4096)
    if b"text/event-stream" in resp:
        sys.exit(0)
except Exception:
    pass
sys.exit(1)
' "${port}" 2>/dev/null && {
      echo "${port}"
      return 0
    }
  done

  return 1
}

_build_opencode_sse() {
  local port="$1"
  cat <<EOF
{"type":"remote","url":"http://127.0.0.1:${port}/stream","headers":{"IJ_MCP_SERVER_PROJECT_PATH":"${PROJECT_PATH}"},"enabled":true}
EOF
}

_build_opencode_stdio() {
  local ide_binary="$1" port="$2"
  cat <<EOF
{"type":"local","command":["${ide_binary}","stdioMcpServer"],"env":{"IJ_MCP_SERVER_PROJECT_PATH":"${PROJECT_PATH}","IJ_MCP_SERVER_PORT":"${port}"},"enabled":true}
EOF
}

_build_claude_sse() {
  local port="$1"
  cat <<EOF
{
  "type": "remote",
  "url": "http://127.0.0.1:${port}/stream",
  "headers": {
    "IJ_MCP_SERVER_PROJECT_PATH": "${PROJECT_PATH}"
  },
  "enabled": true
}
EOF
}

_build_claude_stdio() {
  local ide_binary="$1" port="$2"
  cat <<EOF
{
  "type": "stdio",
  "command": "${ide_binary}",
  "args": ["stdioMcpServer"],
  "env": {
    "IJ_MCP_SERVER_PROJECT_PATH": "${PROJECT_PATH}",
    "IJ_MCP_SERVER_PORT": "${port}"
  },
  "enabled": true
}
EOF
}

_register_opencode() {
  local mcp_def="$1"
  local result
  result=$(python3 "${MERGE_SCRIPT}" "${opencode_config}" "jetbrains" "${mcp_def}" 2>/dev/null || true)
  case "${result}" in
    INSERTED)     return 0 ;;
    SKIP_EXISTS)  return 2 ;;
    *)            return 1 ;;
  esac
}

_write_claude() {
  local entry_json="$1"
  local claude_config="${PROJECT_DIR}/.mcp.json"

  if [[ -f "${claude_config}" ]]; then
    if python3 -c "import json; d=json.load(open('${claude_config}')); exit(0 if 'jetbrains' in d.get('mcpServers',{}) else 1)" 2>/dev/null; then
      return 2
    fi
    local tmp
    tmp=$(mktemp)
    python3 -c "
import json
with open('${claude_config}') as f:
    cfg = json.load(f)
cfg.setdefault('mcpServers', {})['jetbrains'] = json.loads('''${entry_json}''')
with open('${tmp}', 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
" && mv "${tmp}" "${claude_config}"
  else
    cat > "${claude_config}" <<EOF
{
  "mcpServers": {
    "jetbrains": ${entry_json}
  }
}
EOF
  fi
  return 0
}

# ── main ───────────────────────────────────────────────────────────────────────

main() {
  _header_3 "JetBrains MCP Init"

  if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
    _error "Project directory '${1:-.}' does not exist."
    exit 1
  fi

  # ── Find opencode config ────────────────────────────────────────────────────
  local opencode_config=""
  if [[ -f "${PROJECT_DIR}/opencode.jsonc" ]]; then
    opencode_config="${PROJECT_DIR}/opencode.jsonc"
  elif [[ -f "${PROJECT_DIR}/opencode.json" ]]; then
    opencode_config="${PROJECT_DIR}/opencode.json"
  fi

  # ── 1. Detect the IDE + MCP port ───────────────────────────────────────────
  local ide_pid
  ide_pid=$(_detect_ide_pid) || true

  if [[ -z "${ide_pid}" ]]; then
    _warn "No running JetBrains IDE detected."
    _warn "  Ensure your IDE is open and the MCP Server plugin is enabled."
    _warn "  Then re-run 'devbot init' (or 'devbot up')."
    echo ""
    _info "To enable: Settings → Tools → MCP Server → Enable MCP Server"
    exit 0
  fi

  local mcp_port
  mcp_port=$(_detect_mcp_port "${ide_pid}") || true

  if [[ -z "${mcp_port}" ]]; then
    _warn "IDE found (PID ${ide_pid}) but MCP server port not detected."
    _warn "  Ensure the MCP Server plugin is enabled in your IDE."
    _warn "  Then re-run 'devbot init'."
    echo ""
    _info "To enable: Settings → Tools → MCP Server → Enable MCP Server"
    exit 0
  fi

  _info "Detected MCP server on port ${mcp_port} (IDE PID ${ide_pid})"

  # ── 2. Primary: SSE config (connects directly to running IDE) ──────────────
  local method="SSE"

  # SSE is the simplest and most reliable — connects to the IDE's HTTP endpoint
  local oc_def
  oc_def=$(_build_opencode_sse "${mcp_port}")
  _info "Using SSE (port ${mcp_port})"

  # ── 2a. OpenCode registration (always) ─────────────────────────────────────
  if [[ -n "${opencode_config}" ]]; then
    local oc_result=0
    set +e; _register_opencode "${oc_def}"; oc_result=$?; set -e
    case ${oc_result} in
      0) _ok "JetBrains MCP registered in opencode.jsonc (${method})" ;;
      2) _skip "JetBrains MCP already registered in opencode.jsonc" ;;
      *) _error "Failed to register JetBrains MCP in opencode.jsonc" ;;
    esac
  else
    _warn "No opencode.jsonc/json found — skipping OpenCode MCP registration."
  fi

  # ── 2b. Claude Code registration (only if claudecode tool is enabled) ──────
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  if echo "${disabled_raw}" | python3 -c "import json,sys; tools=json.loads(sys.stdin.read()); sys.exit(0 if 'claudecode' in tools else 1)" 2>/dev/null; then
    _skip "JetBrains MCP: claudecode tool disabled — skipping .mcp.json"
  else
    local cc_entry
    cc_entry=$(_build_claude_sse "${mcp_port}")
    local cc_result=0
    set +e; _write_claude "${cc_entry}"; cc_result=$?; set -e
    case ${cc_result} in
      0) _ok "JetBrains MCP written to .mcp.json (Claude Code, ${method})" ;;
      2) _skip "JetBrains MCP already in .mcp.json" ;;
      *) _error "Failed to write JetBrains MCP to .mcp.json" ;;
    esac
  fi

  echo ""
  _info "JetBrains MCP server configured. Restart your AI client for changes to take effect."
}

main "$@"
