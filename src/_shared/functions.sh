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
_notice() { echo -e "  ${TEXT_BOLD}${TEXT_YELLOW}⚠  NOTICE:  $* ${TEXT_CLEAR}"; }
_warn() { echo -e "  ${TEXT_BOLD}${TEXT_ORANGE}⚠⚠  WARN:  $* ${TEXT_CLEAR}"; }
_error() { echo -e "  ${TEXT_BOLD}${TEXT_RED}❌  ERROR:  $* ${TEXT_CLEAR}" >&2; }
_fatal() { echo -e "  ${TEXT_BOLD}${TEXT_RED}🛑  FATAL:  $* ${TEXT_CLEAR}" >&2; }
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

# ── File logging ────────────────────────────────────────────────────────────────
#
# _log_file <log_file> <message...>
#   Appends a [YYYY-MM-DD HH:MM:SS]-prefixed line to <log_file>, creating the
#   parent directory if needed. Use for any dev-bot log destined for a file
#   (e.g. .agents/logs/*.log) so every line carries a timestamp. Plain text —
#   no color codes; files are not terminals. Silent on failure (never breaks
#   the caller).
_log_file() {
  local log_file="$1"
  shift
  [[ -n "${log_file}" ]] || return 0
  mkdir -p "$(dirname "${log_file}")" 2>/dev/null || true
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "${log_file}" 2>/dev/null || true
}

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
# _devbot_get_config <key> [project_dir]
#   Canonical config getter. Prints the effective value of a scalar config
#   key with project-first, global-fallback precedence: an explicit value in
#   .devbot.project.jsonc wins (even `false`); otherwise the value from
#   .devbot.global.jsonc; empty when unset in both. project_dir defaults to pwd.
#
# _devbot_get_project_dir [project_dir]
#   Prints the devbot state directory path relative to project root.
#   Defaults to ".agents" if not set in config or config is missing.

_devbot_get_config() {
  local key="${1:?Usage: _devbot_get_config <key> [project_dir]}"
  local project_dir="${2:-$(pwd)}"
  local reader="${DEV_BOT_ROOT}/src/_shared/read_jsonc.py"
  local value=""

  # Check per-project config first
  if [[ -n "${project_dir}" && -f "${project_dir}/.devbot.project.jsonc" ]]; then
    value=$(python3 "${reader}" "${project_dir}/.devbot.project.jsonc" "${key}" 2>/dev/null || true)
  fi

  # Fall back to global config
  if [[ -z "${value}" ]]; then
    local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
    if [[ -f "${global_config}" ]]; then
      value=$(python3 "${reader}" "${global_config}" "${key}" 2>/dev/null || true)
    fi
  fi

  echo "${value}"
}

_devbot_get_project_dir() {
  local project_dir="${1:-$(pwd)}"
  local devbot_dir
  devbot_dir="$(_devbot_get_config "devbot_dir" "${project_dir}")"
  echo "${devbot_dir:-.agents}"
}

# ── Harness selection (config-driven) ─────────────────────────────────────────────
#
# _devbot_get_harness [project_dir]
#   Prints the harness name to use: "opencode" or "claudecode".
#   Per-project config (.devbot.project.jsonc) takes precedence over global.
#   Defaults to "opencode" if not set or config is missing.

_devbot_get_harness() {
  local project_dir="${1:-$(pwd)}"
  local harness
  harness="$(_devbot_get_config "harness" "${project_dir}")"

  # Validate and default
  case "${harness}" in
    opencode|claudecode) echo "${harness}" ;;
    *) echo "opencode" ;;
  esac
}

# ── Post-session error log check ───────────────────────────────────────────────

