#!/usr/bin/env bash
# =============================================================================
# src/agentic/chrome-devtools/serve.mcp.sh
# Launch the globally installed, pinned chrome-devtools-mcp server (T1.2).
#
# Symlinked into the project harness dirs by init.sh (tools-mcp pattern):
#   .opencode/chrome-devtools-serve.mcp.sh
#   .claude/chrome-devtools-serve.mcp.sh
#
# Why a launcher instead of npx:
#   * resolves the exact pinned binary — no `@latest` re-resolution, no
#     npm-exec / `sh -c` process chain, no per-session npx download churn;
#   * resolves by EXPLICIT prefix candidates only — a bare-name lookup would
#     pick up a stale system binary (e.g. /usr/bin/chrome-devtools-mcp 0.17.0,
#     which is not the npm package).
#
# EPIPE: execs `node <resolved .js>` through the shared wrapper so the
# NODE_OPTIONS epipe-guard preload applies (audit-19).
#
# stderr is captured by the mcp.json `bash -c` into .agents/logs/.
# GATE: This module must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

# Resolve the real module dir through the symlink (versions.env lives there).
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${SOURCE}" ]]; do
  DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
  SOURCE="$(readlink "${SOURCE}")"
  [[ "${SOURCE}" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
MODULE_DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHROME_DEVTOOLS_MCP_VERSION=""
[[ -f "${MODULE_DIR}/versions.env" ]] && source "${MODULE_DIR}/versions.env"

# ── Resolve the installed binary by explicit prefix candidates ───────────────
resolve_bin() {
  local bin="chrome-devtools-mcp" prefix
  prefix="$(npm config get prefix 2>/dev/null || true)"
  local -a candidates=("${HOME}/.npm-global/bin/${bin}" "/usr/local/bin/${bin}")
  [[ -n "${prefix}" ]] && candidates=("${prefix}/bin/${bin}" "${candidates[@]}")
  local cand
  for cand in "${candidates[@]}"; do
    if [[ -x "${cand}" ]]; then
      printf '%s' "${cand}"
      return 0
    fi
  done
  return 1
}

BIN="$(resolve_bin || true)"
if [[ -z "${BIN}" ]]; then
  echo "FATAL: chrome-devtools-mcp not installed. Run 'devbot install' (module chrome-devtools)." >&2
  exit 1
fi

# Deref the bin symlink to the real .js so we can exec `node <file>` — the
# wrapper's EPIPE guard only applies to node-basename children.
REAL="${BIN}"
while [[ -L "${REAL}" ]]; do
  LINK_DIR="$(cd -P "$(dirname "${REAL}")" && pwd)"
  REAL="$(readlink "${REAL}")"
  [[ "${REAL}" != /* ]] && REAL="${LINK_DIR}/${REAL}"
done

# Soft pin-drift guard: warn (in the MCP log) when the installed version is
# not the pinned one — happens after `devbot update` until reinstall finishes.
if [[ -n "${CHROME_DEVTOOLS_MCP_VERSION}" ]]; then
  INSTALLED_VERSION="$("${BIN}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [[ -n "${INSTALLED_VERSION}" && "${INSTALLED_VERSION}" != "${CHROME_DEVTOOLS_MCP_VERSION}" ]]; then
    echo "WARN: chrome-devtools-mcp ${INSTALLED_VERSION} installed but ${CHROME_DEVTOOLS_MCP_VERSION} pinned — run 'devbot update'." >&2
  fi
fi

# ── Discover a sandboxable Chromium (audit-25: macOS + Linux layouts) ────────
if [ "$(uname -s)" = "Darwin" ]; then
  CHROME_REAL="$(ls "$HOME"/.cache/ms-playwright/chromium-*/chrome-mac/Chromium.app/Contents/MacOS/Chromium 2>/dev/null | head -1)"
else
  CHROME_REAL="$(ls "$HOME"/.cache/ms-playwright/chromium-*/chrome-linux*/chrome 2>/dev/null | head -1)"
fi

# --isolated: give each instance its own temporary user-data-dir, removed when
# the browser closes. Without it every instance targets the server's default
# profile ($HOME/.cache/chrome-devtools-mcp/chrome-profile) and Chromium refuses
# to share one: a second concurrent instance dies with
#   Failed to create .../SingletonLock: File exists (17)
#   Aborting now to avoid profile corruption.
# (exit 21), so its browser never starts at all.
ARGS=(--headless --isolated)
if [[ -n "${CHROME_REAL}" ]]; then
  WRAP="${HOME}/.cache/ms-playwright/chrome-nosandbox"
  printf '#!/bin/bash\nexec "%s" --no-sandbox "$@"\n' "${CHROME_REAL}" > "${WRAP}"
  chmod +x "${WRAP}"
  ARGS+=(--executablePath "${WRAP}")
fi

if [[ "${REAL}" == *.js && -f "${REAL}" ]]; then
  exec node "${HARNESS_DIR}/chrome-devtools-mcp-wrapper.js" node "${REAL}" "${ARGS[@]}"
fi

# Fallback: real CLI is not a .js (e.g. a packaged binary build) — exec it as is.
exec node "${HARNESS_DIR}/chrome-devtools-mcp-wrapper.js" "${BIN}" "${ARGS[@]}"
