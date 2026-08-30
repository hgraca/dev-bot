#!/usr/bin/env bash
# =============================================================================
# bin/prune.sh
# Prune old opencode sessions. Deletes sessions older than N days.
#
# Usage:
#   bin/prune.sh [days]           # prune current project (default: 30 days)
#   bin/prune.sh --all|-a [days]  # prune all registered projects
# =============================================================================

set -euo pipefail

# ── Resolve paths ──────────────────────────────────────────────────────────────
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── Defaults ───────────────────────────────────────────────────────────────────
DEFAULT_DAYS=30

# ── Parse arguments ───────────────────────────────────────────────────────────
ALL_PROJECTS=false
DAYS="${DEFAULT_DAYS}"

for arg in "$@"; do
  case "${arg}" in
    --all|-a)
      ALL_PROJECTS=true
      ;;
    --help|-h)
      echo "Usage: devbot prune [days] [--all|-a]"
      echo ""
      echo "Prune old opencode sessions older than <days> (default: ${DEFAULT_DAYS})."
      echo ""
      echo "Options:"
      echo "  --all, -a    Prune all registered projects"
      echo "  --help, -h   Show this help"
      exit 0
      ;;
    *)
      # Assume it's the days argument
      if [[ "${arg}" =~ ^[0-9]+$ ]]; then
        DAYS="${arg}"
      else
        _fatal "Unknown argument: ${arg}"
        echo "Usage: devbot prune [days] [--all|-a]"
        exit 1
      fi
      ;;
  esac
done

# ── Prune a single project directory ───────────────────────────────────────────
_prune_project() {
  local project_dir="$1"

  _header_2 "Pruning: ${project_dir}"

  # Check harness — only prune for opencode
  local harness
  harness=$(_devbot_get_harness "${project_dir}")

  if [[ "${harness}" != "opencode" ]]; then
    _info "Harness is '${harness}' — skipping (only opencode sessions are pruned)"
    return
  fi

  # Check if opencode binary exists
  local opencode_bin="${HOME}/.opencode/bin/opencode"
  if [[ ! -f "${opencode_bin}" ]]; then
    _warn "opencode binary not found at ${opencode_bin} — skipping"
    return
  fi

  # Calculate cutoff timestamp (milliseconds since epoch)
  local cutoff_ms
  cutoff_ms=$(python3 -c "
import time
cutoff = time.time() - (${DAYS} * 86400)
print(int(cutoff * 1000))
")

  _info "Keeping sessions updated within the last ${DAYS} day(s) (cutoff: $(python3 -c "
import datetime
print(datetime.datetime.fromtimestamp(${cutoff_ms} / 1000).strftime('%Y-%m-%d'))
"))"

  # List sessions in JSON and process
  local sessions_json
  sessions_json=$(cd "${project_dir}" && "${opencode_bin}" session list --format json 2>/dev/null) || {
    _warn "Failed to list sessions for ${project_dir}"
    return
  }

  if [[ -z "${sessions_json}" || "${sessions_json}" == "[]" ]]; then
    _info "No sessions found"
    return
  fi

  # Filter and delete old sessions
  local to_delete
  to_delete=$(echo "${sessions_json}" | python3 -c "
import json, sys
sessions = json.loads(sys.stdin.read())
cutoff = ${cutoff_ms}
old = [s for s in sessions if s.get('updated', 0) < cutoff]
for s in old:
    print(json.dumps({'id': s['id'], 'title': s.get('title', ''), 'updated': s.get('updated', 0)}))
")

  local delete_count=0
  local keep_count=0
  keep_count=$(echo "${sessions_json}" | python3 -c "import json,sys; print(len([s for s in json.loads(sys.stdin.read()) if s.get('updated', 0) >= ${cutoff_ms}]))" 2>/dev/null || echo "0")

  if [[ -z "${to_delete}" ]]; then
    _ok "All ${keep_count} session(s) are within the retention window — nothing to prune"
    return
  fi

  local old_count
  old_count=$(echo "${to_delete}" | wc -l)

  _info "${old_count} session(s) older than ${DAYS} day(s), ${keep_count} session(s) to keep"
  echo

  while IFS= read -r row; do
    local session_id
    local session_title
    session_id=$(echo "${row}" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['id'])" 2>/dev/null)
    session_title=$(echo "${row}" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('title', ''))" 2>/dev/null)

    if [[ -z "${session_id}" ]]; then
      continue
    fi

    _header_3 "Deleting: ${session_title:-${session_id}}"
    if cd "${project_dir}" && "${opencode_bin}" session delete "${session_id}" 2>/dev/null; then
      delete_count=$((delete_count + 1))
      _ok "Deleted ${session_id}"
    else
      _warn "Failed to delete ${session_id}"
    fi
  done <<< "${to_delete}"

  echo
  _ok "Pruned ${delete_count} session(s), kept ${keep_count} session(s)"
}

# ── Read registered projects from global config ────────────────────────────────
_get_projects() {
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  if [[ ! -f "${config}" ]]; then
    echo "[]"
    return
  fi

  python3 -c "
import json, sys
sys.path.insert(0, '${DEV_BOT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
try:
    data = load_jsonc('${config}')
    projects = data.get('projects', [])
    print(json.dumps(projects))
except Exception:
    print('[]')
" 2>/dev/null || echo "[]"
}

# ── main ───────────────────────────────────────────────────────────────────────
main() {
  local total_start=${SECONDS}

  _header_1 "DevBot Prune"

  if [[ "${ALL_PROJECTS}" == "true" ]]; then
    # Prune all registered projects
    local projects_json
    projects_json=$(_get_projects)

    local project_count
    project_count=$(echo "${projects_json}" | python3 -c "import json,sys; print(len(json.loads(sys.stdin.read())))" 2>/dev/null || echo "0")

    if [[ ${project_count} -eq 0 ]]; then
      _info "No projects registered in .devbot.global.jsonc::projects"
      exit 0
    fi

    _info "Pruning ${project_count} registered project(s)"

    while IFS= read -r project_dir; do
      _prune_project "${project_dir}"
    done < <(echo "${projects_json}" | python3 -c "
import json, sys
for p in json.loads(sys.stdin.read()):
    print(p)
" 2>/dev/null)
  else
    # Prune current directory
    _prune_project "$(pwd)"
  fi

  echo
  _header_2 "✔  DevBot prune complete"
  echo -e "  ${TEXT_DIM}⏱  Total: $(_fmt_duration $(( SECONDS - total_start )))${TEXT_CLEAR}"
  echo
}

main "$@"