# _devbot_rotate_session_logs <project_dir>
#   Rotates the previous session's .agents/logs/*.log files out of the way:
#   each becomes .agents/logs/rotated/<YYYYMMDD>-<name>-<NNN>.log (date prefix,
#   zero-padded 3-digit sequence to avoid collisions). Old logs are preserved;
#   writers start fresh files, so the post-exit check only sees this session.
_devbot_rotate_session_logs() {
  local project_dir="${1:-$(pwd)}"
  local logs_dir="${project_dir}/.agents/logs"
  [[ -d "${logs_dir}" ]] || return 0

  local rotated_dir="${logs_dir}/rotated"
  mkdir -p "${rotated_dir}" 2>/dev/null || return 0

  local date_stamp
  date_stamp="$(date +%Y%m%d)"

  local file base nnn target
  for file in "${logs_dir}"/*.log; do
    [[ -f "${file}" ]] || continue
    base="$(basename "${file}")"
    nnn=1
    while [[ ${nnn} -le 999 ]]; do
      target="${rotated_dir}/${date_stamp}-${base%.log}-$(printf '%03d' "${nnn}").log"
      [[ ! -e "${target}" ]] && break
      nnn=$((nnn + 1))
    done
    mv -f "${file}" "${target}" 2>/dev/null || true
  done

  return 0
}

# _devbot_check_session_logs <project_dir>
#   Scans the current .agents/logs/*.log files (fresh for this session, thanks
#   to _devbot_rotate_session_logs) for error-level lines and prints an alert:
#   per file, the total match count plus one representative line per distinct
#   error type (lines normalized by stripping leading [token] prefixes and
#   collapsing whitespace) with a per-type count. Silent when nothing matches.
#   Rotated logs under .agents/logs/rotated/ are never scanned.
#   Called by the harness start.sh scripts after the harness exits.
#   Report-style logs are skipped: their normal content legitimately contains
#   error-like words (e.g. lint-k8s.log holds kube-linter's findings summary
#   "Error: found N lint errors" and format-*.log holds prettier's
#   "Error formatting … failed" reports of invalid input — hook REPORTS, not
#   session errors; audit-25 FAIL-1).
_devbot_check_session_logs() {
  local project_dir="${1:-}"
  [[ -n "${project_dir}" && -d "${project_dir}" ]] || return 0

  local logs_dir="${project_dir}/.agents/logs"
  [[ -d "${logs_dir}" ]] || return 0

  # Word-bounded error verbs + bare "constraint" (catches SQLITE_CONSTRAINT /
  # SQLITE_CONSTRAINT_PRIMARYKEY tokens even without the word "failed" — the
  # _\b_ boundaries would miss the compound token).
  local pattern='(\b(error|fatal|traceback|exception|failed)\b|constraint)'
  local report_logs="lint-k8s.log format-md.log format-json.log format-yml.log"
  local file count found=0
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    case " ${report_logs} " in
      *" $(basename "${file}") "*) continue ;;
    esac
    count="$(grep -ciE "${pattern}" "${file}" 2>/dev/null || true)"
    if [[ "${count}" =~ ^[0-9]+$ ]] && (( count > 0 )); then
      found=$((found + 1))
      if [[ ${found} -eq 1 ]]; then
        _warn "Session finished with error log entries in .agents/logs/:"
      fi

      # Distinct error types: normalized matching lines, most frequent first.
      local types type_count
      types="$(grep -iE "${pattern}" "${file}" 2>/dev/null \
        | sed -E 's/^\[[^]]*\][[:space:]]*//g; s/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//' \
        | sort | uniq -c | sort -rn || true)"
      type_count="$(printf '%s\n' "${types}" | grep -c . 2>/dev/null || true)"
      [[ "${type_count}" =~ ^[0-9]+$ ]] || type_count=0
      echo "  - ${file}: ${count} error line(s), ${type_count} type(s)"
      printf '%s\n' "${types}" | while read -r n text; do
        [[ -n "${n}" ]] || continue
        echo "      ${text}: ${n}x"
      done
    fi
  done < <(find "${logs_dir}" -maxdepth 1 -name "*.log" 2>/dev/null | sort)

  return 0
}

# ── Memory delete→prune self-heal (pre-harness launch) ───────────────────────────

