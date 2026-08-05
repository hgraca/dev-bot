#!/usr/bin/env bash
# =============================================================================
# src/tools/claudecode/init.sh
# Sets up Claude Code in a project: copies the .claude/ template directory,
# writes .claude/settings.local.json from the dist template, creates symlinks
# for agents, commands, skills, tools, and plugins, and removes .gitkeep files.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  echo "Error: directory '${1:-.}' does not exist or cannot be resolved." >&2
  exit 1
fi

# shellcheck source=../_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── Paths ──────────────────────────────────────────────────────────────────────

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
CLAUDE_TPL="${MODULE_DIR}/_claudecode.tpl"
DIST_CONFIG="${MODULE_DIR}/claudecode.dist.json"
CLAUDE_DIR="${PROJECT_DIR}/.claude"

# ── Merge .claude/ template directory ───────────────────────────────────────
_copy_claude_dir() {
  if [[ ! -d "${CLAUDE_TPL}" ]]; then
    _warn "Template directory not found at ${CLAUDE_TPL}"
    return 1
  fi

  local copied=0
  mkdir -p "${CLAUDE_DIR}"

  while IFS= read -r -d '' src_file; do
    local rel="${src_file#${CLAUDE_TPL}/}"
    local tgt="${CLAUDE_DIR}/${rel}"

    [[ "$(basename "${rel}")" == ".gitkeep" ]] && return

    if [[ -e "${tgt}" ]]; then
      _skip "${rel} already exists"
    else
      mkdir -p "$(dirname "${tgt}")"
      cp -r "${src_file}" "${tgt}"
      _ok "${rel} copied"
      copied=$((copied + 1))
    fi
  done < <(find "${CLAUDE_TPL}" -mindepth 1 -print0 2>/dev/null | sort -z)

  if [[ ${copied} -eq 0 ]]; then
    _skip "no new files from template"
  fi
}

# ── Remove .gitkeep files ────────────────────────────────────────────────────
_remove_gitkeep_files() {
  local count=0
  while IFS= read -r -d '' f; do
    rm -f "$f"
    count=$((count + 1))
  done < <(find "${CLAUDE_DIR}" -name '.gitkeep' -type f -print0 2>/dev/null)
  if [[ ${count} -gt 0 ]]; then _ok "Removed ${count} .gitkeep file(s) from .claude/"; fi
}

# ── Link plugins (shell scripts only) ──────────────────────────────────────
_link_plugins() {
  local mod_dir="$1"
  local hook_dir="${mod_dir}/hooks/claudecode"
  [[ ! -d "${hook_dir}" ]] && return
  local mod_name
  mod_name="$(basename "${mod_dir}")"

  while IFS= read -r -d '' plugin_file; do
    local plugin_name
    plugin_name="$(basename "${plugin_file}")"

    # Only link .sh files (hook .json configs are merged into settings.local.json)
    [[ "${plugin_name}" == *.sh ]] || continue

    local target="${plugin_file}"
    local link="${CLAUDE_DIR}/plugins/${plugin_name}"

    if [[ -L "${link}" ]]; then
      local current
      current="$(readlink "${link}")"
      if [[ "${current}" == "${target}" ]]; then
        _skip "plugins/${plugin_name} already linked"
      else
        rm -f "${link}"
        ln -sf "${target}" "${link}"
        _ok "plugins/${plugin_name} relinked"
      fi
    elif [[ -e "${link}" ]]; then
      _warn "plugins/${plugin_name} exists but is not a symlink"
    else
      mkdir -p "$(dirname "${link}")"
      ln -sf "${target}" "${link}"
      _ok "plugins/${plugin_name} linked"
    fi
  done < <(find "${hook_dir}" -maxdepth 1 -type f -name '*.sh' -print0 2>/dev/null)
}

