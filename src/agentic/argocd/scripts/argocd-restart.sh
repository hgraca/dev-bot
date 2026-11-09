#!/usr/bin/env bash
# Restart the Argo CD server so a renewed TLS certificate is served, then verify.
set -euo pipefail

CONTEXT=""
NAMESPACE=argocd
WITH_REPO=0
DRY_RUN=0
JSON=0
VERIFY_HOST=""
TIMEOUT=300
TMP_CERT=""
KUBECONFIG_FILE=""

log()  { printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" >&2; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
usage_die() { printf 'FATAL: %s\n' "$*" >&2; printf 'Run with --help for usage.\n' >&2; exit 2; }

cleanup() {
  [[ -n "$TMP_CERT" ]] && rm -f "$TMP_CERT"
  return 0
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Restart the Argo CD server so a renewed TLS certificate is served.

  argocd-restart.sh --context <kube-context> [options]

  --context <name>      required; the cluster to act on
  --kubeconfig <file>   kubeconfig to use (default: $KUBECONFIG or ~/.kube/config)
  --namespace <name>    default: argocd
  --repo-server         also restart argocd-repo-server
  --verify-host <host>  fetch the served certificate and fail if it is expired
  --timeout <seconds>   rollout timeout, default 300
  --dry-run             print what would run, change nothing
  --json                machine-readable result on stdout (successful runs)
  -h, --help            this help

Exit codes: 0 ok, 1 failure, 2 usage.

Argo CD loads its server certificate from Secret argocd-server-tls at startup;
writing a renewed certificate into the secret does not reliably hot-reload it.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)      [[ -n "${2:-}" ]] || usage_die "--context needs a value"; CONTEXT="$2"; shift 2 ;;
    --kubeconfig)   [[ -n "${2:-}" ]] || usage_die "--kubeconfig needs a value"; KUBECONFIG_FILE="$2"; shift 2 ;;
    --namespace)    [[ -n "${2:-}" ]] || usage_die "--namespace needs a value"; NAMESPACE="$2"; shift 2 ;;
    --repo-server)  WITH_REPO=1; shift ;;
    --verify-host)  [[ -n "${2:-}" ]] || usage_die "--verify-host needs a value"; VERIFY_HOST="$2"; shift 2 ;;
    --timeout)      [[ -n "${2:-}" ]] || usage_die "--timeout needs a value"; TIMEOUT="$2"; shift 2 ;;
    --dry-run)      DRY_RUN=1; shift ;;
    --json)         JSON=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              usage_die "unknown option: $1" ;;
  esac
done

[[ -n "$CONTEXT" ]] || usage_die "--context is required (refusing to guess the cluster)"
[[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -ge 1 ]] || usage_die "--timeout must be a positive integer"
[[ -n "$KUBECONFIG_FILE" ]] && export KUBECONFIG="$KUBECONFIG_FILE"
for bin in kubectl date jq; do command -v "$bin" >/dev/null || die "$bin not found"; done
[[ -z "$VERIFY_HOST" ]] || command -v openssl >/dev/null || die "openssl not found (needed by --verify-host)"

TO=()
if command -v timeout >/dev/null 2>&1; then
  TO=(timeout 10)
elif command -v gtimeout >/dev/null 2>&1; then
  TO=(gtimeout 10)
fi

kubectl --context "$CONTEXT" cluster-info >/dev/null 2>&1 || die "cannot reach cluster for context '$CONTEXT'"
kubectl --context "$CONTEXT" auth can-i patch deployments -n "$NAMESPACE" >/dev/null 2>&1 \
  || die "identity for '$CONTEXT' cannot patch deployments in '$NAMESPACE'"

refs=(deployment/argocd-server)
[[ "$WITH_REPO" -eq 1 ]] && refs+=(deployment/argocd-repo-server)

refs_json=$(printf '%s\n' "${refs[@]}" | jq -R . | jq -s .)

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry run: would restart ${refs[*]}"
  if [[ "$JSON" -eq 1 ]]; then
    jq -n --arg c "$CONTEXT" --argjson refs "$refs_json" \
      '{status:"dry-run",context:$c,restarted:$refs}'
  fi
  exit 0
fi

for ref in "${refs[@]}"; do
  log "restarting $ref"
  kubectl --context "$CONTEXT" -n "$NAMESPACE" rollout restart "$ref" >/dev/null \
    || die "restart failed: $ref"
done

for ref in "${refs[@]}"; do
  log "waiting for $ref"
  kubectl --context "$CONTEXT" -n "$NAMESPACE" rollout status "$ref" --timeout="${TIMEOUT}s" >/dev/null \
    || die "rollout failed: $ref"
done

cert_json="null"
verified="false"
if [[ -n "$VERIFY_HOST" ]]; then
  pem=$(echo | "${TO[@]}" openssl s_client -connect "${VERIFY_HOST}:443" -servername "$VERIFY_HOST" 2>/dev/null \
    | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' || true)
  if [[ -z "$pem" ]]; then
    die "cannot read the certificate from $VERIFY_HOST:443"
  fi
  TMP_CERT=$(mktemp)
  printf '%s\n' "$pem" > "$TMP_CERT"
  subject=$(openssl x509 -in "$TMP_CERT" -noout -subject 2>/dev/null | sed 's/^subject=//')
  not_before=$(openssl x509 -in "$TMP_CERT" -noout -startdate 2>/dev/null | sed 's/^notBefore=//')
  not_after=$(openssl x509 -in "$TMP_CERT" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
  serial=$(openssl x509 -in "$TMP_CERT" -noout -serial 2>/dev/null | sed 's/^serial=//')
  if openssl x509 -in "$TMP_CERT" -checkend 0 -noout >/dev/null 2>&1; then
    expired="false"
  else
    expired="true"
  fi
  log "served: subject=$subject notAfter=$not_after serial=$serial"
  cert_json=$(jq -n --arg s "$subject" --arg nb "$not_before" --arg na "$not_after" \
    --arg sn "$serial" --argjson ex "$expired" \
    '{subject:$s,notBefore:$nb,notAfter:$na,serial:$sn,expired:$ex}')
  if [[ "$expired" == "true" ]]; then
    die "the served certificate is still expired ($not_after)"
  fi
  verified="true"
fi

log "restart complete"
if [[ "$JSON" -eq 1 ]]; then
  jq -n --arg c "$CONTEXT" --arg ns "$NAMESPACE" --argjson refs "$refs_json" \
    --argjson cert "$cert_json" --argjson ok "$verified" \
    '{status:"restarted",context:$c,namespace:$ns,restarted:$refs,certificateVerified:$ok,certificate:$cert}'
fi