# _devbot_prune_memories_detached <project_dir>
#   Fires the memory delete→prune self-heal (qmd cleanup && qmd update, no
#   embed) detached BEFORE the harness starts. Moved out of the session.created
#   hook (memory/hooks.json) into the harness start.sh scripts (audit-36):
#     - it runs per launch, not only on the first session.created of a process
#       (audit-34 NOTE-8), and
#     - qmd gets a head start ahead of the MCP-server fleet boot at session
#       start, whose concurrent-launch contention exceeded the client's 30s
#       connect budget for the two heaviest servers (audit-35 FAIL).
#   The prune tool (reindex-memories.mcp.sh prune) backgrounds + disowns qmd
#   itself; this helper additionally detaches the invocation from start.sh and
#   writes a marker line so audits can cross-check `.agents/logs/qmd-index.log`.
#   Fail-open and silent: no qmd, no memory vault, or a disabled memory module
#   means "no prune needed here" — it never blocks or fails the harness launch.
_devbot_prune_memories_detached() {
  local project_dir="${1:-$(pwd)}"
  [[ -n "${project_dir}" && -d "${project_dir}" ]] || return 0

  # Disabled memory module → no prune (and no qmd-index.log to write).
  if _devbot_get_disabled_modules "${project_dir}" | grep -q '"memory"'; then
    return 0
  fi

  # No memory vault → nothing to prune.
  local devbot_dir vault
  devbot_dir="$(_devbot_get_project_dir "${project_dir}")"
  vault="${project_dir}/${devbot_dir}/memory"
  [[ -d "${vault}" ]] || return 0

  command -v qmd >/dev/null 2>&1 || return 0

  # Resolve the tool next to this file (functions.sh → src/_shared), not via
  # DEV_BOT_ROOT, which may be overridden to a sandbox root in tests.
  local shared_dir tool
  shared_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  tool="${shared_dir}/../agentic/memory/tools/reindex-memories/reindex-memories.mcp.sh"
  [[ -f "${tool}" ]] || return 0

  local logs_dir="${project_dir}/.agents/logs"
  mkdir -p "${logs_dir}" 2>/dev/null || return 0

  # Marker line (synchronous) so a session can prove the prune fired; the qmd
  # work itself runs detached inside the tool.
  printf '[reindex-memories-prune-start] devbot start.sh: detached memory prune (qmd cleanup && qmd update) launched before harness\n' \
    >> "${logs_dir}/qmd-index.log" 2>/dev/null || true

  ( cd "${project_dir}" && bash "${tool}" prune ) >> "${logs_dir}/qmd-index.log" 2>&1 &
  disown 2>/dev/null || true

  return 0
}

# ── Disabled modules (config-driven) ─────────────────────────────────────────────
#
# _devbot_get_disabled_modules [project_dir]
#   Returns a JSON array of disabled module names. The effective state is
#   computed from the "modules" maps (module → bool): the per-project
#   value overrides the global value; a module absent from both is enabled.
#   Handles missing fields gracefully (returns "[]").

_devbot_get_disabled_modules() {
  local project_dir="${1:-}"
  # The reader always lives beside this file — not under DEV_BOT_ROOT, which
  # may be overridden to a sandbox root in tests.
  local shared_dir
  shared_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local reader="${shared_dir}/read_jsonc.py"
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"

  # Read global modules map
  local global_states="{}"
  if [[ -f "${global_config}" ]]; then
    global_states=$(python3 "${reader}" "${global_config}" "modules" 2>/dev/null || true)
    [[ -z "${global_states}" || "${global_states}" == "null" ]] && global_states="{}"
  fi

  # Read per-project modules map
  local project_states="{}"
  if [[ -n "${project_dir}" && -f "${project_dir}/.devbot.project.jsonc" ]]; then
    project_states=$(python3 "${reader}" "${project_dir}/.devbot.project.jsonc" "modules" 2>/dev/null || true)
    [[ -z "${project_states}" || "${project_states}" == "null" ]] && project_states="{}"
  fi

  # Merge: project overrides global. A module is disabled when its effective
  # value is false (project value if present, else global value).
  GLOBAL_STATES="${global_states}" PROJECT_STATES="${project_states}" python3 -c '
import json, os
global_states = json.loads(os.environ["GLOBAL_STATES"])
project_states = json.loads(os.environ["PROJECT_STATES"])
disabled = set()
for m, v in global_states.items():
    if project_states.get(m, v) is False:
        disabled.add(m)
for m, v in project_states.items():
    if m not in global_states and v is False:
        disabled.add(m)
print(json.dumps(sorted(disabled)))
' 2>/dev/null || echo "[]"
}

