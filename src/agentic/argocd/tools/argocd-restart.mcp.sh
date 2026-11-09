#!/usr/bin/env bash
# ---
# description: Restart the Argo CD server (and optionally repo-server) so a renewed TLS certificate is served, then verify the served certificate. Use after rotating argocd-server-tls.
# ---
# =============================================================================
# src/agentic/argocd/tools/argocd-restart.mcp.sh
# CLI wrapper for scripts/argocd-restart.sh.
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"argocd-restart","timeoutMs":1800000,"description":"Restart the Argo CD server deployment (and optionally argocd-repo-server) so a renewed TLS certificate is actually served, then wait for the rollout. With --verify-host it fetches the live certificate and reports subject, dates and serial, failing when the served certificate is still expired. Pass --json for a machine-readable result.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: --context <ctx> [--namespace <ns>] [--repo-server] [--verify-host <host>] [--timeout <seconds>] [--dry-run] [--json]"}},"required":["args"]}}
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

exec bash "${SCRIPT_DIR}/../scripts/argocd-restart.sh" "$@"
