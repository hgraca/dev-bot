#!/usr/bin/env bash
# =============================================================================
# src/agentic/graphify/init.sh
# Set up Graphify in a project: create .graphifyignore, install the graphify
# bootstrap memory, build the initial knowledge graph, symlink MCP wrappers,
# and add graphify patterns to .gitignore and .git/info/exclude.
# Hooks (OpenCode plugins + Claude Code hooks) are auto-discovered — no
# manual git-hook setup needed.
#
# Idempotent — safe to re-run.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd)"

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_fmt_duration() {
  local secs=$1
  if (( secs >= 60 )); then
    printf '%dm %ds' $(( secs / 60 )) $(( secs % 60 ))
  else
    printf '%ds' "${secs}"
  fi
}

# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Force-correct DEV_BOT_ROOT — _shared/functions.sh computes it one level too deep
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"

_header_3 "Graphify Init"

if ! command -v graphify >/dev/null 2>&1; then
  _warn "graphify not found — run install.sh first"
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_DIR}")"

# ── Check if harnesses are disabled ──────────────────────────────────────────
_IS_CLAUDE_DISABLED="false"
_IS_OPENCODE_DISABLED="false"
_disabled_modules_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"
if echo "${_disabled_modules_raw}" | jq -e 'index("claudecode") != null' >/dev/null 2>&1; then
  _IS_CLAUDE_DISABLED="true"
fi
if echo "${_disabled_modules_raw}" | jq -e 'index("opencode") != null' >/dev/null 2>&1; then
  _IS_OPENCODE_DISABLED="true"
fi

# ── Symlink MCP wrapper ──────────────────────────────────────────────────────
if [[ "${_IS_OPENCODE_DISABLED}" != "true" ]]; then
  mkdir -p "${PROJECT_DIR}/.opencode"
  ln -sf "${MODULE_DIR}/tools/start-graphify-mcp.sh" "${PROJECT_DIR}/.opencode/graphify-serve.sh"
  _log "Symlinked .opencode/graphify-serve.sh"
else
  _skip "OpenCode disabled — skipping .opencode/ MCP wrapper symlink"
fi

if [[ "${_IS_CLAUDE_DISABLED}" != "true" ]]; then
  mkdir -p "${PROJECT_DIR}/.claude"
  ln -sf "${MODULE_DIR}/tools/start-graphify-mcp.sh" "${PROJECT_DIR}/.claude/graphify-serve.sh"
  _log "Symlinked .claude/graphify-serve.sh"
else
  _skip "Claude Code disabled — skipping .claude/ MCP wrapper symlink"
fi

# ── Install tools ────────────────────────────────────────────────────────────
cd "${PROJECT_DIR}"

if command -v graphify >/dev/null 2>&1; then
  if [[ "${_IS_OPENCODE_DISABLED}" != "true" ]]; then
    _step "Installing graphify OpenCode tools..."
    if graphify install --platform opencode --project 2>&1; then
      _log "graphify OpenCode tools installed"
      # The module's SKILL.md is already delegated to .agents/skills/devbot/graphify
      # (opencode auto-discovers .agents/skills); the CLI's own copy under
      # .opencode/skills/graphify is a duplicate that opencode logs a WARN for.
      rm -rf "${PROJECT_DIR}/.opencode/skills/graphify" 2>/dev/null || true
    else
      _warn "graphify install failed — continuing without OpenCode tools"
    fi
  else
    _skip "OpenCode disabled — skipping graphify OpenCode tools"
  fi

  if [[ "${_IS_CLAUDE_DISABLED}" != "true" ]]; then
    _step "Installing graphify Claude Code tools..."
    if graphify install --platform claude --project 2>&1; then
      _log "graphify Claude Code tools installed"
      # The CLI installs its own skill copy under .claude/skills/graphify with
      # an UNNAMESPACED frontmatter name ("name: graphify") — the same skill
      # dev-bot ships namespaced as devbot:graphify (audit-31 §3). The
      # claudecode harness flatten flattens dev-bot's copy to
      # .claude/skills/devbot:graphify; leaving the CLI's stale unnamespaced
      # copy behind makes BOTH register, and every reinit re-migrates the old
      # one as a "user skill" (graphify.bkp churn). Mirror the opencode branch:
      # remove the CLI's project-scope skill copy — dev-bot's own namespaced
      # skill is the canonical one.
      rm -rf "${PROJECT_DIR}/.claude/skills/graphify" 2>/dev/null || true
    else
      _warn "graphify install (claude) failed — continuing without Claude Code tools"
    fi
  else
    _skip "Claude Code disabled — skipping graphify Claude Code tools"
  fi
