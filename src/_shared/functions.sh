#!/usr/bin/env bash
# =============================================================================
# src/_shared/functions.sh
# Shared library: upsert marked sections in gitignore-style files and git hooks.
#
# Available functions:
#
#   _upsert_gitignore_section <file> <start_marker> <end_marker> <lines...>
#     Upsert a marked section in any ignore-style file (.gitignore, etc.).
#
#   _upsert_hook_section <hook_file> <start_marker> <end_marker> <lines...>
#     Upsert a marked section in a git hook file.
#     Creates the file with a #!/usr/bin/env bash shebang if new.
#     Makes the hook file executable.
#
#   _upsert_opencode_plugin <opencode_jsonc_path> <plugin_entry>
#     Adds a string entry to the "plugin" array in an opencode.jsonc file.
#     Idempotent — no-op if the entry already exists.
#     Preserves JSONC formatting and comments.
#
# All functions are silent — they only manipulate the file. Callers should
# add their own info/ok/skip messages around them.
# =============================================================================

# ── Project root ───────────────────────────────────────────────────────────────

export DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ── Common output helpers ──────────────────────────────────────────────────────

TEXT_BOLD='\033[1m'
TEXT_GREEN='\033[0;32m'
TEXT_BLUE='\033[0;34m'
TEXT_YELLOW='\033[38;5;220m'
TEXT_ORANGE='\033[38;5;208m'
TEXT_RED='\033[0;31m'
TEXT_DIM='\033[2m'
TEXT_CLEAR='\033[0m'

_debug() { echo -e "  ${TEXT_BOLD}${TEXT_RED}[DEBUG]  $* ${TEXT_CLEAR}"; }
_info() { echo -e "  ${TEXT_BOLD}${TEXT_BLUE}ℹ  $* ${TEXT_CLEAR}"; }
_ok()   { echo -e "  ${TEXT_BOLD}${TEXT_GREEN}✔  $* ${TEXT_CLEAR}"; }
_skip() { echo -e "  ${TEXT_BOLD}${TEXT_DIM}›  $* ${TEXT_CLEAR}"; }
_notice() { echo -e "  ${TEXT_BOLD}${TEXT_YELLOW}⚠  $* ${TEXT_CLEAR}"; }
_warn() { echo -e "  ${TEXT_BOLD}${TEXT_ORANGE}⚠⚠  $* ${TEXT_CLEAR}"; }
_error() { echo -e "  ${TEXT_BOLD}${TEXT_RED}❌  $* ${TEXT_CLEAR}"; }
_log()  { echo -e "  ${TEXT_DIM}-  $* ${TEXT_CLEAR}"; }
_step()   { echo -e "  ${TEXT_BOLD}→  $* ${TEXT_CLEAR}"; }

_header_1() {
    echo
    echo -e "${TEXT_BOLD}${TEXT_GREEN}══════════════════════════════════════════${TEXT_CLEAR}"
    echo -e "${TEXT_BOLD}${TEXT_GREEN}  $*${TEXT_CLEAR}"
    echo -e "${TEXT_BOLD}${TEXT_GREEN}══════════════════════════════════════════${TEXT_CLEAR}"
    echo
}
_header_2() { echo -e "\n${TEXT_BOLD}${TEXT_BLUE}━━━ $1 ━━━${TEXT_CLEAR}"; }
_header_3() { echo -e "\n  ${TEXT_BOLD}── $* ──${TEXT_CLEAR}"; }

# ── Shared utilities ──────────────────────────────────────────────────────────────

_fmt_duration() {
  local seconds=$1
  local minutes=$(( seconds / 60 ))
  local secs=$(( seconds % 60 ))
  if [[ ${minutes} -gt 0 ]]; then
    echo "${minutes}m ${secs}s"
  else
    echo "${secs}s"
  fi
}

# ── DevBot config (.devbot.global.jsonc) helpers ────────────────────────────────────────
#
# _devbot_is_true <key>
#   Returns 0 if the key's value is "true" in .devbot.global.jsonc, 1 otherwise.
#   Also returns 1 if .devbot.global.jsonc is missing.
#
# _devbot_get_bool <key>
#   Prints "true" or "false" for the key's value.
#
# _devbot_set_bool <key> <true|false>
#   Sets a boolean value in .devbot.global.jsonc. Key must already exist in the file.
#   Uses sed in-place (BSD and GNU compatible).

