#!/usr/bin/env bash
# ---
# description: Launch mcp-confluent as ONE named Kafka connection (read-only allowlist; credentials resolved into a 0600 config, never into argv or the environment). --check validates the rendered config against the installed server, --print-config prints it with references intact, --which reports the executable.
# ---
# src/agentic/kafka/tools/kafka-mcp-launch.sh
# Kafka MCP launcher — execs mcp-confluent as ONE named Kafka connection.
#
# Usage: kafka-mcp-launch.sh [--check|--print-config|--which] <connection>
#
# The connection is declared in .devbot.global.jsonc:
#
#   "kafka_connections": {
#     "<connection>": {
#       "bootstrap_servers": "broker:9092",
#       "auth": { "type": "api_key", "key": "${K}", "secret": "${S}" },
#       "extra_properties": { "sasl.mechanisms": "SCRAM-SHA-512" },
#       "schema_registry": { "endpoint": "https://sr.local" },
#       "env": { "K": "${DEV_KAFKA_KEY}", "S": "${DEV_KAFKA_SECRET}" }
#     }
#   }
#
# WHERE THE CREDENTIALS GO
#
# Every `${VAR}` the rendered config references is resolved HERE — from the
# connection's `env` block first (which is itself resolved from the process
# environment and the repo .env), then the process environment, then the repo
# .env — and written into the rendered config, which is 0600 in a 0700
# directory. The server therefore reads its credentials from one file:
#
#   - nothing secret appears in the server's argv (readable through `ps`),
#   - nothing secret appears in its environment, which is scrubbed to PATH,
#     HOME, TMPDIR, LANG and DO_NOT_TRACK, so an ambient cloud or database
#     credential the harness exported is unreadable to it.
#
# `--print-config` deliberately prints the UNRESOLVED document — references
# intact — so inspecting a connection does not spill its secrets into a
# terminal or a log.
#
# The server is allowlisted on every launch: the tools in ALLOWED_TOOLS are the
# tools that exist. produce-message, create-topics, delete-topics and
# alter-topic-config never register, so no prompt can reach them. The rendered
# config also carries `read_only: true`, so a mutating tool an upgrade adds
# still cannot run here.
#
# stdout must stay clean: MCP speaks JSON-RPC over stdio, so every diagnostic
# goes to stderr.
#
# This script is symlinked into .opencode/ and .claude/ by init.sh and invoked by
# the per-connection MCP manifest.
#
# GATE: Must work on Ubuntu, Fedora, and macOS.

set -euo pipefail

