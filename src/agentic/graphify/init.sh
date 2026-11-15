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
# shellcheck disable=SC2034  # consumed by the sourced _shared functions
DEV_BOT_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"

_header_3 "Graphify Init"

# ── Module memory ─────────────────────────────────────────────────────────────
# Written before the CLI gate below: reinit clears active/modules/, so exiting
# here on a missing binary would silently drop the module's always-on context.
_devbot_remove_legacy_module_memory "${PROJECT_DIR}" "graphify.md"
if _devbot_write_module_memory "${PROJECT_DIR}" "graphify.md" "${MODULE_DIR}/graphify.md"; then
  _log "Installed graphify bootstrap memory → $(_devbot_get_project_dir "${PROJECT_DIR}")/memory/active/modules/graphify.md"
else
  _warn "graphify.md template not found — skipping bootstrap memory"
fi

if ! command -v graphify >/dev/null 2>&1; then
  _warn "graphify not found — run install.sh first"
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_DIR}")"

# ── Version-matched skill ─────────────────────────────────────────────────────
# Ensure the skill matches the installed graphify version before wiring. This
# covers a graphify upgrade done OUTSIDE the dev-bot lifecycle (a bare
# `graphify install` / `uv tool upgrade`), which install.sh/update.sh never see.
# On success the skills-farm entry is pointed at the generated skill — the
# linking pass ran earlier, so on a first-run reinit the dir may appear only
# now; on failure the relink restores dev-bot's bundled skill.
_graphify_ensure_skill || true
_graphify_log_skill_result
_graphify_relink_skill "${PROJECT_DIR}"

# ── Install tools ────────────────────────────────────────────────────────────
cd "${PROJECT_DIR}"

# The client-side installer is the module's one harness-shaped dependency, so
# it runs for the selected client only — asked for by role, never by name.
_harness_dir="$(_devbot_harness_dir "${PROJECT_DIR}")"
_harness_platform="$(_devbot_harness_platform "${PROJECT_DIR}")"

_step "Installing graphify ${_harness_platform} tools..."
if graphify install --platform "${_harness_platform}" --project 2>&1; then
  _log "graphify ${_harness_platform} tools installed"
else
  _warn "graphify install (${_harness_platform}) failed — continuing without its tools"
fi

# ── Drop what the CLI leaves behind ─────────────────────────────────────────
# Every harness tree, not only the selected one: a selection change must not
# leave a dangling skill reference or a duplicate registration behind. Each
# step is a no-op when the file is absent.
read -r -a _harness_dirs <<< "$(_devbot_harness_dirs)"
for harness_dir in "${_harness_dirs[@]}"; do
  case "${harness_dir}" in
    "${_harness_dir}") ;;
    *) [[ -d "${PROJECT_DIR}/${harness_dir}" ]] || continue ;;
  esac

  # The module's SKILL.md is already delegated into the skills farm, so the
  # CLI's own copy is a duplicate: one client logs a WARN per duplicate, the
  # other registers the unnamespaced copy beside devbot:graphify. Only that
  # copy goes — a skill a user put at the same path is not ours to delete.
  skill_copy="${PROJECT_DIR}/${harness_dir}/skills/graphify"
  if _graphify_cli_skill_copy "${skill_copy}"; then
    rm -r -f "${skill_copy}"
  fi
  # The CLI writes a "## graphify" fragment pointing at the copy removed above.
  _graphify_strip_section "${PROJECT_DIR}/${harness_dir}/CLAUDE.md"
  # Byte-identical settings backup left by the CLI's hook-guard installer.
  rm -f "${PROJECT_DIR}/${harness_dir}/settings.json.graphify-bak" 2>/dev/null || true
done

