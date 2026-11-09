#!/usr/bin/env bash
# Connect the argocd CLI to a cluster and report application status.
set -euo pipefail

CONTEXT=""
NAMESPACE=argocd
PORT=8080
ADDRESS=127.0.0.1
NO_FORWARD=0
SERVER=""
TOKEN="${ARGOCD_AUTH_TOKEN:-}"
USERNAME="admin"
PASSWORD=""
JSON=0
STOP=0
TIMEOUT=30
INSECURE=0
KUBECONFIG_FILE=""
STARTED_FORWARD=0

log()  { printf '%s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
usage_die() { printf 'FATAL: %s\n' "$*" >&2; printf 'Run with --help for usage.\n' >&2; exit 2; }

usage() {
  cat <<'EOF'
Connect the argocd CLI to a cluster and report application status.

  argocd-start.sh [options]

  --context <name>      kubectl context (default: the current context)
  --kubeconfig <file>   kubeconfig to use (default: $KUBECONFIG or ~/.kube/config)
  --namespace <name>    Argo CD namespace, default: argocd
  --port <n>            local port for the port-forward, default: 8080
  --address <ip>        local address for the port-forward, default: 127.0.0.1
  --no-forward          use an existing server instead of forwarding
  --server <url>        Argo CD server URL; implies --no-forward
  --token <token>       use a token (or set ARGOCD_AUTH_TOKEN)
  --username <user>     login user, default: admin
  --password <pass>     login password
  --insecure            skip TLS verification for a remote --server (local is implicit)
  --timeout <seconds>   port-forward readiness timeout, default: 30
  --stop-forward        stop the port-forward recorded for this target
  --json                print the application list as JSON
  -h, --help            this help

Auth: --token (or ARGOCD_AUTH_TOKEN) or --password. The script never reads
Argo CD Secrets; obtain a token or password from the user or your secret store.
Exit codes: 0 ok, 1 failure, 2 usage/auth.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)      [[ -n "${2:-}" ]] || usage_die "--context needs a value"; CONTEXT="$2"; shift 2 ;;
    --kubeconfig)   [[ -n "${2:-}" ]] || usage_die "--kubeconfig needs a value"; KUBECONFIG_FILE="$2"; shift 2 ;;
    --namespace)    [[ -n "${2:-}" ]] || usage_die "--namespace needs a value"; NAMESPACE="$2"; shift 2 ;;
    --port)         [[ -n "${2:-}" ]] || usage_die "--port needs a value"; PORT="$2"; shift 2 ;;
    --address)      [[ -n "${2:-}" ]] || usage_die "--address needs a value"; ADDRESS="$2"; shift 2 ;;
    --no-forward)   NO_FORWARD=1; shift ;;
    --server)       [[ -n "${2:-}" ]] || usage_die "--server needs a value"; SERVER="$2"; shift 2 ;;
    --token)        [[ -n "${2:-}" ]] || usage_die "--token needs a value"; TOKEN="$2"; shift 2 ;;
    --username)     [[ -n "${2:-}" ]] || usage_die "--username needs a value"; USERNAME="$2"; shift 2 ;;
    --password)     [[ -n "${2:-}" ]] || usage_die "--password needs a value"; PASSWORD="$2"; shift 2 ;;
    --timeout)      [[ -n "${2:-}" ]] || usage_die "--timeout needs a value"; TIMEOUT="$2"; shift 2 ;;
    --insecure)     INSECURE=1; shift ;;
    --stop-forward) STOP=1; shift ;;
    --json)         JSON=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              usage_die "unknown option: $1" ;;
  esac
done

