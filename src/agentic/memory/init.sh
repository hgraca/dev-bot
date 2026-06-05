#!/usr/bin/env bash
# =============================================================================
# src/agentic/memory/init.sh
# Initialises the memory system for a project:
#   Scaffolds the <devbot-dir>/memory/ vault directory hierarchy
#
# The remember-session plugin is now a session.idle-based opencode plugin
# (src/agentic/memory/plugins/remember-session.ts) — no git hook needed.
#
# Idempotent — safe to re-run at any time.
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  cp -r "${tmpl_src}/"* "$vault/"

  # Symlink global-memories to the dev-bot central store
  # Remove first if it exists as a real dir (from template copy or prior run)
  [[ -e "${vault}/latent/global" && ! -L "${vault}/latent/global" ]] && rm -rf "${vault}/latent/global"
  ln -sfn "${SCRIPT_DIR}/global-memories" "${vault}/latent/global"

  # ── QMD collection for global memories ────────────────────────────────────
  # QMD doesn't follow symlinks, so create a collection pointing at the real
  # global-memories path. Uses a fixed shared name — all projects share the
  # same global knowledge base, so a single QMD collection suffices.
  local global_collection="dev-bot-global"

  if qmd collection show "${global_collection}" >/dev/null 2>&1; then
    _skip "QMD collection '${global_collection}' already exists"
  else
    qmd collection add "${SCRIPT_DIR}/global-memories" --name "${global_collection}" >/dev/null 2>&1 && \
      _ok "QMD collection '${global_collection}' created"
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

  # Read commit_memory from project config (default: false)
  local commit_memory="false"
  local config="${project_dir}/.devbot.project.jsonc"
  if [[ -f "${config}" ]]; then
    commit_memory=$(python3 -c "
import json
with open('${config}') as f:
    data = json.load(f)
print('true' if data.get('commit_memory', False) else 'false')
" 2>/dev/null || echo "false")
  fi

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