# ── External modules (config-driven) ─────────────────────────────────────────────
#
# _devbot_get_external_modules
#   Prints the names of configured external modules (keys of `modules` in
#   .devbot.global.jsonc), one per line. The config is the single source of
#   truth for which external modules exist — never the vendor/ or
#   storage/external-agentic-modules/ filesystem directories.

_devbot_get_external_modules() {
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ -f "${global_config}" ]] || return 0
  python3 -c "
import json, sys
sys.path.insert(0, '${DEV_BOT_ROOT}/src/_shared')
from read_jsonc import load_jsonc
try:
    data = load_jsonc('${global_config}')
    modules = data.get('external_modules')
    if isinstance(modules, dict):
        for name in modules:
            print(name)
except Exception:
    pass
" 2>/dev/null || true
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

  tmp="$(mktemp "${TMPDIR:-/tmp}/devbot.XXXXXX")" || return 1

  # Single awk pass — three modes, idempotent (no-op when the entry is
  # already inside the "plugin" array):
  #
  # Mode A (single-line array: "plugin": [...] on one line):
  #   Appends the entry inline, or no-ops if already present. This is the
  #   critical case — the dist ships "plugin": [], and the old two-mode awk
  #   treated every line after the "[" as array body, corrupting the file.
  #
  # Mode B (multi-line array: "plugin": [ ... ] across lines):
  #   Buffers the array body, inserts the entry before the closing bracket.
  #
  # Mode C (no "plugin" key): inserts a new block before the closing brace.
  awk -v entry="$plugin_entry" '
    BEGIN { found = 0; n = 0; buf_len = 0; already = 0 }
    /"plugin": \[[^]]*\]/ {
      found = 1
      for (i = 1; i <= n; i++) print lines[i]
      n = 0
      if (index($0, "\"" entry "\"")) { print; next }
      if ($0 ~ /\[[[:space:]]*\]/) sub(/\[[[:space:]]*\]/, "[\"" entry "\"]")
      else sub(/\]/, ", \"" entry "\"]")
      print; next
    }
    /"plugin": \[/ {
      found = 1
      for (i = 1; i <= n; i++) print lines[i]
      n = 0
      in_block = 1
      print; next
    }
    in_block && /\]/ {
      if (!already) {
        if (buf_len > 0) {
          gsub(/,[[:space:]]*$/, "", buf[buf_len])
          buf[buf_len] = buf[buf_len] ","
        }
        for (i = 1; i <= buf_len; i++) print buf[i]
        print "    \"" entry "\""
      } else {
        for (i = 1; i <= buf_len; i++) print buf[i]
      }
      in_block = 0; buf_len = 0; print; next
    }
    in_block {
      if (index($0, "\"" entry "\"")) already = 1
      buf[++buf_len] = $0; next
    }
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
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

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

  # ── Resolve disabled modules (global + per-project union) ──
  # "$1" is the first extra arg — the project dir for _init_modules.
  local disabled_raw
  disabled_raw=$(_devbot_get_disabled_modules "${1:-}")
  local disabled_modules
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

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
      _warn "${module_name} $(printf '%s' "${label}" | tr '[:upper:]' '[:lower:]') failed."
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
  disabled_raw=$(_devbot_get_disabled_modules "${1:-}")
  disabled_modules=$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)

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

