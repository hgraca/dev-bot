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
LAUNCHER="${MODULE_DIR}/tools/aws-mcp-proxy.sh"
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

# Is a harness module turned off? Mirrors the datasources/jetbrains gate.
_aws_harness_disabled() {
  _devbot_get_disabled_modules "${PROJECT_DIR}" |
    jq -e --arg m "$1" 'index($m) != null' >/dev/null 2>&1
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

# Keep the copied rules out of the project's history. The file lands in the
# project's devbot dir, which the memory module deliberately un-ignores
# (`!.agents`), so it cannot inherit that block's protection — it gets its own
# local exclude entry instead of a .gitignore edit, since only this machine
# writes the file.
_aws_exclude_rules() {
  local rel_path="$1"
  [[ -d "${PROJECT_DIR}/.git" ]] || {
    _skip "aws — not a git repo; ${rel_path} not excluded"
    return 0
  }
  if _upsert_gitignore_section "${PROJECT_DIR}/.git/info/exclude" \
    "# >>> DEVBOT - aws" \
    "# <<< DEVBOT - aws" \
    "${rel_path}"; then
    _ok ".git/info/exclude updated (${rel_path})"
  else
    _skip "aws — .git/info/exclude upsert failed"
  fi
}

# A connection name becomes a server name and a filename, so keep it boring.
_aws_valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# The command both manifests run. It is SECRET-FREE: it only names the
# connection — the launcher resolves credentials at launch, from the environment.
# Dynamic manifests are harness-native (never translated), so the harness dir is
# written literally rather than as a {harness-dir} token.
_aws_command() {
  local harness_dir="$1" name="$2"
  printf 'mkdir -p .agents/logs && exec bash %s/%s %s 2>>.agents/logs/%s%s-mcp.log' \
    "${harness_dir}" "${LAUNCHER_NAME}" "${name}" "${PREFIX}" "${name}"
}

# Write the dynamic MCP manifests for one connection. opencode's shape is
# opencode-native (what _register_dynamic_mcps merges verbatim); claudecode's
# matches the .mcp.json contract. Both mirror the datasources module.
#
# The connections are optional per project, so the opencode manifest ships the
# server disabled by default — one flag turns it on without a reinit. The
# claudecode entry keeps `true`: .mcp.json has no per-server on/off, and
# _wire_mcp reads `enabled` as a wire/don't-wire gate, so `false` there would
# silently drop the server from that harness.
_aws_write_manifests() {
  local name="$1"
  local server="${PREFIX}${name}"

  if ! _aws_harness_disabled opencode; then
    local dir="${PROJECT_DIR}/.opencode"
    mkdir -p "${dir}"
    printf '{"%s": {"type": "local", "command": ["bash", "-c", "%s"], "enabled": false}}\n' \
      "${server}" "$(_aws_command ".opencode" "${name}")" > "${dir}/${server}.mcp.json"
  fi

  if ! _aws_harness_disabled claudecode; then
    local dir="${PROJECT_DIR}/.claude"
    mkdir -p "${dir}"
    printf '{"mcpServers": {"%s": {"type": "stdio", "command": "bash", "args": ["-c", "%s"], "enabled": true}}}\n' \
      "${server}" "$(_aws_command ".claude" "${name}")" > "${dir}/${server}.mcp.json"
  fi
}

# Reconcile the opencode config with the selection. The harness merges dynamic
# manifests APPEND-ONLY into opencode.jsonc and nothing removes them, so deleting
# a manifest is not enough: the key stays live and the project keeps a server for
# a connection it has removed. Scanning the CONFIG also cleans up a key left
# behind by an earlier init. claudecode needs nothing — its .mcp.json is
# regenerated from scratch.
_aws_reconcile_opencode() {
  local selected="$1" config="${PROJECT_DIR}/opencode.jsonc"
  [[ -f "${config}" ]] || return 0

  local key name
  for key in $(
    python3 "${READER}" "${config}" mcp 2>/dev/null |
      python3 -c '
import json, sys
try:
    print(" ".join(json.load(sys.stdin)))
except Exception:
    pass
' 2>/dev/null
  ); do
    case "${key}" in
      "${PREFIX}"*) ;;
      *) continue ;; # a server this module does not own
    esac
    name="${key#"${PREFIX}"}"
    if ! printf ' %s ' "${selected}" | grep -Fq " ${name} "; then
      python3 "${REMOVE_KEY}" "${config}" "${key}" \
        >/dev/null 2>&1 || true
      _skip "aws — unregistered ${key} (no longer selected)"
    fi
  done
}