_devbot_is_true() {
  local key="$1"
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ ! -f "${config}" ]] && return 1
  grep -q "\"${key}\"[[:space:]]*:[[:space:]]*true" "${config}" 2>/dev/null && return 0
  return 1
}

_devbot_get_bool() {
  local key="$1"
  if _devbot_is_true "${key}"; then
    echo "true"
  else
    echo "false"
  fi
}

_devbot_set_bool() {
  local key="$1" value="$2"
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"

  if [[ ! -f "${config}" ]]; then
    _warn ".devbot.global.jsonc not found at ${config}"
    return 1
  fi

  if ! grep -q "\"${key}\"" "${config}" 2>/dev/null; then
    _warn "Key \"${key}\" not found in .devbot.global.jsonc"
    return 1
  fi

  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' "s/\"${key}\":[[:space:]]*true/\"${key}\": ${value}/; s/\"${key}\":[[:space:]]*false/\"${key}\": ${value}/" "${config}"
  else
    sed -i "s/\"${key}\":[[:space:]]*true/\"${key}\": ${value}/; s/\"${key}\":[[:space:]]*false/\"${key}\": ${value}/" "${config}"
  fi
}

# ── Project config (.devbot.project.jsonc) helpers ──────────────────────────────────────
#
# _devbot_get_project_dir [project_dir]
#   Prints the devbot state directory path relative to project root.
#   Defaults to ".agents" if not set in .devbot.project.jsonc or config is missing.

_devbot_get_project_dir() {
  local project_dir="${1:-$(pwd)}"
  local reader="${DEV_BOT_ROOT}/src/_shared/read_jsonc.py"
  local devbot_dir=""
  local default=".agents"

  # Check per-project config first
  if [[ -n "${project_dir}" && -f "${project_dir}/.devbot.project.jsonc" ]]; then
    devbot_dir=$(python3 "${reader}" "${project_dir}/.devbot.project.jsonc" "devbot_dir" 2>/dev/null || true)
  fi

  # Fall back to global config
  if [[ -z "${devbot_dir}" ]]; then
    local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
    if [[ -f "${global_config}" ]]; then
      devbot_dir=$(python3 "${reader}" "${global_config}" "devbot_dir" 2>/dev/null || true)
    fi
  fi

  # Default if still unset
  echo "${devbot_dir:-${default}}"
}

# ── Harness selection (config-driven) ─────────────────────────────────────────────
#
# _devbot_get_harness [project_dir]
#   Prints the harness name to use: "opencode" or "claudecode".
#   Per-project config (.devbot.project.jsonc) takes precedence over global.
#   Defaults to "opencode" if not set or config is missing.
#
# _devbot_resolve_harness_bin [project_dir]
#   Prints the binary path for the resolved harness. Exits with error if
#   the harness value is unknown or the binary is not found.

_devbot_get_harness() {
  local project_dir="${1:-}"
  local reader="${DEV_BOT_ROOT}/src/_shared/read_jsonc.py"
  local harness=""

  # Check per-project config first
  if [[ -n "${project_dir}" && -f "${project_dir}/.devbot.project.jsonc" ]]; then
    harness=$(python3 "${reader}" "${project_dir}/.devbot.project.jsonc" "harness" 2>/dev/null || true)
  fi

  # Fall back to global config
  if [[ -z "${harness}" ]]; then
    local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
    if [[ -f "${global_config}" ]]; then
      harness=$(python3 "${reader}" "${global_config}" "harness" 2>/dev/null || true)
    fi
  fi

  # Validate and default
  case "${harness}" in
    opencode|claudecode) echo "${harness}" ;;
    *) echo "opencode" ;;
  esac
}

_devbot_resolve_harness_bin() {
  local harness
  harness=$(_devbot_get_harness "$@")
  local bin=""

  case "${harness}" in
    opencode)
      bin="${HOME}/.opencode/bin/opencode"
      if [[ ! -f "${bin}" ]]; then
        _error "opencode binary not found at ${bin}"
        exit 1
      fi
      ;;
    claudecode)
      bin="$(command -v claude 2>/dev/null || true)"
      if [[ -z "${bin}" ]]; then
        _error "claude binary not found on PATH (install with: npm install -g @anthropic-ai/claude-code)"
        exit 1
      fi
      ;;
    *)
      _error "Unknown harness: ${harness}"
      exit 1
      ;;
  esac

  echo "${bin}"
}

