#!/usr/bin/env bash
# =============================================================================
# bin/agentic-tools.sh
# Lists agentic tools available to agents in the current project.
# Inspects .opencode/tools/*.ts and outputs a JSON array (default) or
# markdown table (--md) with tool name, path, description (first section
# before Parameters), and a how-to array of parameter objects parsed from
# the Parameters: section.
#
# Usage:
#   bin/agentic-tools.sh          # JSON output (default)
#   bin/agentic-tools.sh --json   # JSON output
#   bin/agentic-tools.sh --md     # Markdown table output
#   devbot agentic-tools          # JSON output (default)
#   devbot agentic-tools --md     # Markdown table output
# =============================================================================

set -euo pipefail

# ── Resolve paths ──────────────────────────────────────────────────────────────
DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

# ── Source shared library ──────────────────────────────────────────────────────
# shellcheck source=../src/_shared/functions.sh
source "${DEV_BOT_ROOT}/src/_shared/functions.sh"

# ── Extract tool info via inline Python ───────────────────────────────────────
# For .ts: reads description property.
# For .sh: reads description from comment block (second paragraph after shebang).
_extract_tool_info() {
  local tool_file="$1"
  local ext="${tool_file##*.}"
  python3 - "$tool_file" "$ext" <<'PYEOF'
import json, re, sys

tool_file = sys.argv[1]
ext = sys.argv[2]

with open(tool_file) as f:
    content = f.read()

if ext == "ts":
    match = re.search(
        r'description:\s*\n(\s*"(?:\\.|[^"\\])*"(?:\s*\+\s*\n\s*"(?:\\.|[^"\\])*")*)',
        content
    )
    if not match:
        sys.exit(1)
    strings = re.findall(r'"((?:\\.|[^"\\])*)"', match.group(1))
    full_desc = ''.join(strings)
else:
    # .sh: extract description from comment block (lines starting with # after shebang)
    lines = content.split('\n')
    desc_lines = []
    in_block = False
    for line in lines:
        if line.startswith('#!'):
            continue
        if line.startswith('# ='):
            in_block = True
            continue
        if in_block and line == '#':
            desc_lines.append('')
            continue
        if in_block and line.startswith('# '):
            stripped = line[2:]
            if stripped.strip().startswith('src/') or stripped.strip().startswith('bin/'):
                continue
            desc_lines.append(stripped)
            continue
        if in_block and not line.startswith('#'):
            break  # end of comment block
        # Simple comment format (no === block)
        if not in_block and line.startswith('# '):
            stripped = line[2:].strip()
            if stripped.startswith('src/') or stripped.startswith('bin/'):
                continue
            desc_lines.append(line[2:])
        elif not in_block and line == '#':
            if desc_lines:
                desc_lines.append('')
        elif not in_block and desc_lines and not line.startswith('#'):
            break
    full_desc = '\n'.join(desc_lines) if desc_lines else ''

if not full_desc:
    sys.exit(1)

# Decode escape sequences
full_desc = full_desc.replace('\\n', '\n').replace('\\t', '\t').replace('\\"', '"').replace('\\\\', '\\')

# Split into main description (before Parameters section) and parameters section
parts = full_desc.split('\n\nParameters:', 1)
main_desc = parts[0].strip()

# Parse Parameters section as a JSON array of parameter objects
params_json = []
if len(parts) > 1:
    params_section = parts[1].strip()
    param_pattern = re.compile(
        r'^- ([\w-]+)\s*\((\w+)(?:,\s*(required|optional))?\):\s*(.+)',
        re.MULTILINE
    )
    for m in param_pattern.finditer(params_section):
        params_json.append({
            "name": m.group(1),
            "type": m.group(2),
            "required": m.group(3) == "required",
            "desc": m.group(4).strip(),
        })

howto = json.dumps(params_json, ensure_ascii=False)
main_desc = main_desc.replace('|', '\\|').replace('\n', ' ')

print(f'DESC:{main_desc}')
print(f'HOWTO:{howto}')

PYEOF
}

