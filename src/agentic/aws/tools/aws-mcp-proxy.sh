#!/usr/bin/env bash
# src/agentic/aws/tools/aws-mcp-proxy.sh
# AWS MCP proxy launcher — execs the installed `mcp-proxy-for-aws` tool as ONE
# named AWS connection.
#
# Usage: aws-mcp-proxy.sh <connection>
#
# The connection is declared in .devbot.global.jsonc:
#
#   "aws_connections": {
#     "<connection>": {
#       "region": "eu-central-1",
#       "account_id": "123456789012",              # optional pin
#       "env": { "AWS_ACCESS_KEY_ID": "${VAR}" }   # XOR
#       "profile": "<profile in ~/.aws/config>"    # XOR
#     }
#   }
#
# Credentials reach the proxy through the ENVIRONMENT, never argv (argv is
# visible in `ps`). `env` values may be literals or ${VAR} references, resolved
# from the shell environment and the repo .env — the same load
# datasources/render.sh performs. `profile` defers to ~/.aws/config, where the
# keys live.
#
# stdout must stay clean: MCP speaks JSON-RPC over stdio, so every diagnostic
# goes to stderr.
#
# This script is symlinked into .opencode/ and .claude/ by init.sh and invoked by
# the per-connection MCP manifest.

set -euo pipefail