# Remove manifests for connections no longer selected. Without this, dropping a
# connection from the project config would leave its server registered forever.
_aws_prune() {
  local dir="$1" selected="$2" file name
  [[ -d "${dir}" ]] || return 0

  for file in "${dir}/${PREFIX}"*.mcp.json; do
    [[ -e "${file}" ]] || continue
    name="$(basename "${file}")"
    name="${name#"${PREFIX}"}"
    name="${name%.mcp.json}"
    if ! printf ' %s ' "${selected}" | grep -Fq " ${name} "; then
      rm -f "${file}"
      _skip "aws — pruned ${name} (no longer selected)"
    fi
  done
}

# ── main ──────────────────────────────────────────────────────────────────────

main() {
  _header_3 "AWS init — $(basename "${PROJECT_DIR}")"

  # The manifests reference the launcher inside each harness dir, so wire it
  # first (agentic init runs before the harness inits, so the dirs are created
  # here rather than assumed to exist).
  if ! _aws_harness_disabled opencode; then
    mkdir -p "${PROJECT_DIR}/.opencode"
    ln -sf "${LAUNCHER}" "${PROJECT_DIR}/.opencode/${LAUNCHER_NAME}"
    _log "Linked .opencode/${LAUNCHER_NAME}"
  fi
  if ! _aws_harness_disabled claudecode; then
    mkdir -p "${PROJECT_DIR}/.claude"
    ln -sf "${LAUNCHER}" "${PROJECT_DIR}/.claude/${LAUNCHER_NAME}"
    _log "Linked .claude/${LAUNCHER_NAME}"
  fi

  local selected declared name
  selected="$(_aws_selected)"
  declared="$(_aws_declared)"

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
      _ok "aws — ${PREFIX}${name} -> aws-mcp-proxy.sh ${name}"
    done
  fi

  # An `if`, not `&&`: under `set -e` a short-circuited `&&` would abort here.
  if ! _aws_harness_disabled opencode; then
    _aws_reconcile_opencode "${selected}"
    _aws_prune "${PROJECT_DIR}/.opencode" "${selected}"
  fi
  if ! _aws_harness_disabled claudecode; then
    _aws_prune "${PROJECT_DIR}/.claude" "${selected}"
  fi

  # ── AWS agent rules into the project's memory vault ─────────────────────────
  # Only when the module is enabled for this project, and never committed: the
  # rules are machine-local bootstrap content, so they land in the project's
  # devbot dir and go on the local exclude list.
  if _aws_module_disabled; then
    _skip "aws — module disabled for this project; aws-agent-rules.md not written"
  else
    local rules_src="${DEV_BOT_ROOT}/storage/aws/rules/aws-agent-rules.md"
    local project_dir_rel rules_rel memory_dir
    project_dir_rel="$(_devbot_get_project_dir "${PROJECT_DIR}")"
    rules_rel="${project_dir_rel}/memory/active/aws-agent-rules.md"
    memory_dir="${PROJECT_DIR}/${project_dir_rel}/memory/active"

    if [[ -f "${rules_src}" ]]; then
      mkdir -p "${memory_dir}"
      cp "${rules_src}" "${PROJECT_DIR}/${rules_rel}"
      _log "Copied aws-agent-rules.md → ${PROJECT_DIR}/${rules_rel}"
      _aws_exclude_rules "${rules_rel}"
    else
      _warn "AWS rules not found at ${rules_src} — run 'devbot install' first"
    fi
  fi

  _notice "AWS connections are declared in .devbot.global.jsonc → aws_connections."
  _notice "Opt a project in by adding the connection name to .devbot.project.jsonc → aws_connections."

  return 0
}

main "$@"