# _has_gpu: returns 0 if any usable GPU is available on the host.
#   NVIDIA: nvidia-smi must exist and succeed.
#   AMD:    rocm-smi must exist and succeed, or lspci shows AMD GPU.
#   Intel:  /dev/dri/renderD* exists and a compatible GPU is detected.
#   macOS:  Apple Silicon (arm64) has built-in GPU.
_has_gpu() {
  case "$(uname -s)" in
    Darwin)
      [[ "$(uname -m)" == "arm64" ]]
      return $?
      ;;
    Linux)
      # NVIDIA
      if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        return 0
      fi
      # AMD ROCm
      if command -v rocm-smi >/dev/null 2>&1 && rocm-smi >/dev/null 2>&1; then
        return 0
      fi
      # Intel via /dev/dri (render nodes = GPU available)
      if ls /dev/dri/renderD* >/dev/null 2>&1; then
        return 0
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# _gpu_vendor: prints the GPU vendor name for the primary GPU.
_gpu_vendor() {
  case "$(uname -s)" in
    Darwin)
      echo "apple-silicon"
      return 0
      ;;
    Linux)
      if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        echo "nvidia"
        return 0
      fi
      if command -v rocm-smi >/dev/null 2>&1 && rocm-smi >/dev/null 2>&1; then
        echo "amd"
        return 0
      fi
      if ls /dev/dri/renderD* >/dev/null 2>&1; then
        # Check if it's Intel or AMD integrated via lspci
        if command -v lspci >/dev/null 2>&1; then
          if lspci 2>/dev/null | grep -qi "VGA.*Intel"; then
            echo "intel"
            return 0
          fi
          if lspci 2>/dev/null | grep -qi "VGA.*AMD\|VGA.*Advanced Micro Devices"; then
            echo "amd"  # AMD integrated (not ROCm)
            return 0
          fi
        fi
        echo "intel"  # fallback — most common with /dev/dri/render
        return 0
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# _has_docker_gpu: returns 0 if Docker GPU passthrough is available.
#   Linux (NVIDIA): nvidia-smi + NVIDIA Container Toolkit.
#   Linux (AMD):    rocm-smi + /dev/kfd accessible.
#   Linux (Intel):  /dev/dri/renderD* accessible.
#   macOS:          always 1 — Docker Desktop does not support GPU passthrough.
_has_docker_gpu() {
  [[ "$(uname -s)" != "Linux" ]] && return 1
  _has_gpu || return 1

  local vendor
  vendor="$(_gpu_vendor)"
  case "${vendor}" in
    nvidia)
      docker info 2>/dev/null | grep -qi nvidia \
        || [[ -x "/usr/bin/nvidia-container-toolkit" ]]
      return $?
      ;;
    amd)
      # AMD ROCm requires /dev/kfd for Docker passthrough
      ls /dev/kfd >/dev/null 2>&1
      return $?
      ;;
    intel)
      # Intel GPU in Docker requires /dev/dri and the intel-gpu-plugin
      ls /dev/dri/renderD* >/dev/null 2>&1
      return $?
      ;;
    *)
      return 1
      ;;
  esac
}

# _qmd_gpu_value
#   Prints a QMD_LLAMA_GPU value qmd 2.8.3 actually accepts: metal|cuda|vulkan
#   when the HOST has a usable GPU (audit-25 F5: driven by _has_gpu, not the
#   gpu_enabled config flag — qmd runs as a plain local process, so Docker
#   passthrough availability is irrelevant to it), else "false". qmd REJECTS
#   the plain boolean "true" ("invalid QMD_LLAMA_GPU=\"true\", using auto GPU
#   selection") — this is what the __GPU_ENABLED__ placeholder substitutes.
_qmd_gpu_value() {
  if ! _has_gpu; then
    echo "false"
    return 0
  fi
  case "$(uname -s)" in
    Darwin)
      echo "metal"
      ;;
    Linux)
      if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        echo "cuda"
      elif command -v rocm-smi >/dev/null 2>&1 && rocm-smi >/dev/null 2>&1; then
        echo "vulkan"
      else
        # Docker GPU passthrough (--gpus all / compose gpu reservation) —
        # nvidia-smi is visible inside the container; assume NVIDIA.
        echo "cuda"
      fi
      ;;
    *)
      echo "false"
      ;;
  esac
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

  # No docker daemon (e.g. inside a container) — the host's ollama serves the
  # API; nothing to pull here. Skip cleanly instead of failing compose.
  if ! docker info >/dev/null 2>&1; then
    _skip "no docker daemon (inside a container?) — ollama model pull skipped; the host serves the ollama API instead"
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
      while ! docker exec dev-bot-ollama ollama list >/dev/null 2>&1; do
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

