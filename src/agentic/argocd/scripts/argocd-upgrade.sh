#!/usr/bin/env bash
# Upgrade Argo CD from the official manifests.
# Run with --help for usage.
set -euo pipefail
umask 077

NAMESPACE=argocd
VERSION=""
CONTEXT=""
BACKUP_DIR=""
DRY_RUN=0
ASSUME_YES=0
ALLOW_DOWNGRADE=0
ALLOW_DEGRADED=0
ROLLBACK=0
JSON=0
SETTLE=60
KUBECONFIG_FILE=""

RESULT_STATUS="failed"
RESULT_APPLIED=0
PROBLEMS=""
SERVER=""
MODE=""
CURRENT=""

emit_json() {
  local rc=$?
  if [[ "$JSON" -eq 1 ]] && command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg context "$CONTEXT" --arg server "$SERVER" --arg mode "$MODE" \
      --arg from "$CURRENT" --arg to "$VERSION" --arg backup "$BACKUP_DIR" \
      --arg status "$RESULT_STATUS" --arg problems "$PROBLEMS" \
      --argjson applied "$RESULT_APPLIED" --argjson exitCode "$rc" \
      '{context:$context,server:$server,mode:$mode,from:$from,to:$to,backup:$backup,status:$status,applied:$applied,problems:$problems,exitCode:$exitCode}' \
      || true
  fi
  exit "$rc"
}
trap emit_json EXIT

log()  { local line; line="$(date -u +%H:%M:%SZ) $*"; if [[ "$JSON" -eq 1 ]]; then printf '%s\n' "$line" >&2; else printf '%s\n' "$line"; fi; }
warn() { printf 'WARN: %s\n' "$*" >&2; PROBLEMS="${PROBLEMS}WARN: $*"$'\n'; }
err()  { printf 'ERROR: %s\n' "$*" >&2; PROBLEMS="${PROBLEMS}ERROR: $*"$'\n'; }
die()  { printf 'FATAL: %s\n' "$*" >&2; PROBLEMS="${PROBLEMS}FATAL: $*"$'\n'; exit 1; }
preflight_die() { printf 'FATAL: %s\n' "$*" >&2; PROBLEMS="${PROBLEMS}FATAL: $*"$'\n'; exit 2; }
usage_die() { printf 'FATAL: %s\n' "$*" >&2; PROBLEMS="${PROBLEMS}FATAL: $*"$'\n'; printf 'Run with --help for usage.\n' >&2; exit 2; }

clean_list() {
  jq '{apiVersion:"v1",kind:"List",items:[.items[]|del(
    .metadata.resourceVersion,.metadata.uid,.metadata.creationTimestamp,
    .metadata.generation,.metadata.managedFields,.metadata.selfLink,.status)]}'
}

info_stream() {
  if [[ "$JSON" -eq 1 ]]; then cat >&2; else cat; fi
}

redact_configmap_credentials() {
  jq '.items |= map(
    if .kind == "ConfigMap"
    then .data |= with_entries(
      if (.key == "dex.config" or .key == "repositories" or .key == "repository.credentials")
      then .value = "REDACTED" else . end)
    else . end)'
}

