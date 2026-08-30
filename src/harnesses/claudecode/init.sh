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
  _fatal "directory '${1:-.}' does not exist or cannot be resolved."
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
  done < <(find "${CLAUDE_TPL}" -mindepth 1 -print0 2>/dev/null)

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

# ── Link the harness's own hook scripts into .claude/plugins/ ───────────────
# The generic dispatcher + auto-recover scripts live under the dev-bot repo,
# but Claude Code runs hook commands from the project cwd. Symlinking them into
# .claude/plugins/ (like the opencode harness does for its .ts hooks) makes the
# relative paths in hooks.json resolvable from any project.
_link_harness_hooks() {
  local hook_dir="${MODULE_DIR}/hooks"
  [[ -d "${hook_dir}" ]] || return

  while IFS= read -r -d '' hook_file; do
    local hook_name
    hook_name="$(basename "${hook_file}")"

    local link="${CLAUDE_DIR}/plugins/${hook_name}"
    if [[ -L "${link}" ]]; then
      _skip "plugins/${hook_name} already linked"
    elif [[ -e "${link}" ]]; then
      _warn "plugins/${hook_name} exists but is not a symlink"
    else
      mkdir -p "$(dirname "${link}")"
      ln -sf "${hook_file}" "${link}"
      _ok "plugins/${hook_name} linked"
    fi
  done < <(find "${hook_dir}" -maxdepth 1 -type f \( -name '*.py' -o -name '*.sh' \) -print0 2>/dev/null)
}

# ── Wire the generic harness hooks (hooks.json) into settings.local.json ────
_wire_harness_hooks() {
  local config="${CLAUDE_DIR}/settings.local.json"
  [[ -f "${config}" ]] || return 0

  local harness_hooks="${MODULE_DIR}/hooks.json"
  [[ -f "${harness_hooks}" ]] || return 0

  python3 -c "
import json
with open('${config}') as f:
    settings = json.load(f)
with open('${harness_hooks}') as f:
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
  _ok "harness generic hooks merged into .claude/settings.local.json"
}