# _ensure_ollama_models_detached <model...>
#   Ensures the given models exist on the configured ollama API WITHOUT
#   blocking the caller. Skips models already present; launches the missing
#   pulls as independent (detached) processes so install/update never waits on
#   a model download. With a docker daemon it reuses _pull_ollama_models (the
#   dev-bot ollama container); without one (e.g. inside a dev container where
#   the host serves the API) it talks to the plain ollama API directly.
_ensure_ollama_models_detached() {
  local api="${OLLAMA_API_URL:-}"
  if [[ -z "${api}" && -f "${DEV_BOT_ROOT}/.devbot.global.jsonc" ]]; then
    api="$(python3 "${DEV_BOT_ROOT}/src/_shared/read_jsonc.py" "${DEV_BOT_ROOT}/.devbot.global.jsonc" "ollama_local_api" 2>/dev/null || true)"
  fi
  api="${api:-http://localhost:18434}"

  local model missing=0
  for model in "$@"; do
    if curl -fsS --max-time 5 "${api}/api/tags" 2>/dev/null | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"${model}\""; then
      _skip "ollama model ${model} already present"
    else
      _warn "ollama model ${model} missing — will pull in the background"
      missing=1
    fi
  done
  [[ ${missing} -eq 0 ]] && return 0

  _info "Pulling missing ollama models as independent process(es)..."
  # We reached here because /api/tags answered WITHOUT the model(s) — the API
  # is up, so pull through it directly (works for a container or a native
  # ollama; no docker needed). The docker path is only for an unreachable API.
  if curl -fsS --max-time 5 "${api}/api/tags" >/dev/null 2>&1; then
    local m
    for m in "$@"; do
      ( nohup curl -fsS -X POST "${api}/api/pull" -H "Content-Type: application/json" -d "{\"name\": \"${m}\"}" >/dev/null 2>&1 & )
    done
  elif docker info >/dev/null 2>&1; then
    # API down but docker available — start the ollama container and pull there.
    # NOTE: nohup cannot run a shell function, so wrap it in a bash -c.
    ( nohup bash -c 'source "${DEV_BOT_ROOT}/src/_shared/functions.sh"; _pull_ollama_models "$@"' _ "$@" >/dev/null 2>&1 & )
  else
    _warn "ollama API unreachable and no docker daemon — cannot pull models in the background"
    return 1
  fi
  return 0
}

# ── Shared helpers ─────────────────────────────────────────────────────────────

_upsert_section_impl() {
  local file="$1"
  local marker_start="$2"
  local marker_end="$3"
  shift 3

  local tmpfile
  tmpfile="$(mktemp "${TMPDIR:-/tmp}/devbot.XXXXXX")"
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
  if ! command -v python3 >/dev/null 2>&1; then
    # audit-25: macOS ships no /usr/bin/python3 on fresh installs is rare, but
    # Darwin users routinely have only 3.9.6. Try a Homebrew install before
    # giving up so `devbot install/update` self-heals instead of failing.
    if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
      _info "python3 not found — installing via Homebrew..."
      brew install python >/dev/null 2>&1 || true
    fi
    if ! command -v python3 >/dev/null 2>&1; then
      _fatal "python3 is required but not installed."
      echo "  Install via your system package manager (apt, dnf, brew)." >&2
      exit 1
    fi
  fi

  # audit-25 F1/F3: PEP 604 union annotations (str | None) require Python >=
  # 3.10 at import time. The tools now carry 'from __future__ import
  # annotations' (3.7+ compatible), but 3.10 remains the supported floor —
  # warn loudly when it is not met so future regressions surface early.
  local ver major minor
  ver="$(python3 --version 2>&1 | sed -n 's/^Python \([0-9]*\.[0-9]*\).*/\1/p')"
  if [[ -z "${ver}" ]]; then
    _warn "Could not determine python3 version (got '$(python3 --version 2>&1)') — assuming >= 3.10."
    _ok "python3 found"
    return 0
  fi
  major="${ver%%.*}"
  minor="${ver##*.}"

  if [[ "${major}" -ge 3 && "${minor}" -ge 10 ]]; then
    _ok "python3 found (${ver})"
    return 0
  fi

  if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    _info "python3 ${ver} is older than 3.10 — upgrading via Homebrew..."
    brew upgrade python >/dev/null 2>&1 || brew install python >/dev/null 2>&1 || true
    ver="$(python3 --version 2>&1 | sed -n 's/^Python \([0-9]*\.[0-9]*\).*/\1/p')"
    major="${ver%%.*}"
    minor="${ver##*.}"
    if [[ "${major}" -ge 3 && "${minor}" -ge 10 ]]; then
      _ok "python3 found (${ver})"
      return 0
    fi
  fi

  _warn "python3 is ${ver} (< 3.10) — devbot's Python tools expect Python >= 3.10."
  _warn "Install Python 3.10+ (e.g. 'brew install python' on macOS) for full compatibility."
  _ok "python3 found (${ver})"
}