[[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] || usage_die "--port must be an integer from 1 to 65535"
[[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -ge 1 ]] || usage_die "--timeout must be a positive integer"

[[ -n "$KUBECONFIG_FILE" ]] && export KUBECONFIG="$KUBECONFIG_FILE"
export PATH="${ARGOCD_BIN_DIR:-$HOME/.local/bin}:$PATH"
for bin in kubectl curl argocd; do command -v "$bin" >/dev/null || die "$bin not found"; done

create_state_dir() {
  local dir="${XDG_RUNTIME_DIR:-$HOME/.cache}/devbot/argocd"
  mkdir -p "$dir" || die "cannot create $dir"
  chmod 700 "$dir" || die "cannot chmod $dir"
  printf '%s' "$dir"
}
STATE_DIR="$(create_state_dir)"

# The state key is the real target, not a placeholder "current".
if [[ -z "$CONTEXT" ]]; then
  if [[ "$STOP" -eq 1 || -z "$SERVER" ]]; then
    CONTEXT=$(kubectl config current-context 2>/dev/null) || die "cannot resolve the current kubectl context"
  fi
fi
ctx_slug=$(printf '%s' "${CONTEXT:-current}" | tr -c 'A-Za-z0-9_.-' '_')
STATE_KEY="${ctx_slug}-${NAMESPACE}-${ADDRESS}-${PORT}"
PF_PID_FILE="${STATE_DIR}/pf-${STATE_KEY}.pid"
PF_LOG_FILE="${STATE_DIR}/pf-${STATE_KEY}.log"

pid_is_our_forward() {
  local pid="$1" args
  kill -0 "$pid" 2>/dev/null || return 1
  args=$(ps -p "$pid" -o args= 2>/dev/null || true)
  [[ "$args" == *port-forward* && "$args" == *"${PORT}:443"* && "$args" == *"$NAMESPACE"* ]]
}

cleanup() {
  local rc=$?
  if [[ "$rc" -ne 0 && "$STARTED_FORWARD" -eq 1 && -f "$PF_PID_FILE" ]]; then
    kill "$(cat "$PF_PID_FILE")" 2>/dev/null || true
    rm -f "$PF_PID_FILE"
  fi
  return 0
}
trap cleanup EXIT

if [[ "$STOP" -eq 1 ]]; then
  if [[ -f "$PF_PID_FILE" ]]; then
    pid=$(cat "$PF_PID_FILE")
    if pid_is_our_forward "$pid"; then
      kill "$pid" 2>/dev/null && log "stopped port-forward (pid $pid)"
    else
      log "the recorded pid $pid is not a port-forward for this target"
    fi
    rm -f "$PF_PID_FILE"
  else
    log "no port-forward recorded for this target"
  fi
  exit 0
fi

# Credentials are required before anything is started.
if [[ -z "$TOKEN" && -z "$PASSWORD" ]]; then
  usage_die "no credentials: pass --token (or set ARGOCD_AUTH_TOKEN) or --password"
fi

# An explicit server is authoritative: never forward and ignore it.
[[ -n "$SERVER" ]] && NO_FORWARD=1
if [[ "$NO_FORWARD" -eq 1 ]]; then
  [[ -n "$SERVER" ]] || usage_die "--no-forward needs --server"
else
  SERVER="https://${ADDRESS}:${PORT}"
fi

if [[ "$NO_FORWARD" -eq 0 ]]; then
  if curl -sk --max-time 2 "${SERVER}/healthz" >/dev/null 2>&1; then
    if [[ -f "$PF_PID_FILE" ]] && pid_is_our_forward "$(cat "$PF_PID_FILE")"; then
      log "reusing the recorded port-forward on ${SERVER}"
    else
      die "something already answers on ${SERVER} and it is not a recorded forward for this target; stop it or pass --server"
    fi
  else
    log "starting port-forward ${ADDRESS}:${PORT} -> ${NAMESPACE}/argocd-server:443"
    nohup kubectl ${CONTEXT:+--context "$CONTEXT"} -n "$NAMESPACE" \
      port-forward "svc/argocd-server" "${PORT}:443" --address "$ADDRESS" \
      >"$PF_LOG_FILE" 2>&1 &
    echo $! > "$PF_PID_FILE"
    STARTED_FORWARD=1
    ready=0
    for _ in $(seq 1 "$TIMEOUT"); do
      if curl -sk --max-time 2 "${SERVER}/healthz" >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 1
    done
    if [[ "$ready" -ne 1 ]]; then
      die "port-forward did not become ready in ${TIMEOUT}s (see $PF_LOG_FILE)"
    fi
    log "port-forward ready (pid $(cat "$PF_PID_FILE"))"
  fi
fi

insecure_arg=()
if [[ "$INSECURE" -eq 1 ]]; then
  insecure_arg=(--insecure)
elif [[ "$SERVER" =~ ^https://(127\.0\.0\.1|localhost)(:[0-9]+)?/?$ ]]; then
  insecure_arg=(--insecure)
fi

if [[ -n "$TOKEN" ]]; then
  export ARGOCD_SERVER="$SERVER"
  export ARGOCD_AUTH_TOKEN="$TOKEN"
  if [[ ${#insecure_arg[@]} -gt 0 ]]; then
    export ARGOCD_OPTS="${ARGOCD_OPTS:-} --insecure"
  fi
elif [[ -n "$PASSWORD" ]]; then
  log "logging in as $USERNAME"
  argocd login "$SERVER" "${insecure_arg[@]}" --username "$USERNAME" --password "$PASSWORD" >/dev/null \
    || die "login failed"
fi

if [[ "$JSON" -eq 1 ]]; then
  exec argocd app list -o json
else
  exec argocd app list -o wide
fi
