#!/usr/bin/env bash
# =============================================================================
# src/tools/devbot/init.sh
# Writes .devbot.project.jsonc at project root.
# Merges values from <devbot-root>/.devbot.global.jsonc with project-specific values.
# Idempotent — skips if .devbot.project.jsonc already exists.
#
# Usage:
#   init.sh                    # init in current directory
#   init.sh /path/to/project   # init in specified project
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

PROJECT_DIR="$(cd "${1:-$(pwd)}" && pwd 2>/dev/null || true)"

if [[ -z "${PROJECT_DIR}" || ! -d "${PROJECT_DIR}" ]]; then
  echo "Error: directory '${1:-.}' does not exist or cannot be resolved." >&2
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_DIR}")"
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# ── Write devbot.jsonc (merged from root config + project overrides) ───────────

_write_devbot_config() {
  local config="${PROJECT_DIR}/.devbot.project.jsonc"

  if [[ -f "${config}" ]]; then
    _skip ".devbot.project.jsonc already exists"
    return 0
  fi

  local dist="${DEV_BOT_ROOT}/.devbot.project.dist.jsonc"
  if [[ ! -f "${dist}" ]]; then
    _warn "Distribution template not found at ${dist}"
    return 1
  fi

  _info "Writing .devbot.project.jsonc (merged from root config)..."

  python3 -c "
import json, os


def _strip_jsonc_comments(text):
    out, i = [], 0
    while i < len(text):
        if text[i] == '\"':
            j = i + 1
            while j < len(text):
                if text[j] == '\\\\':
                    j += 2
                elif text[j] == '\"':
                    j += 1
                    break
                else:
                    j += 1
            out.append(text[i:j])
            i = j
        elif text[i:i + 2] == '//':
            j = text.find('\\n', i)
            if j == -1:
                break
            i = j
        elif text[i:i + 2] == '/*':
            j = text.find('*/', i + 2)
            if j == -1:
                break
            i = j + 2
        else:
            out.append(text[i])
            i += 1
    return ''.join(out)


root_cfg_path = '${DEV_BOT_ROOT}/.devbot.global.jsonc'
project_name  = '${PROJECT_NAME}'
output_path   = '${config}'
dist_path     = '${dist}'

# Load default project config
with open(dist_path) as f:
    result = json.loads(_strip_jsonc_comments(f.read()))

# Substitute project name placeholder
result['project_name'] = project_name

# Ensure disabled_modules exists
if 'disabled_modules' not in result:
    result['disabled_modules'] = []

# Merge from root config if it exists
if os.path.isfile(root_cfg_path):
    with open(root_cfg_path) as f:
        root = json.loads(_strip_jsonc_comments(f.read()))

    if 'auto_recover' in root and isinstance(root['auto_recover'], dict):
        result['auto_recover'].update(root['auto_recover'])

    if 'guards' in root:
        result['guards'] = root['guards']

    if 'disabled_modules' in root and isinstance(root['disabled_modules'], list):
        # Merge: union of global disabled_modules with any from project template
        project_disabled = result.get('disabled_modules', [])
        merged = sorted(set(root['disabled_modules']) | set(project_disabled))
        result['disabled_modules'] = merged

# Write merged config
with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)
    f.write('\n')
"
  _ok ".devbot.project.jsonc written"
}

_ensure_gitignore() {
  local project_dir="${1:-.}"
  [[ "${project_dir}" != /* ]] && project_dir="$(pwd)/${project_dir}"
  local exclude="${project_dir}/.git/info/exclude"
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

  echo
  _info "DEVBOT — .git/info/exclude"

  local -a gitignore_paths=(
    ".devbot.project.jsonc"
    "${devbot_dir}/logs"
    "${devbot_dir}/agents"
    "${devbot_dir}/commands"
    "${devbot_dir}/skills"
    "${devbot_dir}/tools"
  )

  if _upsert_gitignore_section "${exclude}" \
    "# >>> DEVBOT" \
    "# <<< DEVBOT" \
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

_write_devbot_config
_ensure_gitignore "${PROJECT_DIR}"
_link_modules
