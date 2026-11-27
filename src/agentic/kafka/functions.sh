#!/usr/bin/env bash
# src/agentic/kafka/functions.sh
# Thin wrapper: sources the root shared library, then pins this module's
# constants so init.sh, pre.sh and the launcher cannot disagree about them.
set -euo pipefail
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MODULE_DIR
source "${MODULE_DIR}/../../_shared/functions.sh"
_devbot_versions_env_source "${MODULE_DIR}"

# The server key AND the runtime-manifest group prefix. A harness attributes a
# dynamic manifest to a module by its filename (`<module>.mcp.json` /
# `<module>-<detail>.mcp.json`), so both must start with the module's own name.
# shellcheck disable=SC2034  # consumed by the scripts that source this file
PREFIX="kafka-"

# What install.sh installs and the launcher execs.
# shellcheck disable=SC2034  # consumed by install.sh, update.sh and pre.sh
MCP_PACKAGE="@confluentinc/mcp-confluent"
MCP_BINARY="mcp-confluent"

# The tools the server is ALLOWED to register — read-only diagnostics plus a
# bounded consume. produce-message, create-topics, delete-topics and
# alter-topic-config are absent by design: `--allow-tools` is the write gate,
# not a prompt instruction an agent could talk itself past.
#
# get-topic-config is deliberately absent too: its per-connection predicate
# needs the Confluent Cloud REST fields (rest_endpoint + cluster_id + env_id) and
# a named auth block, so for a direct Kafka connection it never registers and
# allowlisting it would promise a tool the session cannot call.
# shellcheck disable=SC2034  # consumed by the scripts that source this file
ALLOWED_TOOLS="list-topics,get-partition-offsets,list-consumer-groups,describe-consumer-group,get-consumer-group-lag,consume-messages,list-schemas,explain-disabled-tools"

# Rendered connection configs. Machine-local (storage/ is gitignored) and
# PRIVATE: the launcher resolves every reference before writing, so this file is
# where a credential sits (0600, in a 0700 directory). `--print-config` shows the
# unresolved document on purpose.
KAFKA_RUNTIME_DIR="${KAFKA_RUNTIME_DIR:-${DEV_BOT_ROOT}/storage/kafka}"

# The connection names this project opted into (a JSON array in its config).
_kafka_selected() {
  local config="${1:-$(pwd)}/.devbot.project.jsonc"
  [[ -f "${config}" ]] || return 0
  python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${config}" kafka_connections 2>/dev/null |
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = None
print(" ".join(data) if isinstance(data, list) else "")
' 2>/dev/null || true
}

# The connection names the machine declares (keys of the global catalogue).
_kafka_declared() {
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ -f "${config}" ]] || return 0
  python3 "${MODULE_DIR}/../../_shared/read_jsonc.py" "${config}" kafka_connections 2>/dev/null |
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = None
print(" ".join(data) if isinstance(data, dict) else "")
' 2>/dev/null || true
}

# Is <needle> one space-separated word of <haystack>? Never `writer | grep -q`:
# grep exits on the first match, the writer takes SIGPIPE on its next write, and
# pipefail reports the pipeline as failed — so a name that IS in a long list
# reads as absent. A here-string is not a pipeline.
_kafka_has_word() {
  grep -Fq -- " $1 " <<< " $2 "
}

# A connection name becomes a server name, a filename and a YAML mapping key, so
# keep it boring: no leading dot or dash (`.`/`..` are not names, and a leading
# dash reads as an option to a CLI), and nothing outside the safe set.
_kafka_valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]
}


# Are the group and other permission bits on <path> clear? The rendered config
# holds resolved credentials, so a 0700 directory and a 0600 file are a
# guarantee, not a nicety — and a filesystem that ignores modes cannot be
# trusted with them. GNU stat first, then BSD.
_kafka_mode_private() {
  local mode
  mode="$(stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || true)"
  [[ -n "${mode}" && "${mode: -2}" == "00" ]]
}

# Is the kafka MODULE itself turned off for this project? `_run_module_script`
# already skips a disabled module's init.sh; this is the module's own guard, so
# the reason is named instead of failing silently.
_kafka_module_disabled() {
  _devbot_get_disabled_modules "${1:-$(pwd)}" |
    jq -e 'index("kafka") != null' >/dev/null 2>&1
}

# Is <a> >= <b>, comparing dot-separated numbers? Bash-native: `sort -V` is
# GNU-only, and macOS has no equivalent. One implementation, so install.sh and
# pre.sh cannot disagree about whether a Node version clears the floor.
_kafka_version_ge() {
  local IFS=. i x y
  local -a left right
  read -r -a left <<<"$1"
  read -r -a right <<<"$2"
  for ((i = 0; i < 3; i++)); do
    x="${left[i]:-0}"
    y="${right[i]:-0}"
    if ((x > y)); then return 0; fi
    if ((x < y)); then return 1; fi
  done
  return 0
}

# The installed server executable, or non-zero. Single source of truth for "is
# the server available?": pre.sh and the launcher must not disagree, and a
# global npm prefix that is not on PATH is still a usable install.
_kafka_mcp_binary() {
  local path prefix
  # npm's global prefix is where install.sh puts the server, so it is resolved
  # FIRST: a binary earlier on PATH from some other prefix would otherwise be
  # the one a launch ran, and the version the pin names would not be the version
  # in play. PATH is the fallback for a machine that manages the binary itself.
  if command -v npm >/dev/null 2>&1; then
    prefix="$(npm prefix -g 2>/dev/null || true)"
    if [[ -n "${prefix}" && -x "${prefix}/bin/${MCP_BINARY}" ]]; then
      printf '%s\n' "${prefix}/bin/${MCP_BINARY}"
      return 0
    fi
  fi
  path="$(command -v "${MCP_BINARY}" 2>/dev/null || true)"
  [[ -n "${path}" && -x "${path}" ]] || return 1
  printf '%s\n' "${path}"
}

# The allowlist names the installed server no longer advertises, space-joined.
# `--allow-tools` ignores an unknown name with a warning rather than failing, so
# an upgrade that renames a tool shrinks the surface silently unless this is
# checked before the pin moves (update.sh does).
_kafka_missing_tools() {
  local binary tools list name missing=""
  binary="$(_kafka_mcp_binary)" || return 1
  tools="${ALLOWED_TOOLS//,/ }"
  # The listing is colourised when the CLI thinks it is on a terminal, and 1.6.1
  # puts the escapes between the indent, the name and the colon. Both are
  # handled: colour is asked off, then any escape sequence is stripped — a
  # listing we cannot parse must never read as "every tool is missing".
  # DO_NOT_TRACK travels with the probe too: this runs from `devbot update`, and
  # the server would otherwise report its own startup.
  list="$(DO_NOT_TRACK=1 NO_COLOR=1 FORCE_COLOR=0 "${binary}" --list-tools 2>/dev/null |
    sed $'s/\033\[[0-9;]*[A-Za-z]//g' || true)"
  [[ -n "${list}" ]] || return 1
  for name in ${tools}; do
    # The catalogue prints `<category>:` then `  <tool>: <description>`, so a
    # name that survives a rename is present at the start of a line.
    # A here-string, not `printf | grep -q`: under pipefail the SIGPIPE a match
    # gives the writer makes the pipeline fail, which reads as a missing tool.
    grep -qE "^[[:space:]]+${name}: " <<<"${list}" || missing="${missing} ${name}"
  done
  printf '%s\n' "${missing# }"
}