# Symlink-safe and GNU-free: resolve the symlink chain by hand. `readlink -f` is
# GNU-only and absent on macOS, which this module must support.
_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "${_SOURCE}" ]]; do
  _DIR="$(cd -P "$(dirname "${_SOURCE}")" && pwd)"
  _SOURCE="$(readlink "${_SOURCE}")"
  [[ "${_SOURCE}" != /* ]] && _SOURCE="${_DIR}/${_SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${_SOURCE}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${SCRIPT_DIR}/../../../.." && pwd)}"
export DEV_BOT_ROOT
GLOBAL_CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
DOTENV="${DEV_BOT_ROOT}/.env"

# shellcheck source=../functions.sh
source "${SCRIPT_DIR}/../functions.sh"

_die() {
  echo "kafka-mcp: $*" >&2
  exit 1
}

# Telemetry is off for EVERY mode, including the preflight: the server reads this
# at startup, so setting it only on the exec path would let a reinit emit
# telemetry. It governs telemetry, never behaviour.
export DO_NOT_TRACK=1

# With --which it reports the resolved server executable (or fails) — no
# connection involved, so pre.sh can report presence consistently with a launch.
if [[ "${1:-}" == "--which" ]]; then
  _kafka_mcp_binary || _die "'${MCP_BINARY}' is not installed — run 'devbot install' to install ${MCP_PACKAGE}"
  exit 0
fi

MODE=""
case "${1:-}" in
  --check)
    MODE="--check"
    shift
    ;;
  --print-config)
    MODE="--print-config"
    shift
    ;;
esac

CONNECTION="${1:-}"
[[ -n "${CONNECTION}" ]] || _die "usage: kafka-mcp-launch.sh [--check|--print-config|--which] <connection>"
# The name becomes a filename and a path segment. init.sh checks it for the
# names it wires, but this launcher is a public entry point: `--check ../x` must
# not write the rendered config outside the runtime directory.
_kafka_valid_name "${CONNECTION}" ||
  _die "'${CONNECTION}' is not a valid connection name (letters, digits, dot, dash, underscore)"
[[ -f "${GLOBAL_CONFIG}" ]] || _die "no global config at ${GLOBAL_CONFIG}"

# One read of the catalogue for the whole launch: render_config.py validates the
# entry and numbers its own errors, so a bad catalogue entry reads the same here
# as it does under 'devbot reinit'.
CATALOGUE="$(python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${GLOBAL_CONFIG}" kafka_connections 2>/dev/null || true)"
[[ -n "${CATALOGUE}" ]] || _die "no kafka_connections declared in ${GLOBAL_CONFIG}"

# The UNRESOLVED document: `${VAR}` references exactly as the catalogue wrote
# them. This is what --print-config shows.
#
# Returns 2 (printing the reason) rather than exiting: callers capture its
# stdout, and an `exit` inside a command substitution would only end the
# subshell — the caller would happily carry on with an empty document.
_rendered() {
  local out rc=0
  out="$(printf '%s' "${CATALOGUE}" | python3 "${MODULE_DIR}/render_config.py" "$1" 2>&1)" || rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    printf '%s\n' "$(printf '%s' "${out}" | sed 's/^kafka: //')" >&2
    return 2
  fi
  printf '%s\n' "${out}"
}

# ── Credentials ───────────────────────────────────────────────────────────────
# The repo .env is PARSED, never sourced and never exported: nothing in it is
# executed, and only the values a connection needs are ever read.

# ── Render the config ─────────────────────────────────────────────────────────
# The file the server reads is the RESOLVED document (see the header): 0600 under
# a 0700 directory, because that is where the credentials live.
RUNTIME_DIR="${KAFKA_RUNTIME_DIR}"
PUBLISHED_CONFIG=""

# Temp files this launch created, removed however it ends — including a `_die`
# between their creation and their use. An EXIT trap never runs after `exec`, but
# by then nothing is outstanding.
LAUNCH_TEMPS=()

_cleanup_temps() {
  local file
  for file in ${LAUNCH_TEMPS[@]+"${LAUNCH_TEMPS[@]}"}; do
    rm -f -- "${file}"
  done
}

trap _cleanup_temps EXIT

_write_config() {
  local name="$1" lenient="${2:-0}" err content hash tmp missing rc=0
  mkdir -p "${RUNTIME_DIR}" || _die "cannot create ${RUNTIME_DIR}"
  # The rendered file holds resolved credentials, so this is the guarantee the
  # module documents. A directory we cannot make private — or a filesystem that
  # ignores modes — must stop the launch, never be ignored.
  chmod 700 "${RUNTIME_DIR}" 2>/dev/null || true
  if ! _kafka_mode_private "${RUNTIME_DIR}"; then
    _die "${RUNTIME_DIR} cannot be made private (mode 0700): kafka credentials must not sit in a shared directory — fix its permissions or point KAFKA_RUNTIME_DIR elsewhere"
  fi

  err="$(mktemp "${RUNTIME_DIR}/.missing.XXXXXX")" || _die "cannot write to ${RUNTIME_DIR}"
  LAUNCH_TEMPS+=("${err}")

  # Resolved as DATA, then rendered: every value goes through json.dumps(), so a
  # quote or a newline in a credential cannot change the document's shape.
  if ! content="$(printf '%s' "${CATALOGUE}" |
    python3 "${MODULE_DIR}/render_config.py" --resolve "${DOTENV}" "${name}" 2>"${err}")"; then
    cat "${err}" >&2 || true
    rm -f "${err}"
    _die "connection '${name}': could not render its resolved config"
  fi
  missing="$(tr '\n' ' ' <"${err}")"
  rm -f "${err}"

  # Checked BEFORE publishing: a document that still carries `${VAR}` is not a
  # config, and a launch or check that fails must not leave a file behind that
  # names this connection's other, resolved credentials.
  if [[ -n "${missing// /}" ]]; then
    if [[ "${lenient}" == "1" ]]; then
      echo "kafka-mcp: connection '${name}': '${missing% }' resolves to nothing — the launcher will refuse to start until it is exported" >&2
      return 3
    fi
    _die "connection '${name}': '${missing% }' is referenced in the config but resolves to nothing"
  fi

  # Content-addressed: two launches whose resolved configs differ (another
  # project, another set of credentials) cannot overwrite each other's file
  # between the render and the server's read. SHA-256, not a CRC: a 32-bit digest
  # is collidable, and a collision here would silently share a credential file.
  hash="$(printf '%s' "${content}" |
    python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:16])')" ||
    _die "connection '${name}': could not digest its config"
  PUBLISHED_CONFIG="${RUNTIME_DIR}/${name}-${hash}.yaml"
  tmp="$(mktemp "${RUNTIME_DIR}/.${name}.XXXXXX")" || _die "cannot write to ${RUNTIME_DIR}"
  LAUNCH_TEMPS+=("${tmp}")
  chmod 600 "${tmp}" 2>/dev/null || true
  if ! _kafka_mode_private "${tmp}"; then
    _die "cannot make ${PUBLISHED_CONFIG} private (mode 0600) — refusing to write kafka credentials to a readable file"
  fi
  printf '%s\n' "${content}" >"${tmp}"
  mv "${tmp}" "${PUBLISHED_CONFIG}"

  # Retention: a resolved file is only needed until the server has read it, and
  # the server parses its config at startup. Anything an hour old is a rotated
  # credential nobody is waiting on — keeping it would turn storage/kafka into an
  # archive of passwords. The window is what makes this safe against a launch
  # that is still reading. Done in python: `find -mmin -delete` is not reliably
  # portable, and python is already this module's dependency.
  python3 -c '
import os, sys, time

root, prefix, keep = sys.argv[1], sys.argv[2] + "-", sys.argv[3]
cutoff = time.time() - 3600
for entry in os.listdir(root):
    if entry == keep or not entry.startswith(prefix) or not entry.endswith(".yaml"):
        continue
    path = os.path.join(root, entry)
    try:
        if os.path.getmtime(path) < cutoff:
            os.remove(path)
    except OSError:
        pass
' "${RUNTIME_DIR}" "${name}" "$(basename "${PUBLISHED_CONFIG}")" || true

  return "${rc}"
}

# Run a command with a hard cap, stdin closed. A wedged server must not block
# `devbot reinit`, and GNU `timeout` is absent on macOS, so this is a portable
# bash watchdog (the same pattern as bin/update.sh's tag fetch).
_bounded() {
  local cap="$1" pid waited=0
  shift
  "$@" </dev/null >"${SERVER_OUT}" 2>&1 &
  pid=$!
  while kill -0 "${pid}" 2>/dev/null; do
    if [[ "${waited}" -ge "${cap}" ]]; then
      kill "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "${pid}"
}

# Prove the installed server actually accepts what was rendered. The server
# parses the config and the flag pair at startup and exits on stdin EOF, so this
# is a hermetic config check that needs no reachable broker — and it is the only
# thing that can catch a schema change in an upgrade.
preflight() {
  local mcp_path rc=0 detail
  mcp_path="$(_kafka_mcp_binary)" || {
    echo "kafka-mcp: '${CONNECTION}' config validated; ${MCP_BINARY} not installed, startup unchecked" >&2
    return 0
  }
  SERVER_OUT="$(mktemp "${TMPDIR:-/tmp}/devbot-kafka-preflight.XXXXXX")"
  # Escaped, and expanded now: TMPDIR is ambient, so a quote in it must not
  # become shell syntax in the trap.
  # shellcheck disable=SC2064
  trap "rm -f $(printf '%q' "${SERVER_OUT}")" RETURN
  _server_env
  _bounded 15 "${SERVER_ENV[@]}" "${mcp_path}" --config "${PUBLISHED_CONFIG}" \
    --allow-tools "${ALLOWED_TOOLS}" || rc=$?
  [[ "${rc}" -eq 0 ]] && return 0
  detail="$(tail -n 3 "${SERVER_OUT}" | tr '\n' ' ')"
  if [[ "${rc}" -eq 124 ]]; then
    _die "connection '${CONNECTION}': ${MCP_BINARY} did not exit within 15s during its config check"
  fi
  _die "connection '${CONNECTION}': ${MCP_BINARY} rejected the rendered config (exit ${rc}): ${detail}"
}

# The server's whole environment. It configures the wrapper, not the connection:
# every credential is in the 0600 config, so an ambient secret the harness
# exported stays unreadable to this third-party process.
_server_env() {
  SERVER_ENV=(env -i "PATH=${PATH}" "DO_NOT_TRACK=1")
  if [[ -n "${HOME:-}" ]]; then SERVER_ENV+=("HOME=${HOME}"); fi
  if [[ -n "${TMPDIR:-}" ]]; then SERVER_ENV+=("TMPDIR=${TMPDIR}"); fi
  if [[ -n "${LANG:-}" ]]; then SERVER_ENV+=("LANG=${LANG}"); fi
}

case "${MODE}" in
  --print-config)
    # References intact and literals masked: this output may be read, pasted or
    # logged, and a `${VAR}` name is useful where its value is not.
    printf '%s' "${CATALOGUE}" |
      python3 "${MODULE_DIR}/render_config.py" --redact "${CONNECTION}" || exit 2
    exit 0
    ;;
  --check)
    # Lenient: a reinit must not unwire a connection whose secret lives
    # elsewhere. An unresolved value skips the startup check, which would fail
    # for that reason alone, and says why.
    rc=0
    _write_config "${CONNECTION}" 1 || rc=$?
    case "${rc}" in
      0) preflight ;;
      3) echo "kafka-mcp: connection '${CONNECTION}' validated (startup not checked: values unresolved)" >&2 ;;
      *) exit "${rc}" ;;
    esac
    if [[ -n "${PUBLISHED_CONFIG}" ]]; then
      echo "kafka-mcp: connection '${CONNECTION}' OK (${PUBLISHED_CONFIG})" >&2
    else
      echo "kafka-mcp: connection '${CONNECTION}' OK" >&2
    fi
    exit 0
    ;;
esac

_write_config "${CONNECTION}" 0

MCP_PATH="$(_kafka_mcp_binary)" ||
  _die "'${MCP_BINARY}' is not installed — run 'devbot install' to install ${MCP_PACKAGE}"

# The server reports usage and runtime errors to Sentry unless DO_NOT_TRACK is
# set; _server_env carries it, so the preflight and the launch agree.
# No --transport: with --config the transport comes from the YAML (default
# stdio), and passing both is a startup error.
_server_env
exec "${SERVER_ENV[@]}" "${MCP_PATH}" --config "${PUBLISHED_CONFIG}" --allow-tools "${ALLOWED_TOOLS}"
