#!/usr/bin/env bash
# =============================================================================
# src/agentic/aws/init.sh
# Wire this project's SELECTED AWS connections into its harness.
#
# Connections are declared once in .devbot.global.jsonc (the `aws_connections`
# catalogue) and opted into per project by name in .devbot.project.jsonc. For
# each selected name this script writes the harness's dynamic MCP manifest,
# naming the server `aws-<connection>` and invoking the launcher with that
# connection as its argument — the launcher resolves the credentials.
#
# Scoping is by name: a project sees only the connections its config lists, and a
# deselected one is pruned, so removing it from the project config takes effect on
# the next init.
#
# Manifests are emitted rather than written into the harness config directly —
# modules stay harness-agnostic and the harness applies them (same contract as
# the datasources and jetbrains modules). A config change needs a reinit, which
# the next bare `devbot` start performs automatically.
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
GLOBAL_CONFIG="${DEV_BOT_ROOT}/.devbot.global.jsonc"
PROJECT_CONFIG="${PROJECT_DIR}/.devbot.project.jsonc"
READER="${MODULE_DIR}/../../_shared/read_jsonc.py"
REMOVE_KEY="${MODULE_DIR}/../../_shared/remove_mcp_key.py"

PREFIX="aws-"
LAUNCHER_NAME="aws-mcp-proxy.sh"

# ── helpers ───────────────────────────────────────────────────────────────────

