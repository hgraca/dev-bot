#!/usr/bin/env bash
# ---
# description: Connect the argocd CLI to a cluster and list applications. Starts a port-forward when needed, authenticates with a token, password, or the initial admin secret, and returns a table or JSON.
# ---
# =============================================================================
# src/agentic/argocd/tools/argocd-start.mcp.sh
# CLI wrapper for scripts/argocd-start.sh.
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"argocd-start","timeoutMs":300000,"description":"Connect the argocd CLI to a cluster's Argo CD and list applications. Starts a port-forward to svc/argocd-server when the server is not already reachable, authenticates with --token (or ARGOCD_AUTH_TOKEN) or --password (it never reads Argo CD Secrets), and prints the app list as a table or with --json.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: [--context <ctx>] [--kubeconfig <file>] [--namespace <ns>] [--port <n>] [--no-forward] [--server <url>] --token <t> | --password <p> [--insecure] [--timeout <s>] [--stop-forward] [--json]"}},"required":["args"]}}
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

exec bash "${SCRIPT_DIR}/../scripts/argocd-start.sh" "$@"