# ── Wire plugin hooks into settings.local.json ──────────────────────────────
# Reads hooks/claudecode/*.json from each module, merges into settings hooks.
_wire_plugin_hooks() {
  local config="${CLAUDE_DIR}/settings.local.json"
  [[ -f "${config}" ]] || return 0

  local merged=0

  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    local hook_dir="${mod_dir}/hooks/claudecode"
    [[ -d "${hook_dir}" ]] || continue

    while IFS= read -r -d '' json_file; do
      python3 -c "
import json

with open('${config}') as f:
    settings = json.load(f)
with open('${json_file}') as f:
    new_hooks = json.load(f)

hooks = settings.setdefault('hooks', {})
added = 0

for event, entries in new_hooks.items():
    existing = hooks.setdefault(event, [])
    for entry in entries:
        if entry not in existing:
            existing.append(entry)
            added += 1

if added > 0:
    with open('${config}', 'w') as f:
        json.dump(settings, f, indent=2)
        f.write('\n')
" 2>/dev/null

      local mod_name hook_name
      mod_name="$(basename "$(dirname "$(dirname "${hook_dir}")")")"
      hook_name="$(basename "${json_file}")"
      _ok "plugin hook: ${mod_name}/${hook_name} merged"
      merged=$((merged + 1))
    done < <(find "${hook_dir}" -maxdepth 1 -type f -name '*.json' -print0 2>/dev/null)
  done

  if [[ ${merged} -gt 0 ]]; then
    _ok "${merged} plugin hook(s) merged into .claude/settings.local.json"
  fi
}

# ── Write .claude/settings.local.json from template ──────────────────────────
_write_claude_config() {
  local config="${CLAUDE_DIR}/settings.local.json"

  if [[ -f "${config}" ]]; then
    _skip ".claude/settings.local.json already exists"
    return 0
  fi

  if [[ ! -f "${DIST_CONFIG}" ]]; then
    _warn "Template not found at ${DIST_CONFIG}"
    return 1
  fi

  _info "Writing .claude/settings.local.json..."
  cp "${DIST_CONFIG}" "${config}"
  _ok ".claude/settings.local.json written"
}

_link_plugins_modules() {
  # Resolve disabled modules
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | python3 -c "
import json, sys
modules = json.loads(sys.stdin.read())
for m in modules:
    print(m)
" 2>/dev/null || true)

  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    local mod_name
    mod_name="$(basename "${mod_dir}")"

    # Skip ENTIRE module if disabled — no symlinks created
    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
      continue
    fi

    _link_plugins "${mod_dir}"
  done
}

# ── Wire MCP servers from agentic modules ───────────────────────────────────
# Reads mcp.claudecode.json from each module, regenerates .mcp.json from scratch.
# Skips disabled modules (same pattern as _link_modules).
_wire_mcp() {
  local config="${PROJECT_DIR}/.mcp.json"
  local merged=0
  local tmp_servers="/tmp/devbot-claudecode-mcp-$$.json"
  echo '{}' > "${tmp_servers}"

  # Resolve disabled modules
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | python3 -c "
import json, sys
modules = json.loads(sys.stdin.read())
for m in modules:
    print(m)
" 2>/dev/null || true)

  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    local mod_name
    mod_name="$(basename "${mod_dir}")"

    # Skip disabled modules
    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
      continue
    fi

    local mcp_file="${mod_dir}/mcp.claudecode.json"
    [[ -f "${mcp_file}" ]] || continue

    # Merge this module's enabled MCP servers into tmp_servers
    python3 -c "
import json

with open('${tmp_servers}') as f:
    current = json.load(f)
with open('${mcp_file}') as f:
    new_mcp = json.load(f)

for name, entry in new_mcp.get('mcpServers', {}).items():
    if entry.get('enabled', True):
        current[name] = entry

with open('${tmp_servers}', 'w') as f:
    json.dump(current, f)
" 2>/dev/null

    _ok "${mod_name}: MCP registered"
    merged=$((merged + 1))
  done

  # Write .mcp.json
  if [[ ${merged} -gt 0 ]]; then
    python3 -c "
import json
with open('${tmp_servers}') as f:
    servers = json.load(f)
with open('${config}', 'w') as f:
    json.dump({'mcpServers': servers}, f, indent=2)
    f.write('\n')
" 2>/dev/null
    _ok ".mcp.json written with ${merged} MCP server(s)"
  fi

  rm -f "${tmp_servers}"
}

# ── main ─────────────────────────────────────────────────────────────────────
_copy_claude_dir
_write_claude_config
_harness_delegate_to_agents "${CLAUDE_DIR}" "${PROJECT_DIR}"
_link_plugins_modules
_wire_plugin_hooks
_wire_mcp
_remove_gitkeep_files
