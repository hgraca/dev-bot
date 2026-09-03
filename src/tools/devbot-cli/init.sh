#!/usr/bin/env bash
# =============================================================================
# src/tools/devbot-cli/init.sh
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
  _fatal "directory '${1:-.}' does not exist or cannot be resolved."
  exit 1
fi

PROJECT_NAME="$(basename "${PROJECT_DIR}")"
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# ── Write devbot.jsonc (merged from root config + project overrides) ───────────

_write_devbot_config() {
  local config="${PROJECT_DIR}/.devbot.project.jsonc"

  if [[ -f "${config}" ]]; then
    # audit-32/33 (b): a pre-existing config may lack project_name (e.g. the
    # harness fixtures write one with only harness/modules). search-memories
    # and qmd/init.sh must agree on the collection name, so ensure the key is
    # present — injected as the project dir basename when missing, preserving
    # the rest of the file (comments and ordering) verbatim.
    local existing
    existing="$(python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${config}" project_name 2>/dev/null || true)"
    if [[ -n "${existing}" ]]; then
      _skip ".devbot.project.jsonc already exists (project_name: ${existing})"
      return 0
    fi
    _info "Injecting missing project_name into ${config} ..."
    PROJECT_NAME="${PROJECT_NAME}" CONFIG="${config}" python3 - <<'PY'
import os, sys

name = os.environ["PROJECT_NAME"]
path = os.environ["CONFIG"]
raw = open(path, encoding="utf-8").read()


def find_top_brace(text):
    """First '{' that is outside strings and comments."""
    i, n = 0, len(text)
    while i < n:
        if text[i] == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                elif text[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            i = j
            continue
        if text[i : i + 2] == "//":
            j = text.find("\n", i)
            if j == -1:
                break
            i = j
            continue
        if text[i : i + 2] == "/*":
            j = text.find("*/", i + 2)
            if j == -1:
                break
            i = j + 2
            continue
        if text[i] == "{":
            return i
        i += 1
    return -1


brace = find_top_brace(raw)
if brace == -1:
    print("WARN: cannot locate top-level { in " + path + " — leaving file unchanged", file=sys.stderr)
    sys.exit(1)
# Splice after the opening brace. Covers both "{\n  ..." and "{...}" layouts.
insert = '\n  "project_name": "%s",' % name
open(path, "w", encoding="utf-8").write(raw[: brace + 1] + insert + raw[brace + 1 :])
PY
    _ok "project_name written to .devbot.project.jsonc"
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

# Ensure modules exists (project overrides; global defaults read at runtime)
if 'modules' not in result:
    result['modules'] = {}

# Merge from root config if it exists
if os.path.isfile(root_cfg_path):
    with open(root_cfg_path) as f:
        root = json.loads(_strip_jsonc_comments(f.read()))

    if 'auto_recover' in root and isinstance(root['auto_recover'], dict):
        result['auto_recover'].update(root['auto_recover'])

    if 'guards' in root:
        result['guards'] = root['guards']

    # modules is intentionally NOT merged here: the project's map holds
    # its overrides; the effective enabled/disabled state is computed at read
    # time by _devbot_get_disabled_modules (project value wins over global).

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
