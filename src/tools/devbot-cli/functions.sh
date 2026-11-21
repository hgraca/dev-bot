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
    _link_is_owned_by "${resolved}" "${agent_dir}" || continue
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
          if _link_is_owned_by "${resolved}" "${agent_dir}"; then
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
# Each command file is symlinked individually into .agents/commands/, NAMED after
# its full frontmatter name (devbot:audit → commands/devbot:audit.md). Hosts read
# that name: opencode 2.x joins path segments with `/`, claudecode joins the dir
# with `:`. A host that reads the frontmatter instead lands on the same id, since
# link name == name. So `/devbot:audit` on every host; the retired devbot/ dir
# gave opencode `/devbot/audit`.
_link_commands() {
  local mod_dir="$1"
  local cmd_dir="${mod_dir}commands"
  local target_dir="${AGENTS_DIR}/commands"
  local f name link current resolved
  local wanted=""
  local cmd_dir_real
  cmd_dir_real="$(cd "${cmd_dir}" 2>/dev/null && pwd -P || true)"
  [[ -n "${cmd_dir_real}" ]] || cmd_dir_real="${cmd_dir}"

  if [[ -d "${cmd_dir}" ]]; then
    for f in "${cmd_dir}"/*.md; do
      [[ -f "${f}" ]] || continue
      name="$(sed -n 's/^name:[[:space:]]*//p' "${f}" | head -1 \
        | tr -d '\r"' | sed 's/[[:space:]]*$//')"
      # The link name is the frontmatter name verbatim, so the shape is the whole
      # guard: anything else escapes the farm or lands in the user's namespace.
      if [[ ! "${name}" =~ ^devbot:[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
        _warn "commands/${f##*/} is named '${name}', not devbot:<id> — not farmed"
        continue
      fi
      wanted+="${name}.md"$'\n'

      mkdir -p "${target_dir}"
      link="${target_dir}/${name}.md"
      if [[ -L "${link}" ]]; then
        current="$(readlink "${link}")"
        if [[ "${current}" == "${f}" ]]; then
          _skip "commands/${name} already linked"
        else
          # Only a link this harness created is ours to re-point. The farm is
          # shared, so a colliding command name from another module — or a
          # user's own link — must survive this module's pass.
          resolved="$(_link_target_path "${link}")"
          [[ -n "${resolved}" ]] || resolved="${current}"
          if _link_is_owned_by "${resolved}" "${cmd_dir}" "${cmd_dir_real}"; then
            rm -f "${link}"
            ln -sf "${f}" "${link}"
            _ok "commands/${name} relinked"
          else
            _warn "commands/${name}.md links outside this module — leaving it"
          fi
        fi
      elif [[ -e "${link}" ]]; then
        _warn "commands/${name} exists but is not a symlink"
      else
        ln -sf "${f}" "${link}"
        _ok "commands/${name} linked"
      fi
    done
  fi

  # A module that ships no commands — or dropped the directory entirely — still
  # has to reconcile: an empty wanted set prunes every link into it, including a
  # dangling one whose directory is gone. Returning early here left exactly that
  # case live.
  [[ -d "${target_dir}" ]] || return 0
  _prune_flat_links "${target_dir}" "${cmd_dir}" "${wanted}" "command no longer shipped" "commands/"
  _retire_legacy_command_farm "${cmd_dir}" "command now named devbot:<id>"
}

# ── Retire the pre-colon devbot/ command category ──────────────────────────────
# A module prunes only its own links, and the dir goes once it is empty, so a
# foreign link or a user's file keeps it alive — and a survivor is reported.
_retire_legacy_command_farm() {
  local src_dir="$1"
  local reason="${2:-command renamed}"

  local legacy_dir="${AGENTS_DIR}/commands/devbot"
  [[ -d "${legacy_dir}" ]] || return 0
  _prune_flat_links "${legacy_dir}" "${src_dir}" "" "${reason}" "commands/devbot/"
  _prune_install_owned_links "${legacy_dir}"
  rmdir "${legacy_dir}" 2>/dev/null || true
}

# One report per run, after every module has retired its links: naming the dir
# per module would repeat the same warning once for each of them.
_warn_unretired_legacy_farm() {
  local legacy_dir="${AGENTS_DIR}/commands/devbot"
  [[ -d "${legacy_dir}" ]] || return 0
  _warn "commands/devbot/ survives with: $(ls -A "${legacy_dir}" 2>/dev/null | tr '\n' ' ')"
}

# A legacy link into the install root is ours even when its module is gone. One
# recorded against an older root matches nothing, so the dir survives and
# `_warn_unretired_legacy_farm` names it — never deleting what we cannot place.
_prune_install_owned_links() {
  local legacy_dir="$1"
  local link resolved raw root_real

  [[ -n "${DEV_BOT_ROOT:-}" ]] || return 0
  root_real="$(cd "${DEV_BOT_ROOT}" 2>/dev/null && pwd -P || echo "${DEV_BOT_ROOT}")"
  while IFS= read -r -d '' link; do
    resolved="$(_link_target_path "${link}")"
    if [[ -z "${resolved}" ]]; then
      raw="$(readlink "${link}" 2>/dev/null || true)"
      [[ -n "${raw}" ]] || continue
      [[ "${raw}" == /* ]] || raw="$(dirname "${link}")/${raw}"
      resolved="${raw}"
    fi
    _link_is_owned_by "${resolved}" "${DEV_BOT_ROOT}" "${root_real}" || continue
    rm -f "${link}"
    _ok "commands/devbot/${link##*/} pruned (orphaned install link)"
  done < <(find "${legacy_dir}" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null)
}

# ── Decide whether a farm link belongs to a module ─────────────────────────────
# True when a symlink's recorded target points into <dir>. A `..` component is
# rejected outright: the harness only ever writes absolute links to real files,
# and a `..` in the recorded text can pass the prefix check while pointing
# elsewhere — which would let one module replace or prune a foreign link.
_link_is_owned_by() {
  local target="$1" dir="$2" dir_real="${3:-$2}"

  [[ -n "${target}" ]] || return 1
  [[ "${target}" == *"/../"* || "${target}" == *"/.." ]] && return 1
  # Equality counts: modules that keep SKILL.md directly in skills/ link at
  # <module>/skills itself, not below it.
  [[ "${target}" == "${dir}" || "${target}" == "${dir}"/* \
    || "${target}" == "${dir_real}" || "${target}" == "${dir_real}"/* ]] || return 1
  return 0
}

# ── Reconcile a flat farm against what a module ships ──────────────────────────
# Commands and tools both farm ONE LINK PER FILE at a flat name, so they reconcile
# the same way. `wanted` is the newline-separated set of link basenames the module
# wants now — suffix included, since a command is `<name>.md` and a tool is
# `<name>.mcp.sh`; an empty set prunes every link into <src_dir>.
_prune_flat_links() {
  local farm="$1"
  local src_dir="$2"
  local wanted="$3"
  local reason="${4:-no longer shipped}"
  local label="${5:-}"
  local src_dir_real
  src_dir_real="$(cd "${src_dir}" 2>/dev/null && pwd -P || true)"
  [[ -n "${src_dir_real}" ]] || src_dir_real="${src_dir}"

  local stale name resolved raw
  while IFS= read -r -d '' stale; do
    name="$(basename "${stale}")"
    if [[ -n "${wanted}" ]] && grep -Fxq -- "${name}" <<< "${wanted}"; then
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
    # _link_is_owned_by compares both forms — the recorded target may be logical
    # while _link_target_path resolves physically — and rejects `..` outright, so
    # a sibling directory sharing the prefix is out of scope.
    _link_is_owned_by "${resolved}" "${src_dir}" "${src_dir_real}" || continue
    rm -f "${stale}"
    _ok "${label}${name} pruned (${reason})"
    # Pre-filtered by recorded target: -lname matches the link's own value, so a
    # dangling link still matches. Without it every module paid one subshell per
    # farm entry to discover the entry was not its own.
  done < <(find "${farm}" -mindepth 1 -maxdepth 1 -type l \
    \( -lname "${src_dir}/*" -o -lname "${src_dir_real}/*" \) -print0 2>/dev/null)
}

# Take a disabled module's command links back out. _link_modules calls this where
# it calls _unlink_agents: leaving them live kept a disabled module's slash
# commands invocable.
_unlink_commands() {
  local mod_dir="$1"
  local reason="${2:-module disabled}"
  local target_dir="${AGENTS_DIR}/commands"

  [[ -d "${target_dir}" ]] || return 0
  _prune_flat_links "${target_dir}" "${mod_dir}commands" "" "${reason}" "commands/"
  _retire_legacy_command_farm "${mod_dir}commands" "${reason}"
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

# ── Decide whether a skill link belongs to a module ────────────────────────────
# A module has two possible skills dirs: the committed <module>/skills, and a
# machine-local generated store at storage/<module>/skills when it carries the
# `.devbot-generated` sentinel. A link into either is the module's.
_skills_owned_by() {
  local target="$1" mod_dir="$2" mod_name
  mod_name="$(basename "${mod_dir}")"
  local d real
  for d in "${mod_dir}skills" "${DEV_BOT_ROOT}/storage/${mod_name}/skills"; do
    real="$(cd "${d}" 2>/dev/null && pwd -P || true)"
    [[ -n "${real}" ]] || real="${d}"
    _link_is_owned_by "${target}" "${d}" "${real}" && return 0
  done
  return 1
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
    if [[ -L "${farm}" ]]; then
      local no_skills_target
      no_skills_target="$(_link_target_path "${farm}")"
      [[ -n "${no_skills_target}" ]] || no_skills_target="$(readlink "${farm}")"
      if _skills_owned_by "${no_skills_target}" "${mod_dir}"; then
        rm -f "${farm}"
        _ok "skills/devbot/${mod_name} pruned (module ships no skills)"
      else
        _warn "skills/devbot/${mod_name} links outside this module — leaving it"
      fi
    elif [[ -d "${farm}" && ! -L "${farm}" ]]; then
      # Current shape: drop only links that resolve into this module's skills.
      local stale
      while IFS= read -r -d '' stale; do
        local resolved
        resolved="$(_link_target_path "${stale}")"
        _skills_owned_by "${resolved}" "${mod_dir}" || continue
        rm -f "${stale}"
        _ok "skills/devbot/${mod_name}/$(basename "${stale}") pruned (module ships no skills)"
      done < <(find "${farm}" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null)
      rmdir "${farm}" 2>/dev/null || true
    fi
    return
  fi

  # The module-level symlink of the previous farm shape becomes a real directory
  # of per-skill links — but only when it is ours. A user's own link at the
  # module name is left in place, as every other path in this file now does.
  if [[ -L "${farm}" ]]; then
    local farm_target
    farm_target="$(_link_target_path "${farm}")"
    [[ -n "${farm_target}" ]] || farm_target="$(readlink "${farm}")"
    if _skills_owned_by "${farm_target}" "${mod_dir}"; then
      rm -f "${farm}"
    else
      _warn "skills/devbot/${mod_name} links outside this module — leaving it"
      return
    fi
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
        # Only a link this harness created is ours to re-point — a user's own
        # link at a skill name is left in place, as the prune below does.
        local resolved_relink
        resolved_relink="$(_link_target_path "${link}")"
        [[ -n "${resolved_relink}" ]] || resolved_relink="$(readlink "${link}")"
        if _skills_owned_by "${resolved_relink}" "${mod_dir}"; then
          rm -f "${link}"
          ln -sf "${target}" "${link}"
          _ok "skills/devbot/${mod_name}/${name} relinked"
        else
          _warn "skills/devbot/${mod_name}/${name} links outside this module — leaving it"
        fi
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
    # Only links into THIS module's skills dirs are ours to prune.
    resolved="$(_link_target_path "${stale}")"
    _skills_owned_by "${resolved}" "${mod_dir}" || continue
    rm -f "${stale}"
    _ok "skills/devbot/${mod_name}/${bare} pruned (skill no longer shipped)"
  done < <(find "${farm}" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null)
}

# ── Link MCP tools into .agents/ ────────────────────────────────────────────────
_link_tools() {
  local mod_dir="$1"
  local tool_dir="${mod_dir}tools"
  local target_dir="${AGENTS_DIR}/tools"
  local tool_dir_real
  tool_dir_real="$(cd "${tool_dir}" 2>/dev/null && pwd -P || true)"
  [[ -n "${tool_dir_real}" ]] || tool_dir_real="${tool_dir}"

  local wanted=""
  if [[ -d "${tool_dir}" ]]; then
    while IFS= read -r -d '' tool_file; do
      local tool_name
      tool_name="$(basename "${tool_file}")"

      # Only *.mcp.sh files are devbot-tools MCP tools. Skip helper scripts
      # (.ts hook targets, .sh CLIs/workers, .py implementations).
      if [[ "${tool_name}" != *.mcp.sh ]]; then
        continue
      fi
      wanted+="${tool_name}"$'\n'

      local target="${tool_file}"
      local link="${target_dir}/${tool_name}"

      if [[ -L "${link}" ]]; then
        local current
        current="$(readlink "${link}")"
        if [[ "${current}" == "${target}" ]]; then
          _skip "tools/${tool_name} already linked"
        else
          # Only a link this harness created is ours to re-point: the tools farm
          # is flat, so a colliding <name>.mcp.sh from another module must stay.
          local resolved
          resolved="$(_link_target_path "${link}")"
          [[ -n "${resolved}" ]] || resolved="${current}"
          if _link_is_owned_by "${resolved}" "${tool_dir}" "${tool_dir_real}"; then
            rm -f "${link}"
            ln -sf "${target}" "${link}"
            _ok "tools/${tool_name} relinked"
          else
            _warn "tools/${tool_name} links outside this module — leaving it"
          fi
        fi
      elif [[ -e "${link}" ]]; then
        _warn "tools/${tool_name} exists but is not a symlink"
      else
        mkdir -p "$(dirname "${link}")"
        ln -sf "${target}" "${link}"
        _ok "tools/${tool_name} linked"
      fi
    done < <(find "${tool_dir}" -maxdepth 3 -name '*.mcp.sh' -type f -print0 2>/dev/null)
  fi

  # A module that ships no tools — or dropped the directory — still reconciles.
  [[ -d "${target_dir}" ]] || return 0
  _prune_flat_links "${target_dir}" "${tool_dir}" "${wanted}" "tool no longer shipped" "tools/"
}

# Take a disabled module's tool links back out. Flat farm, so the shared pruner
# does it with an empty wanted set.
_unlink_tools() {
  local mod_dir="$1"
  local reason="${2:-module disabled}"
  local target_dir="${AGENTS_DIR}/tools"

  [[ -d "${target_dir}" ]] || return 0
  _prune_flat_links "${target_dir}" "${mod_dir}tools" "" "${reason}" "tools/"
}

# Take a disabled module's skills out of the farm. Unlike commands and tools the
# skills farm is one DIRECTORY per module, so this walks that directory — and
# still leaves any link that resolves somewhere else.
_unlink_skills() {
  local mod_dir="$1"
  local reason="${2:-module disabled}"
  local mod_name
  mod_name="$(basename "${mod_dir}")"
  local farm="${AGENTS_DIR}/skills/devbot/${mod_name}"

  [[ -e "${farm}" || -L "${farm}" ]] || return 0

  # The previous farm shape: one module-level link to the skills dir.
  if [[ -L "${farm}" ]]; then
    local farm_target
    farm_target="$(_link_target_path "${farm}")"
    if [[ -z "${farm_target}" ]]; then
      farm_target="$(readlink "${farm}" 2>/dev/null || true)"
      [[ "${farm_target}" == /* || -z "${farm_target}" ]] \
        || farm_target="$(dirname "${farm}")/${farm_target}"
    fi
    if _skills_owned_by "${farm_target}" "${mod_dir}"; then
      rm -f "${farm}"
      _ok "skills/devbot/${mod_name} unlinked (${reason})"
    else
      _warn "skills/devbot/${mod_name} links outside this module — leaving it"
    fi
    return 0
  fi

  [[ -d "${farm}" ]] || return 0
  local link resolved raw
  while IFS= read -r -d '' link; do
    resolved="$(_link_target_path "${link}")"
    if [[ -z "${resolved}" ]]; then
      raw="$(readlink "${link}" 2>/dev/null || true)"
      [[ -n "${raw}" ]] || continue
      [[ "${raw}" == /* ]] || raw="$(dirname "${link}")/${raw}"
      resolved="${raw}"
    fi
    _skills_owned_by "${resolved}" "${mod_dir}" || continue
    rm -f "${link}"
    _ok "skills/devbot/${mod_name}/$(basename "${link}") pruned (${reason})"
  done < <(find "${farm}" -mindepth 1 -maxdepth 1 -type l -print0 2>/dev/null)
  # Only when it is empty — a link that was not ours keeps the directory alive.
  rmdir "${farm}" 2>/dev/null || true
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

  # UNLINK the disabled modules first, then LINK the enabled ones. When two
  # modules ship the same farm name, link-then-unlink loses it: the enabled
  # module refuses a link that is not its own, and the disabled module's unlink
  # then removes it — leaving the name absent until the next run recreates it.
  # Taking the disabled module back out first frees the name for its owner.
  local -a enabled_dirs=() disabled_dirs=()
  local mod_dir mod_name
  for mod_dir in "${mod_dirs[@]}"; do
    mod_name="$(basename "${mod_dir}")"
    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
      disabled_dirs+=("${mod_dir}")
    else
      enabled_dirs+=("${mod_dir}")
    fi
  done

  for mod_dir in ${disabled_dirs[@]+"${disabled_dirs[@]}"}; do
    mod_name="$(basename "${mod_dir}")"
    _skip "${mod_name}: disabled per config — skipping"
    _unlink_agents "${mod_dir}"
    _unlink_commands "${mod_dir}"
    _unlink_skills "${mod_dir}"
    _unlink_tools "${mod_dir}"
  done

  for mod_dir in ${enabled_dirs[@]+"${enabled_dirs[@]}"}; do
    _link_agents "${mod_dir}"
    _link_commands "${mod_dir}"
    _link_skills "${mod_dir}"
    _link_tools "${mod_dir}"
  done

  _warn_unretired_legacy_farm
}