# _check_flock
#   Ensures flock(1) is available. flock ships with Linux's util-linux and is
#   absent on stock macOS. On Darwin, installs util-linux via Homebrew and
#   adds its keg-only bin dir to PATH (brew does NOT symlink keg-only
#   binaries into /opt/homebrew/bin — the hook scripts that exec flock need
#   the explicit PATH entry). Warns — never fails — on any other platform:
#   the hooks themselves carry a python fcntl fallback (audit-25 F2).
_check_flock() {
  if command -v flock >/dev/null 2>&1; then
    _ok "flock found"
    return 0
  fi

  if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    _info "flock not found — installing util-linux via Homebrew..."
    if brew install util-linux >/dev/null 2>&1; then
      # util-linux is keg-only: the binary lands in the versioned opt dir,
      # not on PATH. Prepend it so hook scripts resolve flock. Homebrew
      # exports HOMEBREW_PREFIX (/opt/homebrew on Apple Silicon, /usr/local
      # on Intel) — fall back to probing both when unset.
      local util_bin=""
      local prefix="${HOMEBREW_PREFIX:-}"
      if [[ -n "${prefix}" ]]; then
        [[ -x "${prefix}/opt/util-linux/bin/flock" ]] && util_bin="${prefix}/opt/util-linux/bin"
      else
        for candidate in /opt/homebrew/opt/util-linux/bin /usr/local/opt/util-linux/bin; do
          if [[ -x "${candidate}/flock" ]]; then
            util_bin="${candidate}"
            break
          fi
        done
      fi
      if [[ -n "${util_bin}" ]]; then
        export PATH="${util_bin}:${PATH}"
        _ok "flock found (${util_bin}/flock — keg-only, added to PATH)"
      else
        _warn "util-linux installed but flock not found in expected keg dirs"
      fi
      return 0
    else
      _warn "brew install util-linux failed — hooks will use the python fcntl fallback"
      return 0
    fi
  fi

  _warn "flock not available — hooks will use the python fcntl fallback"
}

# ── Harness delegation to devbot_dir/ ──────────────────────────────────────────
# Migrates existing harness-specific agents/commands/skills/tools content into
# the devbot state dir (from config), then creates a symlink from the harness
# dir to the devbot dir's subdirectories.
#
# Usage: _harness_delegate_to_agents <harness_dir> <project_dir>

