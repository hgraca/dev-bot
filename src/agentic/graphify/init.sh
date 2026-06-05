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

if ! command -v graphify &>/dev/null; then
  _warn "graphify not found — run install.sh first"
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_DIR}")"

# ── Check if claudecode is disabled ──────────────────────────────────────────
_IS_CLAUDE_DISABLED="false"
_disabled_modules_raw="$(_devbot_get_disabled_modules "${PROJECT_DIR}" 2>/dev/null || echo '[]')"
if echo "${_disabled_modules_raw}" | python3 -c "import json,sys; tools=json.loads(sys.stdin.read()); sys.exit(0 if 'claudecode' in tools else 1)" 2>/dev/null; then
  _IS_CLAUDE_DISABLED="true"
fi

# ── Symlink MCP wrapper ──────────────────────────────────────────────────────
if [[ -d "${PROJECT_DIR}/.opencode" ]]; then
  ln -sf "${MODULE_DIR}/tools/start-graphify-mcp.sh" "${PROJECT_DIR}/.opencode/graphify-serve.sh"
  _log "Symlinked .opencode/graphify-serve.sh"
else
  _warn ".opencode/ directory not found — skipping MCP wrapper symlink"
fi

if [[ "${_IS_CLAUDE_DISABLED}" != "true" && -d "${PROJECT_DIR}/.claude" ]]; then
  ln -sf "${MODULE_DIR}/tools/start-graphify-mcp.sh" "${PROJECT_DIR}/.claude/graphify-serve.sh"
  _log "Symlinked .claude/graphify-serve.sh"
elif [[ "${_IS_CLAUDE_DISABLED}" == "true" ]]; then
  _skip "Claude Code disabled — skipping .claude/ MCP wrapper symlink"
fi

# ── Install tools ────────────────────────────────────────────────────────────
cd "${PROJECT_DIR}"

if command -v graphify &>/dev/null; then
  _step "Installing graphify OpenCode tools..."
  if graphify install --platform opencode --project 2>&1; then
    _log "graphify OpenCode tools installed"
  else
    _warn "graphify install failed — continuing without OpenCode tools"
  fi

  if [[ "${_IS_CLAUDE_DISABLED}" != "true" ]]; then
    _step "Installing graphify Claude Code tools..."
    if graphify install --platform claude --project 2>&1; then
      _log "graphify Claude Code tools installed"
    else
      _warn "graphify install (claude) failed — continuing without Claude Code tools"
    fi
  else
    _skip "Claude Code disabled — skipping graphify Claude Code tools"
  fi
fi

# ── Remove graphify plugin (auto-discovered, avoids double-load) ────────────
PLUGIN_FILE="${PROJECT_DIR}/.opencode/plugins/graphify.js"
if [[ -f "${PLUGIN_FILE}" ]]; then
  rm -f "${PLUGIN_FILE}"
  _log "Removed graphify.js plugin (auto-discovered by opencode, explicit file not needed)"
fi

OPCODE_CONFIG="${PROJECT_DIR}/.opencode/opencode.json"
if [[ -f "${OPCODE_CONFIG}" ]]; then
  if command -v jq &>/dev/null; then
    if jq --arg plugin ".opencode/plugins/graphify.js" \
      'if .plugin then .plugin |= map(select(. != $plugin)) else . end' \
      "${OPCODE_CONFIG}" > "${OPCODE_CONFIG}.tmp" 2>/dev/null; then
      mv "${OPCODE_CONFIG}.tmp" "${OPCODE_CONFIG}"
      _log "Removed graphify plugin from .opencode/opencode.json, to prevent double loading (its automatically discovered and registered)"
    else
      rm -f "${OPCODE_CONFIG}.tmp"
      _warn "Failed to process .opencode/opencode.json — skipping cleanup"
    fi
  else
    _warn "jq not found — skipping legacy plugin cleanup in .opencode/opencode.json"
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
# it, but the always-on context now lives in the memory vault).
if [[ -f "${AGENTS_MD}" ]] && grep -q '^## graphify[[:space:]]*$' "${AGENTS_MD}"; then
  awk '
    /^## graphify[[:space:]]*$/   { skip = 1; next }
    skip && /^## /                { skip = 0 }
    !skip
  ' "${AGENTS_MD}" > "${AGENTS_MD}.tmp" && mv "${AGENTS_MD}.tmp" "${AGENTS_MD}"
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
  DATE_STR=$(date '+%-d %b %Y, %H:%M')
  _info "${DATE_STR} — Starting background knowledge graph build (indexing ${_GRAPHIFY_SRC}/)..."
  mkdir -p "graphify-out"
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