# ── Disabled modules (config-driven) ─────────────────────────────────────────────
#
# _devbot_get_disabled_modules [project_dir]
#   Returns a JSON array of disabled module names (union of global + per-project).
#   When a module name appears in the merged list, all scripts that iterate
#   agentic modules (init, install, update, prereq checks) should skip it.
#   Handles missing fields gracefully (returns "[]").

_devbot_get_disabled_modules() {
  local project_dir="${1:-}"
  local reader="${DEV_BOT_ROOT}/src/_shared/read_jsonc.py"
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"

  # Read global
  local global_list="[]"
  if [[ -f "${global_config}" ]]; then
    global_list=$(python3 "${reader}" "${global_config}" "disabled_modules" 2>/dev/null || echo "[]")
    [[ -z "${global_list}" ]] && global_list="[]"
  fi

  # Read per-project
  local project_list="[]"
  if [[ -n "${project_dir}" && -f "${project_dir}/.devbot.project.jsonc" ]]; then
    project_list=$(python3 "${reader}" "${project_dir}/.devbot.project.jsonc" "disabled_modules" 2>/dev/null || echo "[]")
    [[ -z "${project_list}" ]] && project_list="[]"
  fi

  # Merge: sorted unique union
  python3 -c "
import json, sys
a = json.loads('${global_list}')
b = json.loads('${project_list}')
merged = sorted(set(a) | set(b))
print(json.dumps(merged))
" 2>/dev/null || echo "[]"
}

# ── opencode.jsonc plugin upsert ─────────────────────────────────────────────────
#
# Usage:  _upsert_opencode_plugin <opencode_jsonc_path> <plugin_entry>
# Behaviour:
#   - Adds <plugin_entry> (without quotes) to the "plugin" array
#   - If no "plugin" array exists, creates it before the closing "}"
#   - Idempotent: no-op if <plugin_entry> already in the array
#   - Handles empty and non-empty plugin arrays
#   - Preserves JSONC formatting and comments
#   - Silent: only manipulates the file, no output
#   - Returns 0 on success (or no-op), 1 on missing file

_upsert_opencode_plugin() {
  local jsonc_file="$1"
  local plugin_entry="$2"
  local tmp

  [[ -f "$jsonc_file" ]] || return 1
  grep -qF "\"${plugin_entry}\"" "$jsonc_file" && return 0

  tmp="$(mktemp)" || return 1

  # Single awk pass — two modes:
  #
  # Mode A ("plugin": [ block exists):
  #   Lines before the block are buffered in lines[] and flushed when the
  #   block is found. Lines inside the block are handled with immediate
  #   print (via buf[] for entries). Lines after the block are buffered
  #   in the reset lines[] and printed at END. This preserves line order.
  #
  # Mode B (no "plugin": [ block):
  #   All lines buffered in lines[]. At END, a new block is inserted before
  #   the last line (closing brace), with a trailing comma appended to the
  #   preceding field line (only when n > 2, i.e. there are actual fields).
  awk -v entry="$plugin_entry" '
    BEGIN { found = 0; n = 0 }
    /"plugin": \[/ {
      found = 1
      for (i = 1; i <= n; i++) print lines[i]   # flush pre-block lines
      n = 0
      in_block = 1
      print; next
    }
    in_block && /\]/ {
      if (buf_len > 0) {
        gsub(/,[[:space:]]*$/, "", buf[buf_len])
        buf[buf_len] = buf[buf_len] ","
      }
      for (i = 1; i <= buf_len; i++) print buf[i]
      print "    \"" entry "\""
      in_block = 0; buf_len = 0; print; next
    }
    in_block { buf[++buf_len] = $0; next }
    { lines[++n] = $0 }
    END {
      if (found) {
        for (i = 1; i <= n; i++) print lines[i]
      } else {
        for (i = 1; i < n; i++) {
          if (i == n - 1 && n > 2) gsub(/[[:space:]]*$/, ",", lines[i])
          print lines[i]
        }
        print "  \"plugin\": ["
        print "    \"" entry "\""
        print "  ]"
        print lines[n]
      }
    }
  ' "$jsonc_file" > "$tmp" && mv "$tmp" "$jsonc_file"
}

