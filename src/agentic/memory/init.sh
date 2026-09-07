#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/init.sh
# Initialises the memory system for a project:
#   Scaffolds the <devbot-dir>/memory/ vault directory hierarchy
#
# Memory capture is triggered by the primary agent's finish flow (see the
# `agent-communication` skill), not by a git-commit hook.
#
# Idempotent — safe to re-run at any time.
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The shipped global-memories knowledge base lives at the repo root under
# storage/ (tracked via a .gitignore exception despite storage/*).
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
GLOBAL_MEMORIES_DIR="${DEV_BOT_ROOT}/storage/global-memories"

# shellcheck source=./functions.sh
source "${SCRIPT_DIR}/functions.sh"

# ── Resolve project root ──────────────────────────────────────────────────────
_resolve_root() {
  local dir="$SCRIPT_DIR"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.git" || -f "$dir/opencode.jsonc" || -d "$dir/.claude" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  pwd
}

# ── Step 1: Scaffold vault from template ────────────────────────────────────
_scaffold_vault() {
  local target_path="${1:-.}"
  local tmpl_src="${SCRIPT_DIR}/skills/memory-management/_tmpl"

  # Resolve to absolute path
  [[ "${target_path}" != /* ]] && target_path="$(pwd)/${target_path}"

  local devbot_dir
  devbot_dir="$(_devbot_get_project_dir "${target_path}")"
  local vault="${target_path}/${devbot_dir}/memory"

  echo
  _info "memory — vault scaffolding at ${target_path}"

  if [[ ! -d "$tmpl_src" ]]; then
    echo "  ${TEXT_BOLD}${TEXT_YELLOW}⚠${TEXT_CLEAR}  Template not found at ${tmpl_src}" >&2
    return 1
  fi

  mkdir -p "$vault"
  # Seed the template without clobbering: -n (no-clobber) preserves per-project
  # content on reinit — e.g. active/preemptive-skill-loading-list.md regenerated
  # by create-project-report, or active/mcp.md by generate-mcp-guide — that would
  # otherwise be overwritten by the template default on every `devbot reinit`
  # (audit-22: a reinit silently reverted the test-project's curated manifest).
  cp -rn "${tmpl_src}/"* "$vault/"

  # Symlink global-memories to the dev-bot central store
  # Remove first if it exists as a real dir (from template copy or prior run)
  [[ -e "${vault}/latent/global" && ! -L "${vault}/latent/global" ]] && rm -rf "${vault}/latent/global"
  if ln -sfn "${GLOBAL_MEMORIES_DIR}" "${vault}/latent/global"; then
    _ok "Global memories linked (${vault}/latent/global → ${GLOBAL_MEMORIES_DIR})"
  else
    _warn "Could not create global memories symlink at ${vault}/latent/global"
  fi

  # ── Memory-search engine registration for global memories ─────────────────
  # The shared global store is registered under whichever engine
  # memory_search_provider selects. Neither engine follows symlinks, so the
  # latent/global symlink above is never indexed — each engine must register
  # the REAL global-memories path:
  #   - qmd:   a "dev-bot-global" collection pointing at the real path (fixed
  #            shared name — all projects share the same global knowledge base)
  #   - mdctx: a flat keyword index at ${DEV_BOT_ROOT}/storage/.mdctx (already
  #            gitignored: .gitignore has storage/* except global-memories/)
  # audit-25 F6: registration failure must surface loudly — a silently
  # swallowed '&& _ok' left the global store unreachable on a fresh install
  # with no visible error (only the absence of the collection/index).
  local provider
  provider="$(_devbot_get_memory_search_provider "${target_path}")"

  if [[ "${provider}" == "mdctx" ]]; then
    if ! command -v mdctx >/dev/null 2>&1; then
      _warn "mdctx not installed — skipping global index build (run 'devbot install' first)"
    else
      local global_index_dir="${DEV_BOT_ROOT}/storage/.mdctx"
      mkdir -p "${global_index_dir}"
      if mdctx build "${GLOBAL_MEMORIES_DIR}" -o "${global_index_dir}/context-index.json" >/dev/null 2>&1; then
        _ok "mdctx global index written (${global_index_dir}/context-index.json)"
      else
        _warn "Could not build mdctx global index for ${GLOBAL_MEMORIES_DIR}"
        _warn "The global memory store will be unreachable via search-memories — check that mdctx is installed."
      fi
    fi
  else
    local global_collection="dev-bot-global"

    if qmd collection show "${global_collection}" >/dev/null 2>&1; then
      _skip "QMD collection '${global_collection}' already exists"
    elif qmd collection add "${GLOBAL_MEMORIES_DIR}" --name "${global_collection}" >/dev/null 2>&1; then
      _ok "QMD collection '${global_collection}' created"
    else
      _warn "Could not register QMD collection '${global_collection}' for ${GLOBAL_MEMORIES_DIR}"
      _warn "The global memory store will be unreachable via search-memories — check that qmd is installed."
    fi
  fi

  _ok "Vault scaffolded at ${target_path}"
}

# Source shared gitignore library
_upsert_section() {
  # shellcheck source=../../_shared/functions.sh
  source "${SCRIPT_DIR}/../../_shared/functions.sh" && \
  _upsert_gitignore_section "$@"
}

_ensure_gitignore() {
  local project_dir="${1:-.}"
  [[ "${project_dir}" != /* ]] && project_dir="$(pwd)/${project_dir}"
  local exclude="${project_dir}/.git/info/exclude"
  mkdir -p "$(dirname "$exclude")"

  echo
  _info "memory — .git/info/exclude"

  local devbot_dir
  devbot_dir="$(_devbot_get_project_dir "${project_dir}")"

  # Read commit_memory with project-first, global-fallback precedence
  # (defaults to false when unset in both configs)
  local commit_memory
  commit_memory="$(_devbot_get_config "commit_memory" "${project_dir}")"

  local -a gitignore_paths=("!${devbot_dir}")

  # Only blanket-ignore memory if commit_memory is false
  if [[ "${commit_memory}" != "true" ]]; then
    gitignore_paths+=("${devbot_dir}/memory")
  fi

  gitignore_paths+=(
    "${devbot_dir}/memory/latent/global"
    "${devbot_dir}/memory/thinking"
    "${devbot_dir}/memory/work"
  )

  if _upsert_section "${exclude}" \
    "# >>> DEVBOT - memory" \
    "# <<< DEVBOT - memory" \
    "${gitignore_paths[@]}"
  then
    if [[ -f "${exclude}" ]]; then
      _ok ".git/info/exclude updated"
    else
      _ok ".git/info/exclude created"
    fi
  else
    _skip ".git/info/exclude upsert failed"
  fi
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
  local target="${1:-.}"
  [[ "${target}" != /* ]] && target="$(pwd)/${target}"

  _ok "Target project: ${target}"

  _scaffold_vault "$target"
  _ensure_gitignore "$target"
}

main "$@"
