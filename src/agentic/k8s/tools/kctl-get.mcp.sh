#!/usr/bin/env bash
# ---
# description: Run a cluster query without retyping the cluster path — resolves the project's kubeconfig (or one named cluster) and passes the query straight to kubectl through kctl
# ---
# =============================================================================
# src/agentic/k8s/tools/kctl-get.mcp.sh
# Shortcut over `devbot kctl`: the corpus showed the same long cluster path
# retyped for every query, twice in a row to compare environments.
#
# AUTHORISATION — read this before changing the tool. The k8s module requires
# cluster access through the kctl-<key> MCP servers and forbids an agent running
# `devbot kctl run|exec` itself. This tool is the exception, authorised by the
# project owner: it never runs kubectl directly, it delegates to kctl so the
# project's generated kubeconfig and context rules still apply, and it exists
# because the retyped cluster path was one of the costliest patterns measured.
# Keep the delegation — do not reimplement kubectl here.
#
# Usage:
#   kctl-get.mcp.sh get deploy -n transfers-qa
#   kctl-get.mcp.sh get pods -n transfers-qa --cluster gete-dev
#   kctl-get.mcp.sh --cluster gete-dev -- get deploy -n transfers-qa
#
# The arguments are kubectl's own — do NOT prefix `kubectl`:
#   kctl-get.mcp.sh get ns default        ✔
#   kctl-get.mcp.sh kubectl get ns        ✘
#
# Without --cluster the project's kubeconfig current-context is used, exactly as
# `devbot kctl run .` does. With --cluster the context is applied from the
# global catalogue, so a caller cannot reach another cluster's context.
#
# Dependencies: bash, the k8s module's kctl.sh
# =============================================================================

set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"kctl-get","description":"Run a cluster query without retyping the cluster path: resolves the project's generated kubeconfig (or the cluster named by --cluster) and passes the query through kubectl. Arguments are the cluster client's own — do not prefix the binary name.","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI arguments: [--cluster <key>] [--path <dir>] -- <kubectl arguments, without the leading binary>."}},"required":["args"]}}
JSON
    exit 0
    ;;
  -h | --help)
    sed -n '6,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

cluster=""
project_path="."
query=()

# Wrapper options are recognised anywhere in the line, not just before the query:
# `get pods -n transfers-qa --cluster gete-dev` is the documented form, and
# leaving --cluster inside the query would silently target the wrong context.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      cluster="${2:-}"
      [[ -n "$cluster" ]] || {
        echo "ERROR: --cluster needs a value" >&2
        exit 2
      }
      shift 2
      ;;
    --cluster=*)
      cluster="${1#*=}"
      shift
      ;;
    --path)
      project_path="${2:-}"
      [[ -n "$project_path" ]] || {
        echo "ERROR: --path needs a value" >&2
        exit 2
      }
      shift 2
      ;;
    --path=*)
      project_path="${1#*=}"
      shift
      ;;
    --)
      shift
      query+=("$@")
      break
      ;;
    *)
      query+=("$1")
      shift
      ;;
  esac
done

if [[ ${#query[@]} -eq 0 ]]; then
  echo "ERROR: no query given — pass kubectl arguments, e.g. get deploy -n transfers-qa" >&2
  exit 2
fi

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
KCTL="${KCTL_BIN:-${SCRIPT_DIR}/../kctl.sh}"

if [[ ! -f "$KCTL" ]]; then
  echo "FATAL: kctl.sh not found at $KCTL" >&2
  exit 1
fi

if [[ -n "$cluster" ]]; then
  exec bash "$KCTL" exec "$cluster" "$project_path" -- "${query[@]}"
fi
exec bash "$KCTL" run "$project_path" -- "${query[@]}"