# ── Remove graphify plugin (auto-discovered, avoids double-load) ────────────
# A plugin file left in a client directory loads twice: once from the file and
# once from auto-discovery. Both trees are swept, as above.
for harness_dir in "${_harness_dirs[@]}"; do
  PLUGIN_FILE="${PROJECT_DIR}/${harness_dir}/plugins/graphify.js"
  if [[ -f "${PLUGIN_FILE}" ]]; then
    rm -f "${PLUGIN_FILE}"
    _log "Removed ${harness_dir}/plugins/graphify.js (auto-discovered, explicit file not needed)"
  fi

  CLIENT_CONFIG="${PROJECT_DIR}/${harness_dir}/opencode.json"
  [[ -f "${CLIENT_CONFIG}" ]] || continue
  if ! command -v jq >/dev/null 2>&1; then
    _warn "jq not found — skipping legacy plugin cleanup in ${harness_dir}/opencode.json"
    continue
  fi
  if jq --arg plugin "${harness_dir}/plugins/graphify.js" \
    'if .plugin then .plugin |= map(select(. != $plugin)) else . end' \
    "${CLIENT_CONFIG}" > "${CLIENT_CONFIG}.tmp" 2>/dev/null; then
    if cmp -s "${CLIENT_CONFIG}" "${CLIENT_CONFIG}.tmp"; then
      # Already clean — skip the mv so reinit does not churn the mtime on
      # byte-identical content (audit-37 §4).
      rm -f "${CLIENT_CONFIG}.tmp"
    else
      mv "${CLIENT_CONFIG}.tmp" "${CLIENT_CONFIG}"
      _log "Removed graphify plugin from ${harness_dir}/opencode.json (avoids double loading)"
    fi
  else
    rm -f "${CLIENT_CONFIG}.tmp"
    _warn "Failed to process ${harness_dir}/opencode.json — skipping cleanup"
  fi
done

# Remove the graphify section from AGENTS.md if present (graphify install writes
# it, but the always-on context now lives in the memory vault). Also drop
# trailing blank lines: graphify install appends the section (with a blank
# separator) at EOF, and a plain section-strip leaves that separator behind —
# making reinit not byte-idempotent (audit-32 NOTE: AGENTS.md drifted between
# consecutive reinits).
AGENTS_MD="${PROJECT_DIR}/AGENTS.md"
if grep -q '^## graphify[[:space:]]*$' "${AGENTS_MD}" 2>/dev/null; then
  _graphify_strip_section "${AGENTS_MD}"
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
# The scope lives in .graphifyignore — the only thing that constrains the scan.
# It cannot be a `graphify update <path>` argument: that moves the output dir.
_GRAPHIFY_SCOPE="$(_graphify_detect_scope "${PROJECT_DIR}")"
_graphify_write_source_scope "${PROJECT_DIR}" \
  || _warn "graphify scope: could not update .graphifyignore"
case "${_GRAPHIFY_SCOPE}" in
  src)  _GRAPHIFY_SCOPE_LABEL="src/"; _log "Restricting graphify index to src/" ;;
  app)  _GRAPHIFY_SCOPE_LABEL="app/"; _log "Restricting graphify index to app/" ;;
  both) _GRAPHIFY_SCOPE_LABEL="src/ and app/"; _log "Restricting graphify index to src/ and app/" ;;
  *)    _GRAPHIFY_SCOPE_LABEL="nothing"; _warn "No src/ or app/ found — graphify will index nothing (disable the module)" ;;
esac

# ── Build initial knowledge graph ────────────────────────────────────────────
cd "${PROJECT_DIR}"

if [[ -f "graphify-out/graph.json" ]]; then
  _skip "Graph already built"
else
  DATE_STR=$(date '+%d %b %Y, %H:%M')
  _info "${DATE_STR} — Starting background knowledge graph build (indexing ${_GRAPHIFY_SCOPE_LABEL})..."
  # Placeholder so the graphify MCP server can start immediately instead of
  # blocking for the ~1min build (opencode times out first). The server
  # hot-reloads graph.json when `graphify update` overwrites it.
  _graphify_ensure_placeholder_graph "${PROJECT_DIR}"

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
