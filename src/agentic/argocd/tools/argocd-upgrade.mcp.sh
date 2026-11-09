#!/usr/bin/env bash
# ---
# description: Upgrade Argo CD in place from the official manifests with backup, verification and a rollback hint. Requires cluster-admin; pass --yes for non-interactive runs and --json for a machine-readable result.
# ---
# =============================================================================
# src/agentic/argocd/tools/argocd-upgrade.mcp.sh
# CLI wrapper for scripts/argocd-upgrade.sh.
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"argocd-upgrade","timeoutMs":3900000,"description":"Upgrade Argo CD in place from the official upstream manifests. Refuses to guess the cluster, requires CRD-patch permission, auto-detects non-HA vs HA, backs up config/workloads/Applications/CRDs, applies server-side, then verifies image tags, argocd-cm keys, ComparisonError and application health. Pass --dry-run to validate only, --yes for non-interactive runs (required non-interactively), and --json for a machine-readable result.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: <version> --context <ctx> [--dry-run] [--yes] [--rollback] [--allow-downgrade] [--allow-degraded] [--settle <seconds>] [--json] [--backup-dir <path>]"}},"required":["args"]}}
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

exec bash "${SCRIPT_DIR}/../scripts/argocd-upgrade.sh" "$@"
