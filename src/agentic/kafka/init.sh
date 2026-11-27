#!/usr/bin/env bash
# =============================================================================
# src/agentic/kafka/init.sh
# Wire this project's SELECTED Kafka connections into its harness.
#
# Connections are declared once in .devbot.global.jsonc (the `kafka_connections`
# catalogue) and opted into per project by name in .devbot.project.jsonc. For
# each selected name this script writes the harness's dynamic MCP manifest,
# naming the server `kafka-<connection>` and invoking the launcher with that
# connection as its argument — the launcher resolves the credentials and renders
# the config.
#
# Scoping is by name: a project sees only the connections its config lists, and a
# deselected one is pruned, so removing it from the project config takes effect on
# the next init.
#
# Manifests are emitted rather than written into the harness config directly —
# modules stay harness-agnostic and the harness applies them (same contract as
# the aws and datasources modules). A config change needs a reinit, which the
# next bare `devbot` start performs automatically.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"
LAUNCHER_NAME="kafka-mcp-launch.sh"

# ── helpers ───────────────────────────────────────────────────────────────────

# Publish the connection canonically; the selected harness applies it. The
# command is SECRET-FREE: it only names the connection — the launcher resolves
# credentials and renders the config at launch. Shipped disabled: a connection
# is opt-in per project.
_kafka_write_manifests() {
  local name="$1" server logs log_file
  server="${PREFIX}${name}"
  # Relative to the project root, the harness's working directory. The path is
  # project-owned (`devbot_dir`), so it is shell-escaped before it enters the
  # command string: a state directory with a space, or with a metacharacter,
  # must not change — or execute — the launch command.
  logs="$(printf '%q' "$(_devbot_get_project_dir "${PROJECT_DIR}")/logs")"
  log_file="$(printf '%q' "$(_devbot_get_project_dir "${PROJECT_DIR}")/logs/${server}-mcp.log")"
  local cmd="mkdir -p ${logs} && exec bash {harness-dir}/${LAUNCHER_NAME} ${name} 2>>${log_file}"
  _devbot_publish_runtime_mcp "${PROJECT_DIR}" "${server}" \
    "$(jq -nc --arg s "${server}" --arg c "${cmd}" \
      '{($s): {type: "stdio", command: ["bash", "-c", $c], wire_disabled: true}}')"
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  _header_3 "Kafka init — $(basename "${PROJECT_DIR}")"

  # The module gate comes first: a disabled module must publish nothing, so an
  # init invoked directly (by a test, a person, another script) cannot wire a
  # server the user turned off. The runner skips this script; this guard makes
  # that a property of the module rather than of its caller.
  if _kafka_module_disabled "${PROJECT_DIR}"; then
    _devbot_remove_module_memory "${PROJECT_DIR}" "kafka.md"
    # Retire what an earlier init wired. A disabled module that leaves its
    # server registered is a module that still launches on the next client
    # start — the manifests go first, then the harness entries that name them.
    _devbot_prune_runtime_mcp "${PROJECT_DIR}" "${PREFIX}"
    _devbot_apply_runtime_mcps "${PROJECT_DIR}"
    _skip "kafka — module disabled for this project; nothing wired"
    return 0
  fi

  local selected declared name check_reason wired=0
  selected="$(_kafka_selected "${PROJECT_DIR}")"
  declared="$(_kafka_declared)"

  # Split the names into an array: an unquoted `for name in ${selected}` performs
  # pathname expansion first, so a project that selects "*" would wire whatever
  # happens to match a filename in the working directory.
  local -a names=()
  read -r -a names <<<"${selected}"

  # One loop, so `keep` is exactly what got wired: a connection that fails any
  # check must also lose the manifest an earlier init published, or the harness
  # keeps a registered server whose launcher dies at launch.
  local -a keep=()
  for name in ${names[@]+"${names[@]}"}; do
    if ! _kafka_valid_name "${name}"; then
      _warn "kafka — '${name}' is not a valid connection name (letters, digits, dot, dash, underscore)"
      continue
    fi
    if ! _kafka_has_word "${name}" "${declared}"; then
      # A typo would otherwise register a server whose launcher exits at launch —
      # visible only when the agent first calls it.
      _warn "kafka — '${name}' is selected but not declared in .devbot.global.jsonc"
      continue
    fi
    # --check renders the config and, when the server is installed, proves the
    # server accepts it: a schema change in an upgrade is caught here rather
    # than at the agent's first call.
    if ! check_reason="$(bash "${MODULE_DIR}/tools/kafka-mcp-launch.sh" --check "${name}" 2>&1 >/dev/null)"; then
      _warn "kafka — '${name}' could not be wired: ${check_reason#kafka-mcp: }"
      continue
    fi
    # A successful check can still carry a warning worth surfacing — a
    # credential this process cannot see, for instance.
    if [[ -n "${check_reason}" ]]; then
      _warn "kafka — '${name}': ${check_reason#kafka-mcp: }"
    fi
    _kafka_write_manifests "${name}"
    keep+=("${PREFIX}${name}")
    wired=1
    _ok "kafka — ${PREFIX}${name} -> ${LAUNCHER_NAME} ${name}"
  done

  if [[ -z "${selected}" ]]; then
    _skip "kafka — no connections selected in .devbot.project.jsonc"
  fi

  _devbot_prune_runtime_mcp "${PROJECT_DIR}" "${PREFIX}" ${keep[@]+"${keep[@]}"}
  _devbot_apply_runtime_mcps "${PROJECT_DIR}"

  # ── Kafka agent memory ───────────────────────────────────────────────────────
  # One memory file, only when a server is wired: it says to use the MCP, so it
  # must not claim none is there.
  if [[ "${wired}" -eq 1 ]]; then
    if _devbot_write_module_memory "${PROJECT_DIR}" "kafka.md" "${MODULE_DIR}/kafka.md"; then
      _log "Wrote kafka.md → $(_devbot_get_project_dir "${PROJECT_DIR}")/memory/active/modules/kafka.md"
    fi
  else
    _devbot_remove_module_memory "${PROJECT_DIR}" "kafka.md"
    _skip "kafka — no connection wired; kafka.md not written"
  fi

  _notice "Kafka connections are declared in .devbot.global.jsonc → kafka_connections."
  _notice "Opt a project in by adding the connection name to .devbot.project.jsonc → kafka_connections."

  return 0
}

main "$@"
