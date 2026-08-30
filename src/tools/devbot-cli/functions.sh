#!/usr/bin/env bash
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.
# Also provides _link_* functions for wiring agents/commands/skills/tools
# into .agents/ (dual-wired alongside .opencode/).

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# ── Link module agents into .agents/ ────────────────────────────────────────────
_link_agents() {
  local mod_dir="$1"
  local agent_dir="${mod_dir}agents"
  [[ ! -d "${agent_dir}" ]] && return
  local mod_name
  mod_name="$(basename "${mod_dir}")"
  local link_name="${AGENTS_DIR}/agents/${mod_name}"

  if [[ -L "${link_name}" ]]; then
    local current
    current="$(readlink "${link_name}")"
    if [[ "${current}" == "${agent_dir}" ]]; then
      _skip "agents/${mod_name} already linked"
    else
      rm -f "${link_name}"
      ln -sf "${agent_dir}" "${link_name}"
      _ok "agents/${mod_name} relinked"
    fi
  elif [[ -e "${link_name}" ]]; then
    _warn "agents/${mod_name} exists but is not a symlink"
  else
    mkdir -p "$(dirname "${link_name}")"
    ln -sf "${agent_dir}" "${link_name}"
    _ok "agents/${mod_name} linked"
  fi
}

# ── Link module commands into .agents/ ──────────────────────────────────────────
# Each command file is symlinked individually under .agents/commands/devbot/,
# NAMED after its frontmatter name (devbot:audit → devbot/audit.md). This makes
# both harnesses expose the same slash command: opencode reads the frontmatter
# `name:` (devbot:audit), while claudecode derives `<dir>:<file>` from the path
# — a category symlink of the module dir would render devbot/devbot-audit.md as
# `devbot:devbot-audit` (wrong). The devbot/ category + bare-name file gives
# claudecode the matching `devbot:audit`.
_link_commands() {
  local mod_dir="$1"
  local cmd_dir="${mod_dir}commands"
  [[ ! -d "${cmd_dir}" ]] && return

  local target_dir="${AGENTS_DIR}/commands/devbot"
  local f name bare link current
  for f in "${cmd_dir}"/*.md; do
    [[ -f "${f}" ]] || continue
    name="$(sed -n 's/^name:[[:space:]]*//p' "${f}" | head -1 | tr -d '"')"
    bare="${name#devbot:}"
    [[ -n "${bare}" ]] || continue

    mkdir -p "${target_dir}"
    link="${target_dir}/${bare}.md"
    if [[ -L "${link}" ]]; then
      current="$(readlink "${link}")"
      if [[ "${current}" == "${f}" ]]; then
        _skip "commands/${bare} already linked"
      else
        rm -f "${link}"
        ln -sf "${f}" "${link}"
        _ok "commands/${bare} relinked"
      fi
    elif [[ -e "${link}" ]]; then
      _warn "commands/${bare} exists but is not a symlink"
    else
      ln -sf "${f}" "${link}"
      _ok "commands/${bare} linked"
    fi
  done
}

# ── Link skills into .agents/ ───────────────────────────────────────────────────
_link_skills() {
  local mod_dir="$1"
  local skill_dir="${mod_dir}skills"
  [[ ! -d "${skill_dir}" ]] && return
  local mod_name
  mod_name="$(basename "${mod_dir}")"
  local link_name="${AGENTS_DIR}/skills/devbot/${mod_name}"

  if [[ -L "${link_name}" ]]; then
    local current
    current="$(readlink "${link_name}")"
    if [[ "${current}" == "${skill_dir}" ]]; then
      _skip "skills/devbot/${mod_name} already linked"
    else
      rm -f "${link_name}"
      ln -sf "${skill_dir}" "${link_name}"
      _ok "skills/devbot/${mod_name} relinked"
    fi
  elif [[ -e "${link_name}" ]]; then
    _warn "skills/devbot/${mod_name} exists but is not a symlink"
  else
    mkdir -p "$(dirname "${link_name}")"
    ln -sf "${skill_dir}" "${link_name}"
    _ok "skills/devbot/${mod_name} linked"
  fi
}

# ── Link MCP tools into .agents/ ────────────────────────────────────────────────
_link_tools() {
  local mod_dir="$1"
  local tool_dir="${mod_dir}tools"
  [[ ! -d "${tool_dir}" ]] && return
  local mod_name
  mod_name="$(basename "${mod_dir}")"

  while IFS= read -r -d '' tool_file; do
    local tool_name
    tool_name="$(basename "${tool_file}")"

    # Only *.mcp.sh files are devbot-tools MCP tools. Skip helper scripts
    # (.ts hook targets, .sh CLIs/workers, .py implementations).
    if [[ "${tool_name}" != *.mcp.sh ]]; then
      continue
    fi

    local target="${tool_file}"
    local link="${AGENTS_DIR}/tools/${tool_name}"

    if [[ -L "${link}" ]]; then
      local current
      current="$(readlink "${link}")"
      if [[ "${current}" == "${target}" ]]; then
        _skip "tools/${tool_name} already linked"
      else
        rm -f "${link}"
        ln -sf "${target}" "${link}"
        _ok "tools/${tool_name} relinked"
      fi
    elif [[ -e "${link}" ]]; then
      _warn "tools/${tool_name} exists but is not a symlink"
    else
      mkdir -p "$(dirname "${link}")"
      ln -sf "${target}" "${link}"
      _ok "tools/${tool_name} linked"
    fi
  done < <(find "${tool_dir}" -maxdepth 3 -name '*.mcp.sh' -type f -print0 2>/dev/null)
}

# ── Wire all modules into devbot_dir (agents, commands, skills, tools) ──────────
_link_modules() {
  AGENTS_DIR="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")"

  # Resolve disabled modules
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

  local -a mod_dirs=("${DEV_BOT_ROOT}/src/agentic/"*/)
  mod_dirs+=("${DEV_BOT_ROOT}/src/tools/"*/)

  for mod_dir in "${mod_dirs[@]}"; do
    local mod_name
    mod_name="$(basename "${mod_dir}")"

    # Skip ENTIRE module if disabled — no symlinks created
    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
      _skip "${mod_name}: disabled per config — skipping"
      continue
    fi

    _link_agents "${mod_dir}"
    _link_commands "${mod_dir}"
    _link_skills "${mod_dir}"
    _link_tools "${mod_dir}"
  done
}