usage() {
  cat <<'EOF'
Upgrade Argo CD in place from the official manifests.

  argocd-upgrade.sh <version> --context <kube-context> [options]

  <version>             required, e.g. v3.6.1
  --context <name>      required; the script refuses to guess a cluster
  --kubeconfig <file>   kubeconfig to use (default: $KUBECONFIG or ~/.kube/config)
  --dry-run             server-side dry run only, no changes, no backup
  --yes                 skip the interactive confirmation (for automation)
  --rollback            allow a downgrade; prints how rollback really behaves
  --allow-downgrade     same intent for a non-rollback downgrade
  --allow-degraded      do not fail when an application worsens (lost apps still fail)
  --settle <seconds>    wait before the diff check, default 60 (0 skips)
  --json                machine-readable result on stdout (logs go to stderr)
  --backup-dir <path>   default: ./argocd-backup-<context>-<timestamp>
  -h, --help            this help

Exit codes: 0 ok, 1 apply or verification failed, 2 usage/preflight, 3 aborted.
Namespace fixed: upstream RBAC hardcodes argocd.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      [[ -n "${2:-}" ]] || usage_die "--context needs a value"
      CONTEXT="$2"; shift 2 ;;
    --backup-dir)
      [[ -n "${2:-}" ]] || usage_die "--backup-dir needs a value"
      BACKUP_DIR="$2"; shift 2 ;;
    --kubeconfig)
      [[ -n "${2:-}" ]] || usage_die "--kubeconfig needs a value"
      KUBECONFIG_FILE="$2"; shift 2 ;;
    --settle)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || usage_die "--settle needs a number of seconds"
      SETTLE="$2"; shift 2 ;;
    --dry-run)         DRY_RUN=1; shift ;;
    --yes|-y)          ASSUME_YES=1; shift ;;
    --rollback)        ROLLBACK=1; ALLOW_DOWNGRADE=1; shift ;;
    --allow-downgrade) ALLOW_DOWNGRADE=1; shift ;;
    --allow-degraded)  ALLOW_DEGRADED=1; shift ;;
    --json)            JSON=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    -*)                usage_die "unknown option: $1" ;;
    *)                 [[ -z "$VERSION" ]] || usage_die "unexpected argument: $1"; VERSION="$1"; shift ;;
  esac
done

[[ -n "$VERSION" ]] || { usage >&2; exit 2; }
[[ -n "$KUBECONFIG_FILE" ]] && export KUBECONFIG="$KUBECONFIG_FILE"
[[ "$VERSION" == v* ]] || VERSION="v$VERSION"
[[ -n "$CONTEXT" ]] || usage_die "--context is required (refusing to guess the cluster)"
for bin in kubectl curl jq sort awk comm head grep tee mkdir chmod dirname basename date sleep; do
  command -v "$bin" >/dev/null || preflight_die "$bin not found"
done

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

kubectl --context "$CONTEXT" cluster-info >/dev/null 2>&1 || preflight_die "cannot reach cluster for context '$CONTEXT'"

missing_perms=()
can_i() { kubectl --context "$CONTEXT" auth can-i "$@" >/dev/null 2>&1 || missing_perms+=("$*"); }
can_i create customresourcedefinitions
can_i patch customresourcedefinitions
can_i create clusterroles
can_i patch clusterroles
can_i create clusterrolebindings
can_i patch clusterrolebindings
for res in configmaps secrets serviceaccounts services deployments statefulsets networkpolicies roles rolebindings; do
  can_i create "$res" -n "$NAMESPACE"
  can_i patch "$res" -n "$NAMESPACE"