# ── Module prerequisites ─────────────────────────────────────────────────────────
#
# _run_module_prereqs
#   Loops through all agentic modules and runs their pre.sh (if present).
#   Relies on DEV_BOT_ROOT being set (by caller or by default above).
#   Exports MODULE_PREREQ_PASSED, MODULE_PREREQ_FAILED, MODULE_PREREQ_SKIPPED.
#
# Usage:
#   _run_module_prereqs

_run_module_prereqs() {
  _header_2 "Module Prerequisites"

  # ── Resolve disabled modules ──
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules)
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | python3 -c "
import json, sys
modules = json.loads(sys.stdin.read())
for m in modules:
    print(m)
" 2>/dev/null || true)

  local passed=0
  local skipped=0
  local failed=0

  local -a base_dirs=("${DEV_BOT_ROOT}/src/agentic")
  [[ -d "${DEV_BOT_ROOT}/storage/external-agentic-modules" ]] && base_dirs+=("${DEV_BOT_ROOT}/storage/external-agentic-modules")

  for base_dir in "${base_dirs[@]}"; do
    for module_dir in "${base_dir}/"*/; do
      local module_name
      module_name="$(basename "${module_dir}")"

      if echo "${disabled_modules}" | grep -Fxq "${module_name}" 2>/dev/null; then
        _skip "${module_name}: disabled per config — skipping"
        continue
      fi
      local pre_script="${module_dir}/pre.sh"

      if [[ ! -f "${pre_script}" ]]; then
        skipped=$((skipped + 1))
        continue
      fi

      if bash "${pre_script}"; then
        _ok "${module_name} prerequisites met."
        passed=$((passed + 1))
      else
        _warn "${module_name} prerequisites check failed."
        failed=$((failed + 1))
      fi
    done
  done

  if [[ ${passed} -eq 0 && ${failed} -eq 0 ]]; then
    _ok "No module pre.sh scripts found."
  fi

  export MODULE_PREREQ_PASSED="${passed}" MODULE_PREREQ_FAILED="${failed}" MODULE_PREREQ_SKIPPED="${skipped}"
}

# ── Generic module script runner ─────────────────────────────────────────────────
#
# _run_module_script <base_dir> <script_name> <label> <ok_label> [extra_args...]
#   Iterates all module directories under base_dir, skipping disabled modules,
#   and runs script_name in each directory that has it.
#   Extra args after ok_label are passed to each script invocation.
#
#   Exports: MODULE_SCRIPT_COUNT, MODULE_SCRIPT_FAILED, MODULE_SCRIPT_SKIPPED

_run_module_script() {
  local base_dir="$1"
  local script_name="$2"
  local label="$3"
  local ok_label="$4"
  shift 4  # remaining args passed to each script

  # ── Resolve disabled modules ──
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules)
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | python3 -c "
import json, sys
modules = json.loads(sys.stdin.read())
for m in modules:
    print(m)
" 2>/dev/null || true)

  local count=0
  local failed=0
  local skipped=0

  for module_dir in "${base_dir}/"*/; do
    local module_name
    module_name="$(basename "${module_dir}")"

    if echo "${disabled_modules}" | grep -Fxq "${module_name}" 2>/dev/null; then
      _skip "${module_name}: disabled per config — skipping"
      skipped=$((skipped + 1))
      continue
    fi

    local script="${module_dir}/${script_name}"

    if [[ ! -f "${script}" ]]; then
      skipped=$((skipped + 1))
      continue
    fi

    echo
    _header_3 "${label} ${module_name}..."
    local start=${SECONDS}
    if bash "${script}" "$@"; then
      _ok "${module_name} ${ok_label} ($(_fmt_duration $(( SECONDS - start ))))"
      count=$((count + 1))
    else
      _warn "${module_name} ${label,,} failed."
      failed=$((failed + 1))
    fi
    echo
  done

  if [[ ${count} -eq 0 && ${failed} -eq 0 ]]; then
    _ok "No ${script_name} scripts found in ${base_dir}"
  fi

  export MODULE_SCRIPT_COUNT="${count}"
  export MODULE_SCRIPT_FAILED="${failed}"
  export MODULE_SCRIPT_SKIPPED="${skipped}"
}

