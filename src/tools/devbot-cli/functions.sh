#!/usr/bin/env bash
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.
# Also provides _link_* functions for wiring agents/commands/skills/tools
# into .agents/ (dual-wired alongside .opencode/).

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# ── Link module agents into .agents/ ────────────────────────────────────────────
# One link per AGENT, named after the agent's FRONTMATTER NAME:
#   .agents/agents/<name>.md  →  <module>/agents/<file>.md
#
# The link name IS the agent id on an OpenCode 2 host, which derives it from the
# path below `.opencode/agents` (verified: `agents/nested/deep.md` registers as
# `nested/deep`). A module-directory link therefore registered every agent as
# `<module>/<name>`, so the `agents.<name>` entries in opencode.jsonc and
# `default_agent` matched nothing — the host built a prompt-less agent of that
# bare name instead and the session ran with no persona at all (`devbot`,
# `teamlead`, `scout` … all empty; every `@handle` and every "load this skill at
# session start" rule dead). Flat links at the frontmatter name make id == name
# on both harnesses, so the existing config overrides merge into the real agent.
# ── Take a module's agents back out of the farm ────────────────────────────────
# A module disabled after it was linked is skipped by `_link_modules`, so nothing
# would ever reconcile its flat links away and the host would keep serving agents
# the project configuration disabled. Only what this harness created is removed:
# a link into this module's agents dir, and the legacy module-directory link when
# it targets that dir.
_unlink_agents() {
  local mod_dir="$1"
  local reason="${2:-disabled}"
  local agent_dir="${mod_dir}agents"
  local mod_name
  mod_name="$(basename "${mod_dir}")"
  local farm="${AGENTS_DIR}/agents"
  local legacy="${farm}/${mod_name}"

  [[ -d "${farm}" ]] || return 0
  if [[ -L "${legacy}" && "$(readlink "${legacy}")" == "${agent_dir}" ]]; then
    rm -f "${legacy}"
    _ok "agents/${mod_name} pruned (module ${reason})"
  fi
  _prune_agent_links "${farm}" "${agent_dir}" ""
}

