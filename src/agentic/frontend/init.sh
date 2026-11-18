#!/usr/bin/env bash
# =============================================================================
# src/agentic/frontend/init.sh
# Per-project wiring for the frontend module.
#
# Two jobs:
#
#   1. Seed .impeccable/config.json with the Impeccable design hook enabled.
#      The hook itself is the module's own file.edited hook
#      (hooks.json → tools/impeccable-hook.sh), which runs the rule-based
#      design detector over each UI file as it is edited. Upstream's
#      `impeccable hooks on` cannot wire it here — it knows Claude Code, Codex,
#      Cursor, Copilot and Gemini, and dev-bot links skills somewhere its
#      lookup does not reach — so the module ships the dispatch.
#
#      Seed-once: a project that turned the hook off (`impeccable hooks off`)
#      or retuned the limits keeps its file. init never re-enables it.
#
#   2. Keep the machine-local record out of git. dev-bot never writes
#      `.impeccable/config.local.json` — it is what the upstream manifest
#      installer records per machine, and dev-bot does not install a manifest
#      (its own hook dispatch runs the detector). Ignoring it here keeps a
#      developer who does run that installer from committing their copy.
#
# Run by bin/init.sh during devbot init.
# =============================================================================

set -euo pipefail

# shellcheck source=./functions.sh
source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  _fatal "Directory '${1:-.}' does not exist or cannot be resolved."
  exit 1
fi

CONFIG_DIR="${PROJECT_DIR}/.impeccable"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# What `impeccable hooks on` writes for the hook block, minus the consent (which
# stays machine-local). The key shape is the engine's own: hook.enabled is the
# switch, hook.limits bounds what a run may report.
_seed_config() {
  cat > "${CONFIG_FILE}" <<'JSON'
{
  "hook": {
    "enabled": true,
    "limits": {
      "maxFindings": 5,
      "maxChars": 8000
    }
  }
}
JSON
}

main() {
  _info "frontend — project initialization"

  mkdir -p "${CONFIG_DIR}"

  if [[ -f "${CONFIG_FILE}" ]]; then
    _skip ".impeccable/config.json exists — left as is (impeccable hooks off stays off)"
  else
    _seed_config
    _ok ".impeccable/config.json written — design hook enabled (limits: 5 findings, 8000 chars)"
  fi

  # Machine-local record, never committed. .gitignore rather than
  # .git/info/exclude: a collaborator who never ran devbot init would otherwise
  # be free to commit their own copy.
  if [[ -d "${PROJECT_DIR}/.git" ]]; then
    _upsert_gitignore_section "${PROJECT_DIR}/.gitignore" \
      "# >>> DEVBOT - frontend" \
      "# <<< DEVBOT - frontend" \
      "# Impeccable's per-machine hook consent — never shared, never committed." \
      ".impeccable/config.local.json"
    _ok ".gitignore excludes .impeccable/config.local.json"
  else
    _skip "not a git repository — skipping .gitignore"
  fi

  _info "The design detector runs on UI edits from now on (no per-machine install needed)."
  _info "It downloads the engine (about 25 MB) on its first run; 'impeccable hooks off' turns the hook off for the project,"
  _info "IMPECCABLE_HOOK_DISABLED=1 turns it off for one shell."
  _info "Findings land in .agents/logs/impeccable.log — impeccable detect --changed runs the same check on demand."

  _ok "frontend project initialization complete"
}

main "$@"