# The connection names this project opted into (a JSON array in its config).
_aws_selected() {
  [[ -f "${PROJECT_CONFIG}" ]] || return 0
  python3 "${READER}" "${PROJECT_CONFIG}" aws_connections 2>/dev/null |
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
_aws_declared() {
  [[ -f "${GLOBAL_CONFIG}" ]] || return 0
  python3 "${READER}" "${GLOBAL_CONFIG}" aws_connections 2>/dev/null |
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = None
print(" ".join(data) if isinstance(data, dict) else "")
' 2>/dev/null || true
}

# Is the aws MODULE itself turned off for this project? Enablement is a user
# decision, and the file this module drops into the vault is machine-local
# bootstrap content — so a project that disabled the module must not receive it.
# `_run_module_script` already skips a disabled module's init.sh; this is the
# module's own guard, which also names the reason instead of failing silently.
_aws_module_disabled() {
  _devbot_get_disabled_modules "${PROJECT_DIR}" |
    jq -e 'index("aws") != null' >/dev/null 2>&1
}

# A connection name becomes a server name and a filename, so keep it boring.
_aws_valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# Publish the connection canonically; the selected harness applies it. The
# launcher path is a {harness-dir} token, so no harness is named here. The
# command is SECRET-FREE: it only names the connection — the launcher resolves
# credentials at launch. Shipped disabled: a connection is opt-in per project.
_aws_write_manifests() {
  local name="$1"
  local server="${PREFIX}${name}"
  local cmd="mkdir -p .agents/logs && exec bash {harness-dir}/${LAUNCHER_NAME} ${name} 2>>.agents/logs/${PREFIX}${name}-mcp.log"
  _devbot_publish_runtime_mcp "${PROJECT_DIR}" "${server}" \
    "$(jq -nc --arg c "${cmd}" \
      "{($server): {type: \"stdio\", command: [\"bash\", \"-c\", \$c], wire_disabled: true}}")"
}

# ── module memory ─────────────────────────────────────────────────────────────

# One file: our rule, then AWS's rules when fetched.
# Two files would leave the CLI fallback live.
_write_memory() {
  local rules_src="${DEV_BOT_ROOT}/storage/aws/rules/aws-agent-rules.md"
  local tmp rc=0

  # A rules-only file would let the CLI fallback stand uncontradicted.
  if [[ ! -f "${MODULE_DIR}/aws.md" ]]; then
    _warn "aws — ${MODULE_DIR}/aws.md is missing; module memory not written"
    return 1
  fi

  tmp="$(mktemp "${TMPDIR:-/tmp}/devbot-aws-memory.XXXXXX")"
  cat "${MODULE_DIR}/aws.md" > "${tmp}"
  if [[ -f "${rules_src}" ]]; then
    printf '\n' >> "${tmp}"
    cat "${rules_src}" >> "${tmp}"
  else
    _warn "AWS rules not found at ${rules_src} — run 'devbot install' first"
  fi
  # mktemp is 600; a memory file has to be readable by the harness user.
  chmod 644 "${tmp}"
  _devbot_write_module_memory "${PROJECT_DIR}" "aws.md" "${tmp}" || rc=$?
  rm -f -- "${tmp}"
  return "${rc}"
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  _header_3 "AWS init — $(basename "${PROJECT_DIR}")"

  # The manifests reference the launcher inside each harness dir, so wire it
  # first (agentic init runs before the harness inits, so the dirs are created
  # here rather than assumed to exist).
  # The harness links this module's declared MCP assets (mcp.json "assets").
  # The harness links this module's declared MCP assets (mcp.json "assets").
  local selected declared name wired=0 mcp_available=0
  selected="$(_aws_selected)"
  declared="$(_aws_declared)"

  # The memory file says the MCP servers are the way in, so it may only be
  # written when a harness can start them. Which harness that is belongs to the
  # harness — retracting the manifest is a module-level decision only.
  mcp_available=1

  for name in ${selected}; do
    if ! _aws_valid_name "${name}"; then
      _warn "aws — '${name}' is not a valid connection name (letters, digits, dot, dash, underscore)"
      continue
    fi
    if ! printf ' %s ' "${declared}" | grep -Fq " ${name} "; then
      # A typo would otherwise register a server whose launcher exits at launch —
      # visible only when the agent first calls it.
      _warn "aws — '${name}' is selected but not declared in .devbot.global.jsonc"
    fi
  done

  if [[ -z "${selected}" ]]; then
    _skip "aws — no connections selected in .devbot.project.jsonc"
  else
    for name in ${selected}; do
      _aws_valid_name "${name}" || continue
      if ! printf ' %s ' "${declared}" | grep -Fq " ${name} "; then
        # Never wire a server that cannot start: a manifest for an undeclared
        # connection would register an MCP server whose launcher dies at launch,
        # surfacing only when the agent first calls it. The warning above is the
        # whole signal.
        continue
      fi
      _aws_write_manifests "${name}"
      wired=1
      _ok "aws — ${PREFIX}${name} -> aws-mcp-proxy.sh ${name}"
    done
  fi

  local -a keep=()
  for name in ${selected}; do keep+=("${PREFIX}${name}"); done
  _devbot_prune_runtime_mcp "${PROJECT_DIR}" "${PREFIX}" ${keep[@]+"${keep[@]}"}
  _devbot_apply_runtime_mcps "${PROJECT_DIR}"

  # ── AWS agent memory ─────────────────────────────────────────────────────────
  # One memory file, only when a server is wired:
  # it says use the MCP, so it must not claim none.
  # The pre-`active/modules/` copy is a cleanup, never a second source.
  _devbot_remove_legacy_module_memory "${PROJECT_DIR}" "aws-agent-rules.md"
  _devbot_remove_module_memory "${PROJECT_DIR}" "aws-agent-rules.md"

  if _aws_module_disabled; then
    _devbot_remove_module_memory "${PROJECT_DIR}" "aws.md"
    _skip "aws — module disabled for this project; aws.md not written"
  elif [[ "${wired}" -eq 1 && "${mcp_available}" -eq 1 ]]; then
    if _write_memory; then
      _log "Wrote aws.md → $(_devbot_get_project_dir "${PROJECT_DIR}")/memory/active/modules/aws.md"
    fi
  else
    _devbot_remove_module_memory "${PROJECT_DIR}" "aws.md"
    _skip "aws — no connection wired; aws.md not written"
  fi

  _notice "AWS connections are declared in .devbot.global.jsonc → aws_connections."
  _notice "Opt a project in by adding the connection name to .devbot.project.jsonc → aws_connections."

  return 0
}

main "$@"