fi

# ── Remove graphify plugin (auto-discovered, avoids double-load) ────────────
if [[ "${_IS_OPENCODE_DISABLED}" != "true" ]]; then
  PLUGIN_FILE="${PROJECT_DIR}/.opencode/plugins/graphify.js"
  if [[ -f "${PLUGIN_FILE}" ]]; then
    rm -f "${PLUGIN_FILE}"
    _log "Removed graphify.js plugin (auto-discovered by opencode, explicit file not needed)"
  fi

  OPCODE_CONFIG="${PROJECT_DIR}/.opencode/opencode.json"
  if [[ -f "${OPCODE_CONFIG}" ]]; then
    if command -v jq >/dev/null 2>&1; then
      if jq --arg plugin ".opencode/plugins/graphify.js" \
        'if .plugin then .plugin |= map(select(. != $plugin)) else . end' \
        "${OPCODE_CONFIG}" > "${OPCODE_CONFIG}.tmp" 2>/dev/null; then
        if cmp -s "${OPCODE_CONFIG}" "${OPCODE_CONFIG}.tmp"; then
          # Already clean (no graphify plugin entry) — skip the mv so reinit
          # does not churn the file's mtime on byte-identical content
          # (audit-37 §4 NOTE: .opencode/opencode.json stub rewritten every
          # reinit with identical bytes).
          rm -f "${OPCODE_CONFIG}.tmp"
        else
          mv "${OPCODE_CONFIG}.tmp" "${OPCODE_CONFIG}"
          _log "Removed graphify plugin from .opencode/opencode.json, to prevent double loading (its automatically discovered and registered)"
        fi
      else
        rm -f "${OPCODE_CONFIG}.tmp"
        _warn "Failed to process .opencode/opencode.json — skipping cleanup"
      fi
    else
      _warn "jq not found — skipping legacy plugin cleanup in .opencode/opencode.json"
    fi
  fi
fi

# ── Install graphify bootstrap memory from module template ────────────────────
AGENTS_MD="${PROJECT_DIR}/AGENTS.md"
GRAPHIFY_BOOTSTRAP_TEMPLATE="${MODULE_DIR}/graphify.md"
GRAPHIFY_BOOTSTRAP="${PROJECT_DIR}/$(_devbot_get_project_dir "${PROJECT_DIR}")/memory/active/graphify.md"

mkdir -p "$(dirname "${GRAPHIFY_BOOTSTRAP}")"

if [[ -f "${GRAPHIFY_BOOTSTRAP_TEMPLATE}" ]]; then
  cp "${GRAPHIFY_BOOTSTRAP_TEMPLATE}" "${GRAPHIFY_BOOTSTRAP}"
  _log "Installed graphify bootstrap memory → $(_devbot_get_project_dir "${PROJECT_DIR}")/memory/active/graphify.md"
else
  _warn "graphify.md template not found — skipping bootstrap memory"
fi

