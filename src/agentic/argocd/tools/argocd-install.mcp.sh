#!/usr/bin/env bash
# ---
# description: Install or verify the argocd CLI binary (arch-aware, checksummed, no profile edits). Pass --version to pin a release and --json for a machine-readable result.
# ---
# =============================================================================
# src/agentic/argocd/tools/argocd-install.mcp.sh
# CLI wrapper for scripts/argocd-install.sh.
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"argocd-install","timeoutMs":300000,"description":"Install or verify the argocd CLI binary. Detects OS/architecture, downloads the pinned or latest release, verifies its checksum, and installs to $ARGOCD_BIN_DIR or ~/.local/bin without editing shell profiles unless --add-to-path is passed. Use --json for a machine-readable result.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: [--version <tag>] [--bin-dir <dir>] [--force] [--add-to-path] [--json]"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

exec bash "${SCRIPT_DIR}/../scripts/argocd-install.sh" "$@"