# ── Reconcile the flat agent links against what a module ships ─────────────────
# `wanted` is the newline-separated set of names the module links now; an empty
# set prunes every link into the module's agents dir, including dangling ones
# whose directory is gone.
_prune_agent_links() {
  local farm="$1"
  local agent_dir="$2"
  local wanted="$3"

  local stale resolved bare raw
  while IFS= read -r -d '' stale; do
    bare="$(basename "${stale}" .md)"
    if [[ -n "${wanted}" ]] && grep -Fxq -- "${bare}" <<< "${wanted}"; then
      continue
    fi
    resolved="$(_link_target_path "${stale}")"
    if [[ -z "${resolved}" ]]; then
      # A link into a now-missing directory resolves to nothing; normalise the
      # recorded target by hand so it can still be recognised as ours.
      raw="$(readlink "${stale}" 2>/dev/null || true)"
      [[ -n "${raw}" ]] || continue
      [[ "${raw}" == /* ]] || raw="$(dirname "${stale}")/${raw}"
      resolved="${raw}"
    fi
    [[ "${resolved}" == "${agent_dir}"/* ]] || continue
    rm -f "${stale}"
    _ok "agents/${bare} pruned (agent no longer shipped)"
  done < <(find "${farm}" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null)
}

_link_agents() {
  local mod_dir="$1"
  local agent_dir="${mod_dir}agents"
  local mod_name
  mod_name="$(basename "${mod_dir}")"
  local farm="${AGENTS_DIR}/agents"
  local legacy="${farm}/${mod_name}"
  local wanted=""

  if [[ -d "${agent_dir}" ]]; then
    # The module-directory link of the previous shape becomes a flat farm. Only
    # a link this harness created (one targeting this module's agents dir) is
    # ours to remove — a user's own link named after the module stays.
    if [[ -L "${legacy}" ]]; then
      if [[ "$(readlink "${legacy}")" == "${agent_dir}" ]]; then
        rm -f "${legacy}"
      else
        _warn "agents/${mod_name} links outside this module — leaving it"
      fi
    elif [[ -e "${legacy}" ]]; then
      # A real directory or file of this name is not ours to remove, and it does
      # not occupy the flat `<name>.md` entries — so link those anyway.
      _warn "agents/${mod_name} exists but is not our link — leaving it"
    fi
    mkdir -p "${farm}"

    local f name link current resolved
    while IFS= read -r -d '' f; do
      name="$(sed -n 's/^name:[[:space:]]*//p' "${f}" | head -1 | tr -d '\r"' | sed 's/[[:space:]]*$//')"
      [[ -n "${name}" ]] || name="$(basename "${f}" .md)"
      # A name with a path separator would escape the farm.
      [[ "${name}" == */* || "${name}" == "." || "${name}" == ".." ]] && continue
      link="${farm}/${name}.md"
      wanted+="${name}"$'\n'

      if [[ -L "${link}" ]]; then
        current="$(readlink "${link}")"
        if [[ "${current}" == "${f}" ]]; then
          _skip "agents/${name} already linked"
        else
          # Only a link this harness created is ours to re-point — a foreign
          # one (a user's own agent) is left in place, as above.
          resolved="$(_link_target_path "${link}")"
          [[ -n "${resolved}" ]] || resolved="${current}"
          if [[ "${resolved}" == "${agent_dir}"/* ]]; then
            rm -f "${link}"
            ln -sf "${f}" "${link}"
            _ok "agents/${name} relinked"
          else
            _warn "agents/${name}.md links outside this module — leaving it"
          fi
        fi
      elif [[ -e "${link}" ]]; then
        _warn "agents/${name}.md exists but is not a symlink — leaving it"
      else
        ln -sf "${f}" "${link}"
        _ok "agents/${name} linked"
      fi
    done < <(find "${agent_dir}" -mindepth 1 -maxdepth 1 -name '*.md' -type f -print0 2>/dev/null)
  else
    _unlink_agents "${mod_dir}" "ships no agents"
  fi

  # Reconcile: an agent renamed or removed must not keep a link in the farm (the
  # host would advertise an agent that no longer exists).
  _prune_agent_links "${farm}" "${agent_dir}" "${wanted}"
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
# One link per SKILL, named after the skill's FRONTMATTER NAME:
#   .agents/skills/devbot/<module>/<name>  →  <skill dir>
#
# The directory name is the skill's ID on an OpenCode 2 host (SkillScan derives
# it from the SKILL.md's parent directory) while the frontmatter `name` is the
# display name. A `devbot:`-prefixed display name sitting in a plain directory
# (`git-commits`) therefore advertised an id that no caller used and that the
# Skill tool could not resolve — the whole module farm, 82 of 84 skills, was
# unreachable (audit-01 FAIL-4: `skill("devbot:tree")` → "Unable to load
# skill"). Linking AT the frontmatter name makes id == name on both hosts, and
# keeps every `devbot:<skill>` reference in the docs, commands and agent
# instructions valid.
#
# A project links the farm into `.opencode/skills` or reads `.agents/skills`
# directly, so this shape is host-agnostic: one level per skill either way.

# Absolute target of a symlink, without the GNU-only `readlink -f`/`realpath`
# (absent on stock macOS). Resolves the parent directory physically so two
# spellings of the same install compare equal; a dangling link yields nothing.
_link_target_path() {
  local link="$1" target dir
  target="$(readlink "${link}" 2>/dev/null || true)"
  [[ -n "${target}" ]] || return 0
  [[ "${target}" == /* ]] || target="$(dirname "${link}")/${target}"
  dir="$(cd "$(dirname "${target}")" 2>/dev/null && pwd -P)" || return 0
  printf '%s/%s\n' "${dir}" "$(basename "${target}")"
}

_link_skills() {
  local mod_dir="$1"
  local mod_name
  mod_name="$(basename "${mod_dir}")"
  local skill_dir="${mod_dir}skills"

  # A module may produce a machine-local, generated skill dir (e.g. graphify's
  # version-matched skill at storage/graphify/skills). It is preferred ONLY when
  # it carries the `.devbot-generated` sentinel — an explicit opt-in, so an
  # unrelated module's storage/<name>/skills (e.g. signoz, which wires its own
  # skills elsewhere) is never farmed here. The committed skills/ dir stays the
  # fallback.
  local generated="${DEV_BOT_ROOT}/storage/${mod_name}/skills"
  [[ -f "${generated}/.devbot-generated" ]] && skill_dir="${generated}"

  local farm="${AGENTS_DIR}/skills/devbot/${mod_name}"

  # A module that ships no skills must not leave a dangling farm entry behind.
  # Only a link this function created — one pointing at the expected dir, or the
  # per-skill links of the current shape — is ours to remove; links from a
  # previous install root are left alone.
  if [[ ! -d "${skill_dir}" ]]; then
    if [[ -L "${farm}" && "$(readlink "${farm}")" == "${skill_dir}" ]]; then
      rm -f "${farm}"
      _ok "skills/devbot/${mod_name} pruned (module ships no skills)"
    elif [[ -d "${farm}" && ! -L "${farm}" ]]; then
      # Current shape: drop only links that resolve into this module's skills.
      local stale
      while IFS= read -r -d '' stale; do
        local resolved
        resolved="$(_link_target_path "${stale}")"
        [[ "${resolved}" == "${skill_dir}" || "${resolved}" == "${skill_dir}"/* ]] || continue
        rm -f "${stale}"
        _ok "skills/devbot/${mod_name}/$(basename "${stale}") pruned (module ships no skills)"
      done < <(find "${farm}" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null)
      rmdir "${farm}" 2>/dev/null || true
    fi
    return
  fi

  # The module-level symlink of the previous farm shape becomes a real directory
  # of per-skill links.
  if [[ -L "${farm}" ]]; then
    rm -f "${farm}"
  elif [[ -e "${farm}" && ! -d "${farm}" ]]; then
    _warn "skills/devbot/${mod_name} exists but is not a directory — leaving it"
    return
  fi
  mkdir -p "${farm}"

  local wanted=""
  local f name target link
  while IFS= read -r -d '' f; do
    target="$(dirname "${f}")"
    name="$(sed -n 's/^name:[[:space:]]*//p' "${f}" | head -1 | tr -d '\r"' | sed 's/[[:space:]]*$//')"
    [[ -n "${name}" ]] || name="$(basename "${target}")"
    # A name with a path separator would escape the farm.
    [[ "${name}" == */* || "${name}" == "." || "${name}" == ".." ]] && continue
    link="${farm}/${name}"
    wanted+="${name}"$'\n'

    if [[ -L "${link}" ]]; then
      if [[ "$(readlink "${link}")" == "${target}" ]]; then
        _skip "skills/devbot/${mod_name}/${name} already linked"
      else
        rm -f "${link}"
        ln -sf "${target}" "${link}"
        _ok "skills/devbot/${mod_name}/${name} relinked"
      fi
    elif [[ -e "${link}" ]]; then
      _warn "skills/devbot/${mod_name}/${name} exists but is not a symlink"
    else
      ln -sf "${target}" "${link}"
      _ok "skills/devbot/${mod_name}/${name} linked"
    fi
  done < <(find "${skill_dir}" -name SKILL.md -print0 2>/dev/null)

  # Reconcile: a skill renamed or removed from the module must not keep a link
  # in the farm (the host would advertise a skill that no longer exists).
  local stale resolved
  while IFS= read -r -d '' stale; do
    local bare
    bare="$(basename "${stale}")"
    grep -Fxq -- "${bare}" <<< "${wanted}" && continue
    # Only links into THIS module's skill dir are ours to prune.
    resolved="$(_link_target_path "${stale}")"
    [[ "${resolved}" == "${skill_dir}" || "${resolved}" == "${skill_dir}"/* ]] || continue
    rm -f "${stale}"
    _ok "skills/devbot/${mod_name}/${bare} pruned (skill no longer shipped)"
  done < <(find "${farm}" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null)
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

    # Skip ENTIRE module if disabled — no symlinks created, and any link an
    # earlier run created is taken back out.
    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
      _skip "${mod_name}: disabled per config — skipping"
      _unlink_agents "${mod_dir}"
      continue
    fi

    _link_agents "${mod_dir}"
    _link_commands "${mod_dir}"
    _link_skills "${mod_dir}"
    _link_tools "${mod_dir}"
  done
}