# ── Per-action wrappers ──────────────────────────────────────────────────────────

_install_modules()   { _run_module_script "$1" "install.sh"  "Installing"   "installed"; }
_update_modules()    { _run_module_script "$1" "update.sh"   "Updating"     "updated"; }
_init_modules()      { local d="$1"; shift; _run_module_script "$d" "init.sh" "Initializing" "initialized" "$@"; }
_uninstall_modules() { _run_module_script "$1" "uninstall.sh" "Uninstalling" "uninstalled"; }

# Collect scripts matching a name from modules in one or more base directories.
# Outputs one path per line. Useful for discovery before execution.
_collect_module_scripts() {
  local script_name="$1"
  shift  # remaining are base directories
  for base_dir in "$@"; do
    for module_dir in "${base_dir}/"*/; do
      local script="${module_dir}/${script_name}"
      if [[ -f "${script}" && -x "${script}" ]]; then
        echo "${script}"
      fi
    done
  done
}

# ── Service lifecycle runner (up.sh / down.sh) ──────────────────────────────────
#
# _run_service_scripts <script_name> [args...]
#   Runs <script_name> (e.g. up.sh, down.sh) in every module directory —
#   internal (src/tools, src/agentic, src/harnesses) and external
#   (storage/external-agentic-modules) — skipping disabled modules.
#   Remaining args are passed to each script.