done
if [[ ${#missing_perms[@]} -gt 0 ]]; then
  preflight_die "identity for '$CONTEXT' lacks: ${missing_perms[*]}"
fi
SERVER=$(kubectl --context "$CONTEXT" config view --minify -o jsonpath='{.clusters[0].cluster.server}')

CURRENT_IMAGE=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get deployment argocd-server \
  -o jsonpath='{.spec.template.spec.containers[0].image}') || preflight_die "Argo CD not found in namespace '$NAMESPACE'"
CURRENT="${CURRENT_IMAGE##*:}"

if kubectl --context "$CONTEXT" -n "$NAMESPACE" get deployment argocd-redis-ha-haproxy >/dev/null 2>&1; then
  MODE=HA; MANIFEST="manifests/ha/install.yaml"
else
  MODE=non-HA; MANIFEST="manifests/install.yaml"
fi
URL="https://raw.githubusercontent.com/argoproj/argo-cd/${VERSION}/${MANIFEST}"
curl -fsI "$URL" >/dev/null || preflight_die "manifest not found: $URL"

vercmp() {
  local a="${1#v}" b="${2#v}"
  awk -v a="$a" -v b="$b" 'BEGIN{
    n=split(a,A,"."); m=split(b,B,".");
    k=(n>m?n:m);
    for(i=1;i<=k;i++){ x=A[i]+0; y=B[i]+0; if(x<y){print -1; exit} if(x>y){print 1; exit} }
    print 0
  }'
}

CMP=$(vercmp "$VERSION" "$CURRENT")
if [[ "$CMP" -eq 0 ]]; then
  if [[ "$ROLLBACK" -eq 1 ]]; then
    log "already at $VERSION; re-applying in rollback mode"
  else
    log "already at $VERSION on $SERVER"
    RESULT_STATUS="already"
    exit 0
  fi
fi
if [[ "$CMP" -eq -1 ]]; then
  [[ "$ALLOW_DOWNGRADE" -eq 1 ]] || preflight_die "$SERVER runs $CURRENT, refusing to downgrade to $VERSION (use --allow-downgrade)"
  warn "DOWNGRADE $CURRENT -> $VERSION: older CRDs are re-applied; a clean revert is not guaranteed"
fi
[[ "$ROLLBACK" -eq 1 ]] && warn "rollback mode: older CRDs are re-applied, stored objects may lose newer fields"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR="${BACKUP_DIR:-$PWD/argocd-backup-${CONTEXT//[^a-zA-Z0-9_.-]/_}-$STAMP}"
if command -v git >/dev/null && git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  case "$BACKUP_DIR" in
    "$PWD"/*) warn "backup dir is inside a git work tree; never 'git add' it" ;;
  esac
fi

banner() {
  cat <<EOF

  cluster   : $SERVER
  context   : $CONTEXT
  namespace : $NAMESPACE
  mode      : $MODE
  argo cd   : $CURRENT -> $VERSION
  manifest  : $URL
  backup    : $BACKUP_DIR

EOF
}
if [[ "$JSON" -eq 1 ]]; then banner >&2; else banner; fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry run: server-side apply validation only"
  kubectl --context "$CONTEXT" apply -n "$NAMESPACE" --server-side --force-conflicts \
    --field-manager=argocd-upgrade --dry-run=server -f "$URL" | info_stream
  RESULT_STATUS="dry-run"
  exit 0
fi

if [[ "$ASSUME_YES" -eq 0 ]]; then
  [[ -t 0 ]] || usage_die "non-interactive shell; pass --yes to confirm"
  read -r -p "Type 'yes' to continue: " reply
  [[ "$reply" == "yes" ]] || { printf 'aborted\n' >&2; RESULT_STATUS="aborted"; exit 3; }
fi

log "backing up to $BACKUP_DIR"
[[ -e "$BACKUP_DIR" ]] && die "backup dir already exists: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR" || die "cannot create $BACKUP_DIR"
chmod 700 "$BACKUP_DIR" || die "cannot chmod $BACKUP_DIR"

kubectl --context "$CONTEXT" -n "$NAMESPACE" get configmaps -o json \
  | clean_list | redact_configmap_credentials > "$BACKUP_DIR/configmaps.json" || die "backup: configmaps"
kubectl --context "$CONTEXT" -n "$NAMESPACE" get deployments,statefulsets,services -o json \
  | clean_list > "$BACKUP_DIR/workloads.json" || die "backup: workloads"
kubectl --context "$CONTEXT" -n "$NAMESPACE" get applications,applicationsets -o json \
  | clean_list > "$BACKUP_DIR/apps.json" || die "backup: applications"
kubectl --context "$CONTEXT" get crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io -o json \
  | clean_list > "$BACKUP_DIR/crds.json" || die "backup: CRDs (required before the apply)"
kubectl --context "$CONTEXT" -n "$NAMESPACE" get deploy,sts \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image' \
  > "$BACKUP_DIR/images-before.txt" || die "backup: image snapshot"
kubectl --context "$CONTEXT" -n "$NAMESPACE" get applications \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' \
  > "$BACKUP_DIR/apps-before.txt" || die "backup: application snapshot"
kubectl --context "$CONTEXT" -n "$NAMESPACE" get cm argocd-cm \
  -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}' \
  | sort > "$BACKUP_DIR/cm-keys-before.txt" || die "backup: argocd-cm keys"
printf 'context=%s\nserver=%s\nfrom=%s\nto=%s\nmode=%s\nmanifest=%s\n' \
  "$CONTEXT" "$SERVER" "$CURRENT" "$VERSION" "$MODE" "$URL" > "$BACKUP_DIR/meta.txt"

rollback_hint() {
  cat >&2 <<EOF

To roll back:
  "$SCRIPT" "$CURRENT" --context "$CONTEXT" --rollback --yes
That re-applies the other version's manifests, including its CRDs; stored
objects may lose fields introduced by the version just applied. ConfigMaps
were backed up with credential-bearing keys redacted, so the backup is
reference-only — restore credentials from their own source.
Backup: $BACKUP_DIR

EOF
}

trap 'err "interrupted"; rollback_hint; exit 130' INT
trap 'err "terminated"; rollback_hint; exit 143' TERM
trap 'err "hangup"; rollback_hint; exit 129' HUP

log "applying $VERSION ($MODE)"
set +e
kubectl --context "$CONTEXT" apply -n "$NAMESPACE" --server-side --force-conflicts \
  --field-manager=argocd-upgrade -f "$URL" 2>&1 | tee "$BACKUP_DIR/apply.log" >&2
APPLY_RC=${PIPESTATUS[0]}
set -e

if [[ "$APPLY_RC" -ne 0 ]]; then
  err "apply exited with $APPLY_RC"
  rollback_hint
  exit 1
fi
if grep -qE '^(error:|Error from server)' "$BACKUP_DIR/apply.log"; then
  err "apply reported per-object errors:"
  grep -E '^(error:|Error from server)' "$BACKUP_DIR/apply.log" >&2
  rollback_hint
  exit 1
fi
RESULT_APPLIED=1

log "waiting for rollouts"
failed=0
for ref in \
  deployment/argocd-server \
  deployment/argocd-repo-server \
  deployment/argocd-applicationset-controller \
  deployment/argocd-notifications-controller \
  deployment/argocd-dex-server \
  deployment/argocd-redis \
  statefulset/argocd-application-controller \
  deployment/argocd-redis-ha-haproxy \
  statefulset/argocd-redis-ha-server
do
  kubectl --context "$CONTEXT" -n "$NAMESPACE" get "$ref" >/dev/null 2>&1 || continue
  if ! kubectl --context "$CONTEXT" -n "$NAMESPACE" rollout status "$ref" --timeout=300s >/dev/null 2>&1; then
    err "rollout failed: $ref"
    failed=1
  fi
done

log "verifying versions and configuration"
if ! IMAGES=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get deploy,sts \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.template.spec.containers[0].image}{"\n"}{end}'); then
  err "cannot read deployments/statefulsets"
  failed=1
  IMAGES=""
fi
if ! MANIFEST_IMAGES=$(curl -fsSL "$URL" | awk '/^[[:space:]]+image: /{print $2}' | sort -u); then
  err "cannot read images from the manifest"
  failed=1
  MANIFEST_IMAGES=""
fi
if [[ -n "$MANIFEST_IMAGES" ]]; then
  while read -r workload image; do
    [[ -z "$workload" ]] && continue
    case "$workload" in argocd-*) ;; *) continue ;; esac
    if ! printf '%s\n' "$MANIFEST_IMAGES" | grep -Fxq "$image"; then
      err "image not declared by $VERSION: $workload $image"
      failed=1
    fi
  done < <(printf '%s\n' "$IMAGES")
fi

if ! KEYS_AFTER=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get cm argocd-cm \
  -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}' | sort); then
  err "cannot read argocd-cm keys"
  failed=1
  KEYS_AFTER=""
fi
LOST=$(comm -23 "$BACKUP_DIR/cm-keys-before.txt" <(printf '%s\n' "$KEYS_AFTER") || true)
if [[ -n "$LOST" ]]; then
  err "argocd-cm lost keys:"
  printf '%s\n' "$LOST" >&2
  failed=1
fi
if ! URL_VALUE=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get cm argocd-cm -o jsonpath='{.data.url}'); then
  err "cannot read argocd-cm .data.url"
  failed=1
elif [[ -z "$URL_VALUE" ]]; then
  err "argocd-cm .data.url is empty"
  failed=1
fi

if [[ "$SETTLE" -gt 0 ]]; then
  log "waiting ${SETTLE}s for the controllers to re-diff applications"
  sleep "$SETTLE"
fi

if ! APPLICATIONS_JSON=$(kubectl --context "$CONTEXT" -n "$NAMESPACE" get applications \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="ComparisonError")].message}{"\n"}{end}'); then
  err "cannot read applications"
  failed=1
  APPLICATIONS_JSON=""
fi
if ! COMPARISON_ERRORS=$(printf '%s\n' "$APPLICATIONS_JSON" | awk -F'\t' 'NF>1 && $2!=""'); then
  err "cannot parse ComparisonError conditions"
  failed=1
  COMPARISON_ERRORS=""
fi
if [[ -n "$COMPARISON_ERRORS" ]]; then
  err "ComparisonError conditions present:"
  printf '%s\n' "$COMPARISON_ERRORS" >&2
  warn "on 3.6 ServerSideApply=true implies ServerSideDiff; for agentgateway et al."
  warn "opt out with argocd.argoproj.io/compare-options: ServerSideDiff=false"
  failed=1
fi

snapshot_ok=1
kubectl --context "$CONTEXT" -n "$NAMESPACE" get applications \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' \
  > "$BACKUP_DIR/apps-after.txt" || { err "cannot snapshot applications"; failed=1; snapshot_ok=0; }

if [[ "$snapshot_ok" -eq 1 ]]; then
  if ! APP_REPORT=$(awk '
    function srank(s){ return s=="Synced" ? 0 : (s=="OutOfSync" ? 1 : 2) }
    NR==FNR { if (FNR>1) b[$1]=$2"/"$3; next }
    FNR>1 {
      a=$2"/"$3
      if (!($1 in b)) { print "NEW " $1 " " a; next }
      split(b[$1], p, "/")
      if (srank($2)>srank(p[1]) || ($3=="Degraded" && p[2]!="Degraded")) print "WORSE " $1 ": " b[$1] " -> " a
      else if (b[$1] != a) print "CHANGED " $1 ": " b[$1] " -> " a
      delete b[$1]
    }
    END { for (n in b) print "LOST " n }
  ' "$BACKUP_DIR/apps-before.txt" "$BACKUP_DIR/apps-after.txt"); then
    err "cannot compare applications"
    failed=1
    APP_REPORT=""
  fi

  if [[ -n "$APP_REPORT" ]]; then
    LOST_APPS=$(printf '%s\n' "$APP_REPORT" | grep -E '^LOST ' || true)
    WORSE_APPS=$(printf '%s\n' "$APP_REPORT" | grep -E '^WORSE ' || true)
    while IFS= read -r line; do
      warn "$line"
    done < <(printf '%s\n' "$APP_REPORT" | grep -vE '^(LOST|WORSE) ' || true)
    if [[ -n "$LOST_APPS" ]]; then
      err "applications disappeared:"
      printf '%s\n' "$LOST_APPS" >&2
      failed=1
    fi
    if [[ -n "$WORSE_APPS" ]]; then
      if [[ "$ALLOW_DEGRADED" -eq 1 ]]; then
        warn "applications worsened (allowed):"
        printf '%s\n' "$WORSE_APPS" >&2
      else
        err "applications worsened:"
        printf '%s\n' "$WORSE_APPS" >&2
        failed=1
      fi
    fi
  fi
else
  warn "application comparison skipped: after-snapshot unavailable"
fi

echo | info_stream
log "result on $SERVER"
kubectl --context "$CONTEXT" -n "$NAMESPACE" get deploy,sts \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas' \
  | info_stream || warn "cannot print final workload table"
printf 'summary: %s -> %s on %s (%s)\n' "$CURRENT" "$VERSION" "$SERVER" "$MODE" | info_stream
printf 'backup:  %s\n' "$BACKUP_DIR" | info_stream

if [[ "$failed" -ne 0 ]]; then
  err "verification found problems"
  rollback_hint
  exit 1
fi

RESULT_STATUS="verified"
log "upgrade verified"