# ── List tools (markdown output) ──────────────────────────────────────────────
# Preserves the original markdown-table output format exactly.
_list_tools_md() {
  _header_1 "Agentic Tools"

  local tools_dir="${DEV_BOT_ROOT}/.opencode/tools"

  if [[ ! -d "${tools_dir}" ]]; then
    _warn ".opencode/tools/ directory not found — are you in a dev-bot project?"
    exit 0
  fi

  local ts_files=()
  while IFS= read -r -d '' f; do
    ts_files+=("$f")
  done < <(find -L "${tools_dir}" -maxdepth 1 \( -name '*.ts' -o -name '*.sh' \) \( -type f -o -type l \) -print0 2>/dev/null)

  if [[ ${#ts_files[@]} -eq 0 ]]; then
    _info "No tool files found in .opencode/tools/"
    exit 0
  fi

  # Build table content
  local table_content=""
  table_content+="| tool | path | description | how-to |"$'\n'
  table_content+="|------|------|-------------|--------|"$'\n'

  for ts_file in "${ts_files[@]}"; do
    local tool_name
    tool_name="$(basename "${ts_file}")"
    tool_name="${tool_name%.ts}"
    tool_name="${tool_name%.sh}"
    local rel_path
    rel_path=".opencode/tools/$(basename "${ts_file}")"

    local desc="" howto=""
    local extract_output
    extract_output="$(_extract_tool_info "${ts_file}" 2>/dev/null)" || true
    if [[ -n "${extract_output}" ]]; then
      while IFS= read -r line; do
        case "${line}" in
          DESC:*) desc="${line#DESC:}" ;;
          HOWTO:*) howto="${line#HOWTO:}" ;;
        esac
      done <<< "${extract_output}"
    fi

    if [[ -z "${desc}" ]]; then
      desc="*(could not extract description)*"
    fi
    if [[ -z "${howto}" ]]; then
      howto="*(could not extract how-to)*"
    fi

    table_content+="| ${tool_name} | ${rel_path} | ${desc} | ${howto} |"$'\n'
  done

  # Format the table
  local formatted_table
  formatted_table="$(echo "${table_content}" | python3 "${DEV_BOT_ROOT}/src/agentic/format-md/tools/format-md.py")"

  echo ""
  echo "${formatted_table}"

  echo ""
  _ok "${#ts_files[@]} tool(s) listed"
}

# ── List tools (JSON output) ──────────────────────────────────────────────────
# Outputs a JSON array of tool objects to stdout. No ANSI codes, no headers,
# no decorative output — only valid JSON.
_list_tools_json() {
  local tools_dir="${DEV_BOT_ROOT}/.opencode/tools"

  if [[ ! -d "${tools_dir}" ]]; then
    echo '[]'
    exit 0
  fi

  local ts_files=()
  while IFS= read -r -d '' f; do
    ts_files+=("$f")
  done < <(find -L "${tools_dir}" -maxdepth 1 \( -name '*.ts' -o -name '*.sh' \) \( -type f -o -type l \) -print0 2>/dev/null)

  if [[ ${#ts_files[@]} -eq 0 ]]; then
    echo '[]'
    exit 0
  fi

  # Pipe tool records (separated by \a) to python3 for JSON construction.
  # Using \a (bell, 0x07) as field separator — extremely unlikely to appear
  # in tool descriptions.
  for ts_file in "${ts_files[@]}"; do
    local tool_name
    tool_name="$(basename "${ts_file}")"
    tool_name="${tool_name%.ts}"
    tool_name="${tool_name%.sh}"
    local rel_path
    rel_path=".opencode/tools/$(basename "${ts_file}")"

    local desc="" howto=""
    local extract_output
    extract_output="$(_extract_tool_info "${ts_file}" 2>/dev/null)" || true
    if [[ -n "${extract_output}" ]]; then
      while IFS= read -r line; do
        case "${line}" in
          DESC:*) desc="${line#DESC:}" ;;
          HOWTO:*) howto="${line#HOWTO:}" ;;
        esac
      done <<< "${extract_output}"
    fi

    if [[ -z "${desc}" ]]; then
      desc="*(could not extract description)*"
    fi
    if [[ -z "${howto}" ]]; then
      howto="*(could not extract how-to)*"
    fi

    printf '%s\a%s\a%s\a%s\n' "${tool_name}" "${rel_path}" "${desc}" "${howto}"
  done | python3 -c '
import sys, json

tools = []
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    parts = line.split("\a", 3)
    if len(parts) < 4:
        continue
    tool_name, rel_path, desc, howto = parts
    # Unescape pipe characters (escaped in _extract_tool_info for markdown)
    desc = desc.replace("\\|", "|")
    # Parse howto as JSON array (output from _extract_tool_info)
    try:
        howto_parsed = json.loads(howto)
    except json.JSONDecodeError:
        howto_parsed = []
    tools.append({
        "tool": tool_name,
        "path": rel_path,
        "description": desc,
        "howto": howto_parsed
    })

print(json.dumps(tools, indent=2))
'
}

# ── main ───────────────────────────────────────────────────────────────────────
main() {
  local format="json"

  if [[ $# -gt 0 ]]; then
    case "$1" in
      --json) format="json" ;;
      --md)   format="md" ;;
      *)
        echo "Usage: $(basename "$0") [--json|--md]" >&2
        echo "  --json   Output JSON array (default)" >&2
        echo "  --md     Output markdown table" >&2
        exit 1
        ;;
    esac
  fi

  if [[ "${format}" == "md" ]]; then
    _list_tools_md
  else
    _list_tools_json
  fi
}

main "$@"