_run_service_scripts() {
  local script_name="$1"
  shift

  local -a base_dirs=("${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses")
  [[ -d "${DEV_BOT_ROOT}/storage/external-agentic-modules" ]] && base_dirs+=("${DEV_BOT_ROOT}/storage/external-agentic-modules")

  local disabled_raw disabled_modules
  disabled_raw=$(_devbot_get_disabled_modules)
  disabled_modules=$(echo "${disabled_raw}" | python3 -c "
import json, sys
for m in json.loads(sys.stdin.read()):
    print(m)
" 2>/dev/null || true)

  local count=0
  local skipped=0
  local failed=0

  for base_dir in "${base_dirs[@]}"; do
    for module_dir in "${base_dir}/"*/; do
      local module_name
      module_name="$(basename "${module_dir}")"

      if echo "${disabled_modules}" | grep -Fxq "${module_name}" 2>/dev/null; then
        skipped=$((skipped + 1))
        continue
      fi

      local script="${module_dir}/${script_name}"
      if [[ ! -f "${script}" ]]; then
        skipped=$((skipped + 1))
        continue
      fi

      echo
      _header_3 "Running ${module_name} ${script_name}..."
      local start=${SECONDS}
      if bash "${script}" "$@"; then
        _ok "${module_name} ${script_name} done ($(_fmt_duration $(( SECONDS - start ))))"
        count=$((count + 1))
      else
        _skip "${module_name} ${script_name} had issues"
        failed=$((failed + 1))
      fi
      echo
    done
  done

  if [[ ${count} -eq 0 && ${failed} -eq 0 ]]; then
    _info "No ${script_name} scripts found"
  else
    echo
    _ok "${count} ${script_name} script(s) completed${skipped:+ (${skipped} skipped)}"
  fi
}

# ── Ollama model pulling helper ─────────────────────────────────────────────────
#
# Usage:  _pull_ollama_models <model> [model...]
# Pulls the specified Ollama models into the running dev-bot-ollama container.
# If the container is not running, starts it and stops it at the end.

_pull_ollama_models() {
  local models=("$@")
  if [[ ${#models[@]} -eq 0 ]]; then
    return 0
  fi

  local container_was_running=false
  local started_container=false

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'dev-bot-ollama'; then
    container_was_running=true
  else
    _info "Ollama container not running — starting it temporarily to pull models..."
    if docker compose -f "${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml" up -d ollama 2>/dev/null; then
      started_container=true
      # Wait for ollama to be ready
      local retries=10
      while ! docker exec dev-bot-ollama ollama list &>/dev/null; do
        if [[ $retries -le 0 ]]; then
          _warn "Ollama container did not become ready in time — skipping model pull"
          docker compose -f "${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml" stop ollama 2>/dev/null
          return 1
        fi
        sleep 2
        (( retries-- ))
      done
    else
      _warn "Failed to start Ollama container — skipping model pull"
      return 1
    fi
  fi

  local existing_models
  existing_models=$(docker exec dev-bot-ollama ollama list 2>/dev/null | awk 'NR>1 {print $1}')

  for model in "${models[@]}"; do
    if echo "${existing_models}" | grep -qx "${model}"; then
      _skip "Model ${model} already present — skipping."
    else
      _info "Pulling ollama model: ${model}..."
      if docker exec dev-bot-ollama ollama pull "${model}"; then
        _ok "Model ${model} pulled."
      else
        _skip "Model ${model} pull failed."
      fi
    fi
  done

  if [[ "$started_container" == true && "$container_was_running" == false ]]; then
    _info "Stopping temporary Ollama container..."
    docker compose -f "${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml" stop ollama 2>/dev/null
  fi
}

# ── Shared helpers ─────────────────────────────────────────────────────────────

_upsert_section_impl() {
  local file="$1"
  local marker_start="$2"
  local marker_end="$3"
  shift 3

  local tmpfile
  tmpfile="$(mktemp)"
  local found_section=0
  local in_section=0

  while IFS= read -r line; do
    if [[ "${line}" == "${marker_start}" ]]; then
      found_section=1
      in_section=1
      echo "${line}" >> "${tmpfile}"
      for content_line in "$@"; do
        echo "${content_line}" >> "${tmpfile}"
      done
    elif [[ "${line}" == "${marker_end}" ]]; then
      in_section=0
      echo "${line}" >> "${tmpfile}"
    elif [[ ${in_section} -eq 1 ]]; then
      :
    else
      echo "${line}" >> "${tmpfile}"
    fi
  done < "${file}"

  if [[ ${found_section} -eq 0 ]]; then
    {
      echo ""
      echo "${marker_start}"
      for line in "$@"; do echo "${line}"; done
      echo "${marker_end}"
    } >> "${tmpfile}"
  fi

  mv "${tmpfile}" "${file}"
}

# ── gitignore/exclude upsert ───────────────────────────────────────────────────
#
# Usage:  _upsert_gitignore_section <file> <start_marker> <end_marker> <lines...>
# Behaviour:
#   - File doesn't exist → create with markers + content
#   - Section exists     → replace content between markers in-place
#   - No section         → append markers + content at end

_upsert_gitignore_section() {
  local file="$1"
  local marker_start="$2"
  local marker_end="$3"
  shift 3

  mkdir -p "$(dirname "$file")"

  if [[ ! -f "${file}" ]]; then
    {
      echo "${marker_start}"
      for line in "$@"; do echo "${line}"; done
      echo "${marker_end}"
    } > "${file}"
    return 0
  fi

  _upsert_section_impl "${file}" "${marker_start}" "${marker_end}" "$@"
}

# ── Git hook upsert ────────────────────────────────────────────────────────────
#
# Usage:  _upsert_hook_section <hook_file> <start_marker> <end_marker> <lines...>
# Behaviour:
#   - File doesn't exist → create with shebang + markers + content
#   - Section exists     → replace content between markers in-place
#   - No section         → append at end
#   - Always ensures the hook file is executable.

_upsert_hook_section() {
  local hook_file="$1"
  local marker_start="$2"
  local marker_end="$3"
  shift 3

  if [[ ! -f "${hook_file}" ]]; then
    {
      printf '#!/usr/bin/env bash\n\n'
      echo "${marker_start}"
      for line in "$@"; do echo "${line}"; done
      echo "${marker_end}"
    } > "${hook_file}"
    chmod +x "${hook_file}"
    return 0
  fi

  _upsert_section_impl "${hook_file}" "${marker_start}" "${marker_end}" "$@"
  chmod +x "${hook_file}"
}

_check_python3() {
  if ! command -v python3 &>/dev/null; then
    echo "  Error: python3 is required but not installed." >&2
    echo "  Install via your system package manager (apt, dnf, brew)." >&2
    exit 1
  fi
  _ok "python3 found"
}