# Remove the graphify section from AGENTS.md if present (graphify install writes
# it, but the always-on context now lives in the memory vault). Also drop
# trailing blank lines: graphify install appends the section (with a blank
# separator) at EOF, and a plain section-strip leaves that separator behind —
# making reinit not byte-idempotent (audit-32 NOTE: AGENTS.md drifted between
# consecutive reinits).
if [[ -f "${AGENTS_MD}" ]] && grep -q '^## graphify[[:space:]]*$' "${AGENTS_MD}"; then
  awk '
    /^## graphify[[:space:]]*$/   { skip = 1; next }
    skip && /^## /                { skip = 0 }
    !skip
  ' "${AGENTS_MD}" > "${AGENTS_MD}.tmp" && mv "${AGENTS_MD}.tmp" "${AGENTS_MD}"
  # Strip trailing blank lines (the separator left where the section was).
  awk 'NF { seen = NR } { lines[NR] = $0 } END { for (i = 1; i <= seen; i++) print lines[i] }' \
    "${AGENTS_MD}" > "${AGENTS_MD}.tmp" && mv "${AGENTS_MD}.tmp" "${AGENTS_MD}"
  _log "Removed graphify section from AGENTS.md"
fi

# ── .graphifyignore from template ────────────────────────────────────────────
cd "${PROJECT_DIR}"

if [[ ! -f ".graphifyignore" ]]; then
  if [[ -f "${MODULE_DIR}/graphifyignore.tpl" ]]; then
    cp "${MODULE_DIR}/graphifyignore.tpl" ".graphifyignore"
    _log "Created .graphifyignore from template"
  else
    _warn "graphifyignore.tpl not found — skipping .graphifyignore"
  fi
fi

# ── Determine source scope ────────────────────────────────────────────────────
if [[ -d "src" ]]; then
  _GRAPHIFY_SRC="src"
  _log "Restricting graphify index to src/"
elif [[ -d "app" ]]; then
  _GRAPHIFY_SRC="app"
  _log "Restricting graphify index to app/"
else
  _GRAPHIFY_SRC="."
  _log "No src/ or app/ found — indexing project root"
fi

# ── Build initial knowledge graph ────────────────────────────────────────────
cd "${PROJECT_DIR}"

if [[ -f "graphify-out/graph.json" ]]; then
  _skip "Graph already built"
else
  DATE_STR=$(date '+%d %b %Y, %H:%M')
  _info "${DATE_STR} — Starting background knowledge graph build (indexing ${_GRAPHIFY_SRC}/)..."
  mkdir -p "graphify-out"

  # Write a dummy empty graph so the graphify MCP server can start immediately
  # instead of blocking for the ~1min build (opencode times out first). The
  # server hot-reloads graph.json when `graphify update` overwrites it.
  cat > "graphify-out/graph.json" <<'JSON'
{"directed": true, "multigraph": false, "graph": {}, "nodes": [], "links": []}
JSON

  nohup graphify update . > "graphify-out/init.log" 2>&1 &
  _ok "Graph build started in background — output: graphify-out/init.log"
fi

# ── .git/info/exclude section (local-only patterns) ──────────────────────────
_upsert_gitignore_section "${PROJECT_DIR}/.git/info/exclude" \
  "# >>> DEVBOT - graphify" \
  "# <<< DEVBOT - graphify" \
  ".graphifyignore" \
  "graphify-out/"
_log ".git/info/exclude updated with graphify patterns"

# ── .gitignore section (shared, required by codebase-index watcher) ──────────
# graphify-out/ MUST also be written to .gitignore, not only .git/info/exclude:
# the codebase-index file watcher (chokidar) reads .gitignore to decide which
# paths to skip watching, but never reads .git/info/exclude. Without this entry
# it watches every AST cache file under graphify-out/cache/ast/ (~80K files),
# exhausting inotify watches (ENOSPC: no space left on device).
_upsert_gitignore_section "${PROJECT_DIR}/.gitignore" \
  "# >>> DEVBOT - graphify" \
  "# <<< DEVBOT - graphify" \
  "# graphify-out/ must be in .gitignore (not only .git/info/exclude): the" \
  "# codebase-index file watcher (chokidar) reads .gitignore to skip paths," \
  "# but never reads .git/info/exclude. Without this it watches all ~80K AST" \
  "# cache files under graphify-out/cache/ast/ and exhausts inotify watches" \
  "# (ENOSPC: no space left on device)." \
  "graphify-out/"
_log ".gitignore updated with graphify patterns"

_log "Graphify init complete for ${PROJECT_NAME}"