_harness_delegate_type() {
  local harness_dir="$1"
  local project_dir="$2"
  local type="$3"
  local migrate_only="${4:-false}"

  local devbot_dir
  devbot_dir="$(_devbot_get_project_dir "${project_dir}")"

  local harness_path="${harness_dir}/${type}"
  local agents_path="${project_dir}/${devbot_dir}/${type}"
  # Already delegated — skip
  if [[ -L "${harness_path}" ]]; then
    local current
    current="$(readlink "${harness_path}")"
    if [[ "${current}" == "../${devbot_dir}/${type}" ]]; then
      _skip "${type}/ already delegated to ${devbot_dir}/"
      return 0
    fi
    # A user-created symlink pointing elsewhere (e.g. .opencode/skills →
    # ~/my-skills): preserve the pointer under devbot_dir instead of
    # destroying it, then remove the harness link so delegation proceeds.
    local target_abs="${current}"
    if [[ "${target_abs}" != /* ]]; then
      target_abs="$(cd "$(dirname "${harness_path}")" 2>/dev/null \
        && cd "${current}" 2>/dev/null && pwd 2>/dev/null || echo "${current}")"
    fi
    local link_name
    link_name="$(basename "${target_abs}")"
    mkdir -p "${agents_path}"
    if [[ ! -e "${agents_path}/${link_name}" ]]; then
      ln -sf "${target_abs}" "${agents_path}/${link_name}"
      _warn "${type}/ is a symlink to '${target_abs}' — preserved as ${devbot_dir}/${type}/${link_name}"
    else
      _warn "${type}/ is a symlink to '${target_abs}' and ${devbot_dir}/${type}/${link_name} exists — leaving the harness symlink in place"
      return 0
    fi
    rm -f "${harness_path}"
  fi

  # Directory exists — migrate content then remove
  local migrated_any=false
  if [[ -d "${harness_path}" ]]; then
    mkdir -p "${agents_path}"
    migrated_any=true

    while IFS= read -r -d '' item; do
      local name
      name="$(basename "${item}")"
      [[ "${name}" == ".gitkeep" ]] && continue

      local dest="${agents_path}/${name}"

      # Collision policy: an existing dest keeps its name (devbot artifact
      # wins); the user's artifact is preserved as <name>.bkp so nothing is
      # clobbered or lost. A symlink pointing at the same target is the same
      # artifact already migrated — skip silently. If the .bkp slot is taken,
      # re-suffix (.bkp.bkp) rather than nesting or overwriting.
      if [[ -L "${item}" && -L "${dest}" ]] \
        && [[ "$(readlink "${dest}")" == "$(readlink "${item}")" ]]; then
        continue
      fi
      if [[ -e "${dest}" || -L "${dest}" ]]; then
        local candidate="${name}"
        while [[ -e "${agents_path}/${candidate}" || -L "${agents_path}/${candidate}" ]]; do
          candidate="${candidate}.bkp"
        done
        _warn "${type}/${name} exists in ${devbot_dir}/ — storing user's as ${candidate}"
        dest="${agents_path}/${candidate}"
      fi

      mkdir -p "$(dirname "${dest}")"
      if [[ -L "${item}" ]]; then
        ln -sf "$(readlink "${item}")" "${dest}"
        _ok "migrated symlink to ${devbot_dir}/${type}/$(basename "${dest}")"
      elif [[ -f "${item}" ]]; then
        cp "${item}" "${dest}"
        _ok "migrated file to ${devbot_dir}/${type}/$(basename "${dest}")"
      elif [[ -d "${item}" ]]; then
        cp -r "${item}" "${dest}"
        _ok "migrated directory to ${devbot_dir}/${type}/$(basename "${dest}")"
      fi
    done < <(find "${harness_path}" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

    rm -rf "${harness_path}"
  elif [[ -e "${harness_path}" ]]; then
    rm -rf "${harness_path}"
  fi

  # Migrate-only mode: content is moved into devbot_dir but no delegation
  # symlink is created. Used by opencode for skills when the devbot dir is
  # .agents — opencode auto-discovers .agents/skills directly, so a
  # .opencode/skills → .agents/skills symlink would double-register them.
  if [[ "${migrate_only}" == "true" ]]; then
    if [[ "${migrated_any}" == "true" ]]; then
      _ok "${type}/ content migrated to ${devbot_dir}/${type}/ (no delegation symlink)"
    else
      _skip "${type}/ not present — nothing to migrate"
    fi
    return 0
  fi

  # Create delegation symlink
  mkdir -p "$(dirname "${harness_path}")"
  ln -sf "../${devbot_dir}/${type}" "${harness_path}"
  _ok "${type}/ delegated to ${devbot_dir}/${type}/"
}

_harness_delegate_to_agents() {
  local harness_dir="$1"
  local project_dir="$2"
  # Space-separated types to delegate. opencode skips "skills" when the devbot
  # dir is the default .agents (opencode auto-discovers .agents/skills, so a
  # .opencode/skills → .agents/skills symlink causes duplicate-skill warnings).
  local types="${3:-agents commands skills tools}"

  for type in ${types}; do
    _harness_delegate_type "${harness_dir}" "${project_dir}" "${type}"
  done
}