_link_plugins_modules() {
  # Resolve disabled modules
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${PROJECT_DIR}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

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
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

  for mod_dir in "${DEV_BOT_ROOT}/src/agentic/"*/; do
    local mod_name
    mod_name="$(basename "${mod_dir}")"

    # Skip disabled modules
    if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
      continue
    fi

    local mcp_file="${mod_dir}/mcp.claudecode.json"
    [[ -f "${mcp_file}" ]] || continue

    # Docker-only MCPs can't run without a docker daemon (e.g. inside a
    # container) — skip the module's MCPs so the client never starts them.
    # Hybrid defs (docker with an npx fallback, like playwright) are kept;
    # their wrapper picks the path.
    if grep -q 'docker run' "${mcp_file}" \
      && ! grep -q 'npx -y @playwright/mcp' "${mcp_file}" \
      && ! docker info >/dev/null 2>&1; then
      _skip "${mod_name}: MCP needs a docker daemon — skipping registration"
      continue
    fi

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

  # Dynamic manifests written by module inits (e.g. jetbrains detects the
  # runtime port). Same mcpServers shape as mcp.claudecode.json.
  for dyn_file in "${PROJECT_DIR}/.claude/"*.mcp.json; do
    [[ -f "${dyn_file}" ]] || continue
    python3 -c "
import json
with open('${tmp_servers}') as f:
    current = json.load(f)
with open('${dyn_file}') as f:
    new_mcp = json.load(f)
for name, entry in new_mcp.get('mcpServers', {}).items():
    if entry.get('enabled', True):
        current[name] = entry
with open('${tmp_servers}', 'w') as f:
    json.dump(current, f)
" 2>/dev/null
    merged=$((merged + 1))
  done

  # Validate transport types — Claude Code validates .mcp.json against a strict
  # schema: a single entry with an unrecognized `type` (e.g. "url" or "remote")
  # makes it reject the ENTIRE file, silently dropping every server. Drop invalid
  # entries here and fail loudly so one bad manifest can't silence the rest.
  local invalid_servers
  invalid_servers=$(python3 -c "
import json
with open('${tmp_servers}') as f:
    servers = json.load(f)
valid = {'stdio', 'sse', 'http', 'ws', 'streamable-http'}
dropped = []
for name, entry in list(servers.items()):
    t = entry.get('type')
    if t is not None and t not in valid:
        dropped.append(name + '\t' + str(t))
        del servers[name]
with open('${tmp_servers}', 'w') as f:
    json.dump(servers, f)
for line in dropped:
    print(line)
" 2>/dev/null)

  if [[ -n "${invalid_servers}" ]]; then
    while IFS=$'\t' read -r bad_name bad_type; do
      [[ -n "${bad_name}" ]] || continue
      _error "MCP server '${bad_name}' has unsupported transport type '${bad_type}'; dropped from .mcp.json. Valid types: stdio, sse, http, ws, streamable-http."
    done <<< "${invalid_servers}"
  fi

  # Write .mcp.json
  if [[ ${merged} -gt 0 ]]; then
    local server_count
    server_count=$(python3 -c "
import json
with open('${tmp_servers}') as f:
    servers = json.load(f)
with open('${config}', 'w') as f:
    json.dump({'mcpServers': servers}, f, indent=2)
    f.write('\n')
print(len(servers))
" 2>/dev/null)
    _ok ".mcp.json written with ${server_count} MCP server(s)"
  fi

  rm -f "${tmp_servers}"
}

# ── Default agent ─────────────────────────────────────────────────────────────
# Claude Code's "agent" key starts every session as the named agent. The agent
# is no longer forced at launch (start.sh). If .claude/settings.json does not
# exist yet, create it with DevBot as the default agent — a missing file is no
# choice, so we never ask for it. Only when the file already exists and chose a
# different agent do we ask — never change an existing choice silently.
# Non-interactive runs (SKIP_CONFIRM=1 or no TTY) leave an existing choice
# untouched. Merge — never clobber — so settings written by other tools (e.g.
# graphify hooks) survive.
_write_default_agent() {
  local config="$1"
  local agent="$2"

  python3 - "${config}" "${agent}" <<'PY'
import json, os, sys
config, agent = sys.argv[1], sys.argv[2]
settings = {}
if os.path.exists(config):
    with open(config) as f:
        settings = json.load(f)
settings["agent"] = agent
with open(config, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PY
}

_ensure_default_agent() {
  local config="${CLAUDE_DIR}/settings.json"
  local agent="DevBot"

  local current=""
  if [[ -f "${config}" ]]; then
    current="$(python3 -c "
import json
try:
    with open('${config}') as f:
        settings = json.load(f)
    print(settings.get('agent', ''))
except Exception:
    print('')
" 2>/dev/null || true)"
  fi

  if [[ -n "${current}" && "${current}" == "${agent}" ]]; then
    _skip ".claude/settings.json: default agent already ${agent}"
    return 0
  fi

  # No agent key set (config missing OR exists WITHOUT an "agent" key — e.g. a
  # project's own settings.json wiring unrelated hooks) — there is no existing
  # choice to protect: write DevBot unconditionally, also in non-interactive
  # runs. _write_default_agent merges, so any existing settings (hooks, etc.)
  # are preserved. An absent key is NOT a protected prior choice.
  if [[ -z "${current}" ]]; then
    _write_default_agent "${config}" "${agent}"
    _ok ".claude/settings.json: default agent set to ${agent}"
    return 0
  fi

  # Existing config with a DIFFERENT agent — ask before changing it.
  if [[ "${SKIP_CONFIRM:-0}" == "1" || ! -t 0 ]]; then
    _skip "default agent is '${current}' — leaving as-is (non-interactive)"
    return 0
  fi

  echo -n "  Default agent is '${current:-unset}'. Set DevBot as the default agent? [y/N] "
  local answer
  read -r answer
  if [[ ! "${answer}" =~ ^[yY](es)?$ ]]; then
    _info "Leaving default agent as '${current:-unset}'."
    return 0
  fi

  _write_default_agent "${config}" "${agent}"
  _ok ".claude/settings.json: default agent set to ${agent}"
}

# ── Link skills FLAT into .claude/skills/ (claudecode-specific) ──────────────
# Claude Code's skill discovery expects a FLAT `.claude/skills/<name>/SKILL.md`
# (one level deep), unlike opencode which reads the nested `.agents/skills`
# tree directly. The generic delegation's `.claude/skills -> .agents/skills`
# nested symlink (devbot/<module>/[<category>/]SKILL.md) makes every dev-bot
# skill UNREACHABLE via the Skill tool — only the 10 that double as slash
# commands resolve. Flatten per-skill here, naming each dir after the skill's
# frontmatter name (devbot:git-conventional-commits etc.), so the Skill tool
# can invoke them.
_link_claude_skills_flat() {
  local project_dir="$1"
  local claude_skills="${project_dir}/.claude/skills"

  # ── Preserve user custom skills before the rebuild ────────────────────────
  # The flat rebuild below drops .claude/skills entirely. Any REAL skill dir
  # the user created there (SKILL.md is a real file, not a symlink) is migrated
  # into devbot_dir/skills first so it is never destroyed. dev-bot's own flat
  # links (symlinked SKILL.md) and already-migrated skills are skipped.
  local devbot_dir agents_skills
  devbot_dir="$(_devbot_get_project_dir "${project_dir}")"
  agents_skills="${project_dir}/${devbot_dir}/skills"

  if [[ -d "${claude_skills}" && ! -L "${claude_skills}" ]]; then
    mkdir -p "${agents_skills}"
    local item
    while IFS= read -r -d '' item; do
      local name
      name="$(basename "${item}")"
      [[ "${name}" == ".gitkeep" ]] && continue
      [[ -e "${item}" ]] || continue

      # dev-bot flat link or already-migrated skill (SKILL.md is a symlink
      # into DEV_BOT_ROOT or devbot_dir/skills) — not user content;
      # re-flattened below, so skip. A symlink pointing anywhere else is a
      # user artifact: warn and migrate it (review F3b).
      if [[ -d "${item}" && -L "${item}/SKILL.md" ]]; then
        local md_target md_abs
        md_target="$(readlink "${item}/SKILL.md")"
        md_abs="${md_target}"
        if [[ "${md_abs}" != /* ]]; then
          md_abs="$(cd "$(dirname "${item}")" 2>/dev/null \
            && cd "$(dirname "${md_target}")" 2>/dev/null \
            && pwd 2>/dev/null || true)/$(basename "${md_target}")"
        fi
        if [[ "${md_abs}" == "${DEV_BOT_ROOT}/"* || "${md_abs}" == "${agents_skills}/"* ]]; then
          continue
        fi
        _warn "skills/${name}/SKILL.md is a symlink pointing outside dev-bot — migrating content"
      fi

      # Collision policy (shared with the delegation migrator): an existing
      # dest keeps its name (devbot wins); the user's artifact is preserved as
      # <name>.bkp. If the .bkp slot is taken, re-suffix (.bkp.bkp) rather
      # than nesting or overwriting (review F4).
      local dest="${agents_skills}/${name}"
      if [[ -e "${dest}" || -L "${dest}" ]]; then
        local candidate="${name}"
        while [[ -e "${agents_skills}/${candidate}" || -L "${agents_skills}/${candidate}" ]]; do
          candidate="${candidate}.bkp"
        done
        _warn "skills/${name} exists in ${devbot_dir}/ — storing user's as ${candidate} (same skill name may register twice)"
        dest="${agents_skills}/${candidate}"
      fi

      mkdir -p "$(dirname "${dest}")"
      # Dereference symlinked skill dirs so the copy is a real dir that the
      # step-4 find can descend into (review F3a).
      if [[ -L "${item}" && -d "${item}" ]]; then
        cp -rL "${item}" "${dest}"
      else
        cp -r "${item}" "${dest}"
      fi
      # Marker: this dir was migrated by dev-bot. Step 4 flattens ONLY marked
      # dirs, so tool-placed real dirs in devbot_dir/skills (graphify-style)
      # are never misclassified as user content (review F1).
      touch "${dest}/.devbot-migrated"
      _ok "migrated custom skill ${name} to ${devbot_dir}/skills/"
    done < <(find "${claude_skills}" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
  fi

  # Drop any previous delegation symlink/dir (a reset leaves it absent, but be
  # safe for projects that were not fully reset).
  if [[ -L "${claude_skills}" ]]; then
    rm -f "${claude_skills}"
  elif [[ -e "${claude_skills}" ]]; then
    rm -rf "${claude_skills}"
  fi
  mkdir -p "${claude_skills}"

  # Link one SKILL.md flat as .claude/skills/<frontmatter-name>/SKILL.md.
  _link_skill_file() {
    local f="$1" name link
    name="$(sed -n 's/^name:[[:space:]]*//p' "${f}" | head -1 | tr -d '"')"
    [[ -n "${name}" ]] || return 0
    mkdir -p "${claude_skills}/${name}"
    link="${claude_skills}/${name}/SKILL.md"
    if [[ -L "${link}" ]]; then
      if [[ "$(readlink "${link}")" != "${f}" ]]; then
        rm -f "${link}"
        ln -s "${f}" "${link}"
      fi
    else
      ln -s "${f}" "${link}"
    fi
  }

  # Link a user skill (from devbot_dir/skills) flat, preferring its frontmatter
  # name and falling back to the dir name. On collision with an existing flat
  # skill (a dev-bot one), the user's is stored as <name>.bkp; if that slot is
  # taken too, re-suffix (.bkp.bkp) rather than aborting (review F2).
  _link_user_skill_file() {
    local f="$1" name link
    name="$(sed -n 's/^name:[[:space:]]*//p' "${f}" | head -1 | tr -d '"')"
    [[ -n "${name}" ]] || name="$(basename "$(dirname "${f}")")"
    link="${claude_skills}/${name}/SKILL.md"
    if [[ -e "${link}" || -L "${link}" ]]; then
      local candidate="${name}"
      while [[ -e "${claude_skills}/${candidate}/SKILL.md" || -L "${claude_skills}/${candidate}/SKILL.md" ]]; do
        candidate="${candidate}.bkp"
      done
      _warn "skills/${name} already flattened — storing user's as ${candidate} (same skill name may register twice)"
      link="${claude_skills}/${candidate}/SKILL.md"
    fi
    mkdir -p "$(dirname "${link}")"
    ln -s "${f}" "${link}"
  }

  local f
  # dev-bot module skills (agentic + tools)
  while IFS= read -r -d '' f; do
    _link_skill_file "${f}"
  done < <(find "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/tools" -name SKILL.md -print0 2>/dev/null)

  # External-module skills (addyosmani, mattpocock-grilling, ...): their skill
  # dirs are symlinks into the vendored tree (follow with -L). DevBot's persona
  # references these by their bare upstream names (test-driven-development,
  # grilling, debugging-and-error-recovery, ...) — without this they are
  # unreachable under claudecode.
  if [[ -d "${DEV_BOT_ROOT}/storage/external-agentic-modules" ]]; then
    while IFS= read -r -d '' f; do
      _link_skill_file "${f}"
    done < <(find -L "${DEV_BOT_ROOT}/storage/external-agentic-modules" -name SKILL.md -print0 2>/dev/null)
  fi

  # ── Flatten user custom skills (migrated above) back into .claude/skills ──
  # Only dirs carrying the .devbot-migrated marker (i.e. actually migrated by
  # dev-bot) are flattened. Real dirs placed by tools (graphify-style) or the
  # dev-bot/external namespaced dirs carry no marker and are skipped, so no
  # spurious .bkp duplicates of dev-bot's own skills are created (review F1).
  if [[ -d "${agents_skills}" ]]; then
    local marker
    while IFS= read -r -d '' marker; do
      local skill_dir
      skill_dir="$(dirname "${marker}")"
      _link_user_skill_file "${skill_dir}/SKILL.md"
    done < <(find "${agents_skills}" -mindepth 2 -maxdepth 2 -name .devbot-migrated -print0 2>/dev/null)
  fi

  _ok "claudecode skills flattened into .claude/skills/ (incl. external modules)"
}

# ── main ─────────────────────────────────────────────────────────────────────
_copy_claude_dir
_write_claude_config
_harness_delegate_to_agents "${CLAUDE_DIR}" "${PROJECT_DIR}" "agents commands tools"
_link_claude_skills_flat "${PROJECT_DIR}"
_link_plugins_modules
_wire_plugin_hooks
_link_harness_hooks
_wire_harness_hooks
_wire_mcp
_remove_gitkeep_files
_ensure_default_agent
