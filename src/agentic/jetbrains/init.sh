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

# Known JetBrains IDE process names
IDE_NAMES=(
  phpstorm idea idea64 pycharm pycharm64 webstorm webstorm64
  goland goland64 clion clion64 rider rider64 datagrip datagrip64
  rubymine rubymine64 dataspell dataspell64
)

# Default JetBrains MCP port. Used as a fallback when the IDE isn't running
# locally (e.g. inside a container with --network host, where localhost reaches
# the host's IDE). Override with JETBRAINS_PORT.
JETBRAINS_DEFAULT_PORT="${JETBRAINS_PORT:-64442}"

# ── helpers ───────────────────────────────────────────────────────────────────

# The project path the IDE serves MCP for. Override with JETBRAINS_PROJECT_PATH
# when the IDE lives on a different host (e.g. a container routing to the host's
# IDE needs the host-side path, not /app).
_project_path() {
  echo "${JETBRAINS_PROJECT_PATH:-${PROJECT_PATH}}"
}

# Probe a single port for the MCP SSE endpoint (GET /stream must answer with
# text/event-stream).
_probe_sse_port() {
  local port="$1"
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
' "${port}" 2>/dev/null
}

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
  if command -v ss >/dev/null 2>&1; then
    local filter="${ide_pid}"
    if [[ -z "${filter}" ]]; then
      filter=$(pgrep -d'|' -f "$(IFS='|'; echo "${IDE_NAMES[*]}")" 2>/dev/null || true)
      [[ -z "${filter}" ]] && return 1
      filter="(${filter})"
    fi
    ports=$(ss -tlnp 2>/dev/null \
      | awk -v f="${filter}" '$0 ~ f && /127\.0\.0\.1/ {for(i=1;i<=NF;i++) if($i~/:([0-9]+)$/){split($i,a,":"); print a[length(a)]}}' \
      | sort -nu)
  elif command -v lsof >/dev/null 2>&1; then
    ports=$(lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null \
      | awk -v pid="${ide_pid}" '$2==pid && /127\.0\.0\.1/ {split($9,a,":"); print a[length(a)]}' \
      | sort -nu)
  fi

  # Probe each port for SSE
  for port in ${ports}; do
    _probe_sse_port "${port}" && {
      echo "${port}"
      return 0
    }
  done

  return 1
}

_build_opencode_sse() {
  local port="$1"
  cat <<EOF
{"type":"remote","url":"http://127.0.0.1:${port}/stream","headers":{"IJ_MCP_SERVER_PROJECT_PATH":"$(_project_path)"},"enabled":true}
EOF
}

_build_opencode_stdio() {
  local ide_binary="$1" port="$2"
  cat <<EOF
{"type":"local","command":["${ide_binary}","stdioMcpServer"],"env":{"IJ_MCP_SERVER_PROJECT_PATH":"$(_project_path)","IJ_MCP_SERVER_PORT":"${port}"},"enabled":true}
EOF
}

_build_claude_sse() {
  local port="$1"
  cat <<EOF
{
  "type": "http",
  "url": "http://127.0.0.1:${port}/stream",
  "headers": {
    "IJ_MCP_SERVER_PROJECT_PATH": "$(_project_path)"
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
    "IJ_MCP_SERVER_PROJECT_PATH": "$(_project_path)",
    "IJ_MCP_SERVER_PORT": "${port}"
  },
  "enabled": true
}
EOF
}

# Write the opencode MCP def to a runtime manifest the opencode harness reads.
# Modules stay harness-agnostic: they emit a manifest, the harness registers it.
_write_opencode_manifest() {
  local mcp_def="$1"
  local manifest="${PROJECT_DIR}/.opencode/jetbrains.mcp.json"
  mkdir -p "$(dirname "${manifest}")"
  printf '{"jetbrains": %s}\n' "${mcp_def}" > "${manifest}"
}

# Write the claude MCP def to a runtime manifest the claudecode harness reads.
_write_claude_manifest() {
  local mcp_def="$1"
  local manifest="${PROJECT_DIR}/.claude/jetbrains.mcp.json"
  mkdir -p "$(dirname "${manifest}")"
  printf '{"mcpServers": {"jetbrains": %s}}\n' "${mcp_def}" > "${manifest}"
}

# ── main ───────────────────────────────────────────────────────────────────────

main() {
  _header_3 "JetBrains MCP Init"

  if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
    _fatal "Project directory '${1:-.}' does not exist."
    exit 1
  fi

  # ── 1. Detect the IDE + MCP port ───────────────────────────────────────────
  local ide_pid mcp_port
  ide_pid=$(_detect_ide_pid) || true

  if [[ -z "${ide_pid}" ]]; then
    _notice "No running JetBrains IDE detected locally."
    # Fallback: inside a container (--network host) the host's IDE MCP server
    # is reachable on the default port — probe it before giving up.
    if _probe_sse_port "${JETBRAINS_DEFAULT_PORT}"; then
      _info "Host JetBrains IDE MCP server reachable on port ${JETBRAINS_DEFAULT_PORT} (host-routed)."
      mcp_port="${JETBRAINS_DEFAULT_PORT}"
    else
      _error "No reachable JetBrains MCP server — no local IDE, and ${JETBRAINS_DEFAULT_PORT} did not answer."
      _warn "  Ensure your IDE is open and the MCP Server plugin is enabled, then re-run 'devbot init'."
      echo ""
      _info "To enable: Settings → Tools → MCP Server → Enable MCP Server"
      exit 0
    fi
  else
    mcp_port=$(_detect_mcp_port "${ide_pid}") || true
    if [[ -z "${mcp_port}" ]]; then
      _warn "IDE found (PID ${ide_pid}) but MCP server port not detected."
      _warn "  Ensure the MCP Server plugin is enabled in your IDE."
      _warn "  Then re-run 'devbot init'."
      echo ""
      _info "To enable: Settings → Tools → MCP Server → Enable MCP Server"
      exit 0
    fi
  fi

  _info "Detected MCP server on port ${mcp_port}${ide_pid:+ (IDE PID ${ide_pid})}"

  # ── 2. Primary: SSE config (connects directly to running IDE) ──────────────
  local method="SSE"

  # SSE is the simplest and most reliable — connects to the IDE's HTTP endpoint
  local oc_def
  oc_def=$(_build_opencode_sse "${mcp_port}")
  _info "Using SSE (port ${mcp_port})"

  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")

  # ── 2a. OpenCode: emit a runtime manifest (only if opencode is enabled) ────
  if echo "${disabled_raw}" | jq -e 'index("opencode") != null' >/dev/null 2>&1; then
    _skip "JetBrains MCP: opencode tool disabled — skipping OpenCode manifest"
  else
    _write_opencode_manifest "${oc_def}"
    _ok "JetBrains MCP manifest written for OpenCode (${method})"
  fi

  # ── 2b. Claude Code: emit manifest (only if claudecode tool is enabled) ────
  if echo "${disabled_raw}" | jq -e 'index("claudecode") != null' >/dev/null 2>&1; then
    _skip "JetBrains MCP: claudecode tool disabled — skipping Claude manifest"
  else
    local cc_entry
    cc_entry=$(_build_claude_sse "${mcp_port}")
    _write_claude_manifest "${cc_entry}"
    _ok "JetBrains MCP manifest written for Claude Code (${method})"
  fi

  echo ""
  _info "JetBrains MCP server configured. Restart your AI client for changes to take effect."
}

main "$@"
