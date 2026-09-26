#!/usr/bin/env bash
# src/agentic/aws/tools/aws-mcp-proxy.sh
# AWS MCP proxy launcher — execs `uvx mcp-proxy-for-aws` as ONE named AWS
# connection.
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

PROXY="mcp-proxy-for-aws@1.6.4"
ENDPOINT="https://aws-mcp.us-east-1.api.aws/mcp"

# All diagnostics go to stderr — stdout carries the MCP stream.
_die() {
  echo "aws-mcp: $*" >&2
  exit 1
}

# With --check the launcher resolves the connection, verifies its credentials
# (and its account pin, when present) and exits without starting a session.
# up.sh verifies every declared connection that way.
CHECK=0
if [[ "${1:-}" == "--check" ]]; then
  CHECK=1
  shift
fi

CONNECTION="${1:-}"
[[ -n "${CONNECTION}" ]] || _die "usage: aws-mcp-proxy.sh [--check] <connection>"
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

# ── Region: the connection wins, then the environment, then the ambient config ─
if [[ -z "${REGION}" ]]; then
  REGION="${AWS_REGION:-}"
fi
if [[ -z "${REGION}" ]] && command -v aws &>/dev/null; then
  REGION="$(aws configure get region 2>/dev/null || true)"
fi
REGION="${REGION:-us-east-1}"

# ── Credentials ───────────────────────────────────────────────────────────────
# PROXY_ARGS carries whatever the chosen credential form needs on the command
# line; secrets never do.
PROXY_ARGS=()

if [[ -n "${ENV_JSON}" ]]; then
  # Load the repo .env so ${VAR} references resolve exactly as datasources'
  # render.sh/up.sh resolve them, then resolve this connection's values and
  # export them into the proxy's environment.
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
  fi

  while IFS=$'\t' read -r name value; do
    [[ -n "${name}" ]] || continue
    [[ -n "${value}" ]] || _die "connection '${CONNECTION}': env '${name}' resolves to nothing — is the referenced variable exported (repo .env or shell)?"
    export "${name}=${value}"
  done < <(python3 - "${ENV_JSON}" <<'PY'
import json, os, re, sys

env = json.loads(sys.argv[1])
ref = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$")
for key, raw in env.items():
    value = str(raw)
    match = ref.match(value)
    if match:
        value = os.environ.get(match.group(1), "")
    print(f"{key}\t{value}")
PY
  )

  # The explicit keys must win deterministically: botocore's environment provider
  # precedes the shared-config one, and an ambient AWS_PROFILE would otherwise
  # steer resolution elsewhere.
  unset AWS_PROFILE
elif [[ -n "${PROFILE}" ]]; then
  PROXY_ARGS+=(--profile "${PROFILE}")
else
  _die "connection '${CONNECTION}' declares neither env nor profile — nothing to authenticate with"
fi

# The proxy's boto3 session needs a region to sign with; the resolved one is also
# handed to the server as metadata below.
export AWS_REGION="${REGION}"

# AWS_MCP_PROXY_PROFILES takes precedence over the credential configuration
# inside the proxy, which would let an agent switch profiles. Surface it rather
# than let it win quietly.
if [[ -n "${AWS_MCP_PROXY_PROFILES:-}" ]]; then
  echo "aws-mcp: WARNING AWS_MCP_PROXY_PROFILES is set and takes precedence over the connection's" >&2
  echo "  credentials — the agent may switch profiles. Unset it to keep the pin." >&2
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

exec uvx "${PROXY}" "${ENDPOINT}" \
  ${PROXY_ARGS[@]+"${PROXY_ARGS[@]}"} \
  --metadata "INSTALL_SOURCE=agent-toolkit-core" \
  --metadata "AWS_REGION=${REGION}"