# Symlink-safe and GNU-free: resolve the symlink chain by hand. `readlink -f` is
# GNU-only and absent on macOS, which this module must support — the format-*
# and codebase-memory tools resolve the same way.
_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${_SOURCE}" ]]; do
  _DIR="$(cd -P "$(dirname "${_SOURCE}")" && pwd)"
  _SOURCE="$(readlink "${_SOURCE}")"
  [[ "${_SOURCE}" != /* ]] && _SOURCE="${_DIR}/${_SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${_SOURCE}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${SCRIPT_DIR}/../../../.." && pwd)}"
GLOBAL_CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
ENV_FILE="${DEV_BOT_ROOT}/.env"
READ_JSONC="${SCRIPT_DIR}/../../../_shared/read_jsonc.py"

PROXY_BIN="mcp-proxy-for-aws-cli"
ENDPOINT="https://aws-mcp.us-east-1.api.aws/mcp"

# All diagnostics go to stderr — stdout carries the MCP stream.
_die() {
  echo "aws-mcp: $*" >&2
  exit 1
}

# Resolve the installed proxy executable, or return non-zero. Single source of
# truth for "is the proxy available?": pre.sh and up.sh ask via --which, so their
# warnings cannot disagree with what a launch would actually do.
_proxy_path() {
  local path
  path="$(command -v "${PROXY_BIN}" 2>/dev/null || true)"
  if [[ -z "${path}" && -n "${HOME:-}" ]]; then
    path="${HOME}/.local/bin/${PROXY_BIN}"
  fi
  [[ -x "${path}" ]] || return 1
  printf '%s\n' "${path}"
}

# With --check the launcher resolves the connection, verifies its credentials
# (and its account pin, when present) and exits without starting a session.
# up.sh verifies every declared connection that way.
CHECK=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK=1
  shift
fi

# With --which it reports the resolved proxy path (or fails) — no connection or
# credentials involved, so pre.sh and up.sh can report presence consistently.
if [[ "${1:-}" == "--which" ]]; then
  _proxy_path || _die "'${PROXY_BIN}' is not installed — run 'devbot install' to install the AWS MCP proxy"
  exit 0
fi

CONNECTION="${1:-}"
[[ -n "${CONNECTION}" ]] || _die "usage: aws-mcp-proxy.sh [--check|--which] <connection>"
[[ -f "${GLOBAL_CONFIG}" ]] || _die "no global config at ${GLOBAL_CONFIG}"

# Read one field of the connection. read_jsonc prints "" for a missing key.
_read_field() {
  python3 "${READ_JSONC}" "${GLOBAL_CONFIG}" aws_connections "${CONNECTION}" "$1" 2>/dev/null || true
}

CONN_JSON="$(python3 "${READ_JSONC}" "${GLOBAL_CONFIG}" aws_connections "${CONNECTION}" 2>/dev/null || true)"
[[ -n "${CONN_JSON}" ]] || _die "connection '${CONNECTION}' is not declared in aws_connections (.devbot.global.jsonc)"

ENV_JSON="$(_read_field env)"
PROFILE="$(_read_field profile)"
REGION="$(_read_field region)"
ACCOUNT="$(_read_field account_id)"
[[ "${ENV_JSON}" == "{}" ]] && ENV_JSON=""

if [[ -n "${ENV_JSON}" && -n "${PROFILE}" ]]; then
  _die "connection '${CONNECTION}' declares both env and profile — declare exactly one (precedence would be ambiguous)"
fi

# ── Credentials ───────────────────────────────────────────────────────────────
# PROXY_ARGS carries whatever the chosen credential form needs on the command
# line; secrets never do.
PROXY_ARGS=()

# Load the repo .env ONCE, before either form is resolved — the same load
# datasources/render.sh and up.sh perform — so a ${VAR} reference and a
# .env-supplied AWS_REGION resolve identically for env and profile connections.
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

if [[ -n "${ENV_JSON}" ]]; then
  # Resolve this connection's values and export them into the proxy's environment.
  while IFS=$'\t' read -r name value; do
    [[ -n "${name}" ]] || continue
    [[ -n "${value}" ]] || _die "connection '${CONNECTION}': env '${name}' resolves to nothing — is the referenced variable exported (repo .env or shell)?"
    export "${name}=${value}"
  done < <(printf '%s' "${ENV_JSON}" | python3 -c '
import json, os, re, sys

# The env block arrives on STDIN, never argv: a literal value is secret-like and
# argv is world-readable through ps / /proc.
env = json.load(sys.stdin)
ref = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$")
for key, raw in env.items():
    value = str(raw)
    match = ref.match(value)
    if match:
        value = os.environ.get(match.group(1), "")
    print(f"{key}\t{value}")
')

  # The explicit keys must win deterministically: botocore's environment provider
  # precedes the shared-config one, and an ambient AWS_PROFILE would otherwise
  # steer resolution elsewhere.
  unset AWS_PROFILE
elif [[ -n "${PROFILE}" ]]; then
  PROXY_ARGS+=(--profile "${PROFILE}")
else
  _die "connection '${CONNECTION}' declares neither env nor profile — nothing to authenticate with"
fi

# ── Region ─────────────────────────────────────────────────────────────────────
# Resolved AFTER the credential block so a region supplied through the repo .env
# counts. Precedence: the connection, then AWS_REGION, then the ambient config,
# then us-east-1. The proxy's boto3 session needs a region to sign with, so the
# value is exported as well as passed as metadata below.
if [[ -z "${REGION}" ]]; then
  REGION="${AWS_REGION:-}"
fi
if [[ -z "${REGION}" ]] && command -v aws &>/dev/null; then
  REGION="$(aws configure get region 2>/dev/null || true)"
fi
REGION="${REGION:-us-east-1}"
export AWS_REGION="${REGION}"

# AWS_MCP_PROXY_PROFILES takes precedence over the connection's credentials inside
# the proxy, so leaving it set would let an agent switch profiles: the account
# check below would pass while the session ran as another identity. Drop it and
# say so — the connection is the single source of identity (D10).
if [[ -n "${AWS_MCP_PROXY_PROFILES:-}" ]]; then
  echo "aws-mcp: WARNING AWS_MCP_PROXY_PROFILES is set and would let the agent switch profiles;" >&2
  echo "  ignoring it — connection '${CONNECTION}' is the source of identity." >&2
  unset AWS_MCP_PROXY_PROFILES
fi

# ── Identity verification ──────────────────────────────────────────────────────
# Always run under --check (up.sh verifies every declared connection), and always
# when the connection pins an account. The pin turns "locked to account X" into a
# checked property: a stale, wrong or swapped key refuses to start instead of
# silently running as another account.
ACTUAL_ACCOUNT=""
if [[ "${CHECK}" == "1" || -n "${ACCOUNT}" ]]; then
  command -v aws &>/dev/null || _die "the AWS CLI is unavailable — run 'devbot install'"
  ACTUAL_ACCOUNT="$(aws sts get-caller-identity --query Account --output text ${PROXY_ARGS[@]+"${PROXY_ARGS[@]}"} 2>/dev/null || true)"
  [[ -n "${ACTUAL_ACCOUNT}" ]] || _die "connection '${CONNECTION}': credentials are unusable (aws sts get-caller-identity failed)"
  if [[ -n "${ACCOUNT}" && "${ACTUAL_ACCOUNT}" != "${ACCOUNT}" ]]; then
    _die "connection '${CONNECTION}': sts reports account '${ACTUAL_ACCOUNT}', expected '${ACCOUNT}'"
  fi
fi

if [[ "${CHECK}" == "1" ]]; then
  echo "aws-mcp: connection '${CONNECTION}' OK (account ${ACTUAL_ACCOUNT})" >&2
  exit 0
fi

# The proxy is an installed uv tool (install.sh / update.sh), never resolved at
# launch: `uvx` re-resolves the whole dependency graph against PyPI on every
# start, and a single stalled request outruns the MCP client's 30 s init budget.
# The version pin is applied at install/update time; the launcher deliberately
# execs whatever is installed, so `uv tool upgrade` drifts until the next run.
PROXY_PATH="$(_proxy_path)" || _die "'${PROXY_BIN}' is not installed — run 'devbot install' to install the AWS MCP proxy"

exec "${PROXY_PATH}" "${ENDPOINT}" \
  ${PROXY_ARGS[@]+"${PROXY_ARGS[@]}"} \
  --metadata "INSTALL_SOURCE=agent-toolkit-core" \
  --metadata "AWS_REGION=${REGION}"
