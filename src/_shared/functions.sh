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

# ── Cross-process bounded lock ─────────────────────────────────────────────────
#
# _devbot_lock_wait <lockfile|dir> [cap_seconds] [warning_message]
#   Acquire an exclusive cross-process flock on <lockfile> (or on a directory
#   when a directory is given — flock works on a dir fd, which lets callers
#   lock a collection without leaving a lock file behind). Waits up to
#   cap_seconds (default 600). The lock is held on fd 200 — the caller keeps it
#   until it runs `exec 200>&-` or the script exits.
#   Serializes steps that hammer a SHARED resource across concurrent processes
#   or containers — e.g. `npm install`/`npm update` against a host-mounted npm
#   cache (two dev-bot e2e containers running install simultaneously hang in
#   npm reify) and qmd llama builds on a shared model cache (same rig, CPU
#   freeze). flock(1) is util-linux; on macOS fall back to python fcntl on the
#   inherited fd (same pattern as the reindex tool).
#   Returns 0 when the lock is held; 1 when it could not be acquired in time —
#   the caller should then proceed (with the warning) or skip, never block.
_devbot_lock_wait() {
  local lockfile="$1"
  local cap="${2:-600}"
  local msg="${3:-}"
  if [[ -d "${lockfile}" ]]; then
    # Directory target: open read-only (a dir cannot be opened for writing).
    # The redirect is scoped to the group — a bare `exec … 2>/dev/null` would
    # persist and permanently silence the shell's stderr.
    { exec 200<"${lockfile}"; } 2>/dev/null || return 1
  else
    mkdir -p "$(dirname "${lockfile}")" 2>/dev/null || return 1
    { exec 200>"${lockfile}"; } 2>/dev/null || return 1
  fi
  local waited=0 first_wait=1
  while ! { flock -n 200 2>/dev/null || python3 -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX|fcntl.LOCK_NB)' 2>/dev/null; }; do
    if (( first_wait )); then
      first_wait=0
      _info "waiting for lock $(basename "${lockfile}") (held by another process)…"
    fi
    waited=$((waited + 2))
    if (( waited >= cap )); then
      [[ -n "${msg}" ]] && _warn "${msg}"
      return 1
    fi
    sleep 2
  done
  return 0
}

# ── Devbot session registry (install-level docker lifecycle) ────────────────────
#
# Tracks running devbot harness sessions so the LAST one to exit tears the
# docker services down. Containers are install-level (one compose project
# `devbot`, shared by every session regardless of project), so the registry is
# install-level too: <devbot-root>/storage/run/sessions/.
#
# Liveness uses flock, not pidfiles: each session holds an EXCLUSIVE flock on
# its own file (session-$$) for its lifetime, and the kernel releases it on
# ANY exit — including SIGKILL, where no trap runs. A file whose flock is
# acquirable is therefore stale and gets pruned. When the exiting session
# finds no live session left, it runs the docker teardown.
#
# The flock fd is deliberately NOT inherited by detached children (prune,
# model pulls): the probe opens each file fresh, and a session unlinks its own
# file on release, so an inherited fd on the old inode cannot keep it "live".
#
# _devbot_session_register — record this session. Call BEFORE up.sh so a
#   concurrent last-exit teardown cannot race the containers this session is
#   about to use. Holds fd 210 until release (or process exit).
#
# _devbot_session_release — release this session; if it was the last, tear the
#   containers down. Idempotent (guarded) — safe to call from a trap that may
#   fire alongside an explicit call.
#
# _devbot_session_teardown — docker down for the devbot project (skipped when
#   there is no docker daemon). Delegates to bin/down.sh.

_devbot_sessions_dir() {
  echo "${DEV_BOT_ROOT}/storage/run/sessions"
}

_devbot_session_register() {
  local dir
  dir="$(_devbot_sessions_dir)"
  mkdir -p "${dir}" 2>/dev/null || return 0
  # Hold an exclusive flock on this session's file for the process lifetime.
  # fd 210 is distinct from _devbot_lock_wait's fd 200.
  exec 210>"${dir}/session-$$" 2>/dev/null || return 0
  flock -x 210 2>/dev/null || true
}

_devbot_session_release() {
  # Idempotent — INT/TERM/EXIT traps may all fire, plus an explicit call.
  [[ "${_DEVBOT_SESSION_RELEASED:-0}" == "1" ]] && return 0
  _DEVBOT_SESSION_RELEASED=1

  local dir
  dir="$(_devbot_sessions_dir)"

  # Release our own lock and remove our file so a concurrent probe never sees
  # us as live (an inherited fd on this inode is irrelevant once unlinked).
  flock -u 210 2>/dev/null || true
  exec 210>&- 2>/dev/null || true
  rm -f "${dir}/session-$$" 2>/dev/null || true

  [[ -d "${dir}" ]] || return 0

  # Serialize the probe+teardown against other releases via a lock on the
  # sessions DIRECTORY itself — flock works on a dir fd, so no lock file is
  # left behind (the dir holds only session files). Also remove the legacy
  # .release.lock an older revision created.
  rm -f "${dir}/.release.lock" 2>/dev/null || true
  _devbot_lock_wait "${dir}" 30 \
    "session registry lock held >30s by another process — skipping teardown" || return 0

  local live=0 f
  for f in "${dir}"/session-*; do
    [[ -e "${f}" ]] || continue
    # A file we can lock has no live holder → stale → prune.
    if flock -n "${f}" -c true 2>/dev/null; then
      rm -f "${f}" 2>/dev/null || true
    else
      live=$((live + 1))
    fi
  done

  exec 200>&- 2>/dev/null || true  # release the registry lock

  if [[ ${live} -eq 0 ]]; then
    _devbot_session_teardown
  fi
  return 0
}

_devbot_session_teardown() {
  if ! docker info >/dev/null 2>&1; then
    return 0
  fi
  local down_script="${DEV_BOT_ROOT}/bin/down.sh"
  [[ -f "${down_script}" ]] || return 0
  _info "Last devbot session ended — removing devbot containers"
  bash "${down_script}" >/dev/null 2>&1 || true
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
  # Known-benign qmd graceful-degradation lines: when the shared GPU lacks VRAM
  # (concurrent e2e containers / host ollama), qmd's query-time reranker and
  # query-expansion skip with an InsufficientMemoryError and the search still
  # works — degraded quality, not a runtime failure (audit-45 §4). These lines
  # must not trip the session-end alert the way a genuine crash would.
  local benign='(Reranker unavailable|Structured query expansion failed|GPU init failed|no GPU acceleration|InsufficientMemoryError|skipping reranking)'
  local report_logs="lint-k8s.log format-md.log format-json.log format-yml.log"
  local file count found=0
  while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    case " ${report_logs} " in
      *" $(basename "${file}") "*) continue ;;
    esac
    count="$(grep -iE "${pattern}" "${file}" 2>/dev/null | grep -viE "${benign}" | grep -c . || true)"
    if [[ "${count}" =~ ^[0-9]+$ ]] && (( count > 0 )); then
      found=$((found + 1))
      if [[ ${found} -eq 1 ]]; then
        _warn "Session finished with error log entries in .agents/logs/:"
      fi

      # Distinct error types: normalized matching lines, most frequent first.
      local types type_count
      types="$(grep -iE "${pattern}" "${file}" 2>/dev/null \
        | grep -viE "${benign}" \
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
#   Fires the memory delete→prune self-heal (qmd: cleanup && update, no embed;
#   mdctx: incremental build of project + global indexes) detached BEFORE the
#   harness starts. The engine is the one selected by memory_search_provider;
#   the reindex tool dispatches internally. Moved out of the session.created
#   hook (memory/hooks.json) into the harness start.sh scripts (audit-36):
#     - it runs per launch, not only on the first session.created of a process
#       (audit-34 NOTE-8), and
#     - the engine gets a head start ahead of the MCP-server fleet boot at
#       session start, whose concurrent-launch contention exceeded the client's
#       30s connect budget for the two heaviest servers (audit-35 FAIL).
#   The prune tool (reindex-memories.mcp.sh prune) backgrounds + disowns the
#   engine itself; this helper additionally detaches the invocation from
#   start.sh and writes a marker line so audits can cross-check
#   `.agents/logs/memory-index.log` (engine-agnostic name — qmd and mdctx).
#   Fail-open and silent: no engine binary, no memory vault, or a disabled
#   memory module means "no prune needed here" — it never blocks or fails the
#   harness launch.
_devbot_prune_memories_detached() {
  local project_dir="${1:-$(pwd)}"
  [[ -n "${project_dir}" && -d "${project_dir}" ]] || return 0

  # Disabled memory module → no prune (and no memory-index.log to write).
  if _devbot_get_disabled_modules "${project_dir}" | grep -q '"memory"'; then
    return 0
  fi

  # No memory vault → nothing to prune.
  local devbot_dir vault
  devbot_dir="$(_devbot_get_project_dir "${project_dir}")"
  vault="${project_dir}/${devbot_dir}/memory"
  [[ -d "${vault}" ]] || return 0

  # Fail open when the SELECTED engine's binary is missing.
  local provider
  provider="$(_devbot_get_memory_search_provider "${project_dir}")"
  if [[ "${provider}" == "mdctx" ]]; then
    command -v mdctx >/dev/null 2>&1 || return 0
  else
    command -v qmd >/dev/null 2>&1 || return 0
  fi

  # Resolve the tool next to this file (functions.sh → src/_shared), not via
  # DEV_BOT_ROOT, which may be overridden to a sandbox root in tests.
  local shared_dir tool
  shared_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  tool="${shared_dir}/../agentic/memory/tools/reindex-memories/reindex-memories.mcp.sh"
  [[ -f "${tool}" ]] || return 0

  local logs_dir="${project_dir}/.agents/logs"
  mkdir -p "${logs_dir}" 2>/dev/null || return 0

  # Marker line (synchronous) so a session can prove the prune fired; the
  # engine work itself runs detached inside the tool.
  printf '[reindex-memories-prune-start] devbot start.sh: detached memory prune (%s) launched before harness\n' "${provider}" \
    >> "${logs_dir}/memory-index.log" 2>/dev/null || true

  ( cd "${project_dir}" && bash "${tool}" prune ) >> "${logs_dir}/memory-index.log" 2>&1 &
  disown 2>/dev/null || true

  return 0
}

# ── Codebase engine provider (config-driven) ───────────────────────────────────
#
# _devbot_get_codebase_provider [project_dir]
#   Prints the active codebase engine module name: "codebase-index" or
#   "codebase-memory". Selected by the global-only key "codebase_index_provider"
#   in .devbot.global.jsonc; absent or invalid => "codebase-memory" (the new
#   capability default). project_dir is accepted for signature symmetry but not
#   read in v1 — the provider is deliberately global-only (no per-project
#   override yet).

_devbot_get_codebase_provider() {
  local shared_dir
  shared_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local reader="${shared_dir}/read_jsonc.py"
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"

  local provider=""
  if [[ -f "${global_config}" ]]; then
    provider=$(python3 "${reader}" "${global_config}" "codebase_index_provider" 2>/dev/null || true)
  fi

  case "${provider}" in
    codebase-index | codebase-memory) echo "${provider}" ;;
    *) echo "codebase-memory" ;;
  esac
}

# ── Memory-search engine provider (config-driven) ─────────────────────────────
#
# _devbot_get_memory_search_provider [project_dir]
#   Prints the active memory-search engine module name: "qmd" or "mdctx".
#   Selected by the global-only key "memory_search_provider" in
#   .devbot.global.jsonc; absent or invalid => "mdctx" (the zero-dependency
#   keyword-index default). The DEVBOT_MEMORY_SEARCH_PROVIDER env override
#   wins for hermetic tests. project_dir is accepted for signature symmetry
#   but not read in v1 — the provider is deliberately global-only (no
#   per-project override yet).

_devbot_get_memory_search_provider() {
  local shared_dir
  shared_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local reader="${shared_dir}/read_jsonc.py"
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"

  # DEVBOT_MEMORY_SEARCH_PROVIDER env override wins (hermetic tests — mirrors
  # search-memories.py's SEARCH_MEMORIES_PROVIDER).
  local provider="${DEVBOT_MEMORY_SEARCH_PROVIDER:-}"
  if [[ -z "${provider}" && -f "${global_config}" ]]; then
    provider=$(python3 "${reader}" "${global_config}" "memory_search_provider" 2>/dev/null || true)
  fi

  case "${provider}" in
    qmd | mdctx) echo "${provider}" ;;
    *) echo "mdctx" ;;
  esac
}

# _devbot_ensure_global_default <key> <value>
#   Adds `<key>: "<value>"` (a string) to ${DEV_BOT_ROOT}/.devbot.global.jsonc
#   ONLY when the key is absent — an existing value is never overwritten (an
#   install that deliberately chose the new default keeps it). Thin string
#   wrapper over _devbot_ensure_global_value. Used by `devbot update` to pin
#   the legacy engines on existing installs that predate the provider keys.
#   Silent (callers add their own messaging). Returns 0 on success or no-op,
#   1 when the config file is missing.

_devbot_ensure_global_default() {
  local key="${1:?Usage: _devbot_ensure_global_default <key> <value>}"
  local value="${2:?Usage: _devbot_ensure_global_default <key> <value>}"
  _devbot_ensure_global_value "${key}" "\"${value}\""
}

# _devbot_set_global_value <key> <raw-json>
#   Sets `<key>` in ${DEV_BOT_ROOT}/.devbot.global.jsonc to the raw JSON literal
#   <raw-json> (callers pass JSON — `true`, `"1.4.0"`), replacing an existing
#   value or inserting the key as the first property. Comment-preserving.
#   Returns 0 on success, 1 when the config file is missing.
#
# _devbot_ensure_global_value <key> <raw-json>
#   Adds `<key>: <raw-json>` only when the key is absent (an existing value is
#   never overwritten). Returns 0 on success or no-op, 1 when the config is
#   missing.

_devbot_set_global_value() {
  local key="${1:?Usage: _devbot_set_global_value <key> <raw-json>}"
  local raw="${2:?Usage: _devbot_set_global_value <key> <raw-json>}"
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ -f "${config}" ]] || return 1

  # read_jsonc lives beside this file — pass its dir so the validator imports
  # the same comment-aware parser the rest of the toolkit uses.
  local reader_dir
  reader_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  python3 - "${config}" "${key}" "${raw}" "${reader_dir}" <<'PY' 2>/dev/null || return 1
import re
import sys

path, key, raw, reader_dir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
sys.path.insert(0, reader_dir)
from read_jsonc import load_jsonc

original = open(path).read()
text = original
pattern = re.compile(r'("' + re.escape(key) + r'"\s*:\s*)(?:"[^"]*"|[^,}\s]+)')
if pattern.search(text):
    text = pattern.sub(lambda m: m.group(1) + raw, text, count=1)
else:
    # Insert as the first property. Skip leading comments/whitespace to find
    # the real object brace — a leading `// {` comment must not be mistaken
    # for the object start.
    i = 0
    while True:
        m = re.match(r"\s*", text[i:])
        i += m.end()
        if text.startswith("//", i):
            j = text.find("\n", i)
            if j == -1:
                raise SystemExit(1)
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i)
            if j == -1:
                raise SystemExit(1)
            i = j + 2
        else:
            break
    brace = text.index("{", i) + 1
    rest = text[brace:]
    sep = "" if rest.lstrip().startswith("}") else ","
    text = text[:brace] + '\n  "%s": %s%s' % (key, raw, sep) + rest

open(path, "w").write(text)
try:
    load_jsonc(path)
except Exception:
    open(path, "w").write(original)  # never leave the config unparseable
    raise SystemExit(1)
PY
}

_devbot_ensure_global_value() {
  local key="${1:?Usage: _devbot_ensure_global_value <key> <raw-json>}"
  local raw="${2:?Usage: _devbot_ensure_global_value <key> <raw-json>}"
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ -f "${config}" ]] || return 1
  if grep -q "\"${key}\"[[:space:]]*:" "${config}" 2>/dev/null; then
    return 0
  fi
  _devbot_set_global_value "${key}" "${raw}"
}

# ── Disabled modules (config-driven) ─────────────────────────────────────────────
#
# _devbot_get_disabled_modules [project_dir]
#   Returns a JSON array of disabled module names. The effective state is
#   computed from the "modules" maps (module → bool): the per-project
#   value overrides the global value; a module absent from both is enabled.
#   The two codebase engine modules (codebase-index / codebase-memory) are
#   mutually exclusive: whichever is NOT selected by codebase_index_provider
#   is appended to the disabled set, so exactly one engine is ever wired.
#   The two memory-search engine modules (qmd / mdctx) are mutually exclusive
#   the same way via memory_search_provider — both pairs are independent and
#   both non-selected engines are appended.
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

  # Non-selected codebase engine: codebase-index <-> codebase-memory
  local provider
  provider="$(_devbot_get_codebase_provider "${project_dir}")"
  local non_selected="codebase-index"
  [[ "${provider}" == "codebase-index" ]] && non_selected="codebase-memory"

  # Non-selected memory-search engine: qmd <-> mdctx
  local mem_provider non_selected_mem
  mem_provider="$(_devbot_get_memory_search_provider "${project_dir}")"
  non_selected_mem="qmd"
  [[ "${mem_provider}" == "qmd" ]] && non_selected_mem="mdctx"

  # Merge: project overrides global. A module is disabled when its effective
  # value is false (project value if present, else global value). The
  # non-selected codebase engine and non-selected memory-search engine are
  # always disabled (mutual exclusion per pair).
  GLOBAL_STATES="${global_states}" PROJECT_STATES="${project_states}" \
    NON_SELECTED="${non_selected}" NON_SELECTED_MEM="${non_selected_mem}" python3 -c '
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
disabled.add(os.environ["NON_SELECTED"])
disabled.add(os.environ["NON_SELECTED_MEM"])
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

# ── MCP env-var presence check ──────────────────────────────────────────────────
#
# _devbot_missing_mcp_env_vars <project_dir>
#   Prints one line per {env:VAR} reference found in an enabled module's
#   canonical mcp.json whose variable is unset or empty in the current shell
#   env. Line format: <module>|<server>|<env_key>|<VAR> (pipe-separated).
#   Skips disabled modules and plugin-provided modules (plugin.opencode.json)
#   — the same skip set as init's _register_module_mcp. The extractor is
#   resolved from this file's directory (not DEV_BOT_ROOT, which may be
#   overridden to a sandbox root in tests).
#
# _devbot_present_missing_env_vars <refs> <mode>
#   refs: newline-separated <module>|<server>|<env_key>|<VAR> lines (as
#   produced by _devbot_missing_mcp_env_vars). mode:
#     report — print the notice, no prompt
#     ack    — print the notice, ask the user to press any key, continue
#     gate   — print the notice, ask y/N "launch the harness anyway"; N → 1
#   DEV_BOT_DEFER_ENV_DIALOG=1 (reinit --all defers the dialog to the end of
#   the run), SKIP_CONFIRM=1 and non-TTY stdin all collapse ack/gate to
#   report — never block a non-interactive run.
#
# _devbot_check_mcp_env_vars <project_dir> <mode>
#   Wrapper: collect the missing refs, then present them in the given mode.

_devbot_missing_mcp_env_vars() {
  local project_dir="${1:-$(pwd)}"
  local shared_dir
  shared_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local refs_script="${shared_dir}/mcp_env_refs.py"
  [[ -f "${refs_script}" ]] || return 0

  local disabled_raw disabled_modules
  disabled_raw="$(_devbot_get_disabled_modules "${project_dir}")"
  disabled_modules="$(echo "${disabled_raw}" | jq -r '.[]' 2>/dev/null || true)"

  local base_dir
  for base_dir in "${DEV_BOT_ROOT}/src/tools" "${DEV_BOT_ROOT}/src/agentic" "${DEV_BOT_ROOT}/src/harnesses"; do
    [[ -d "${base_dir}" ]] || continue
    local mod_dir
    for mod_dir in "${base_dir}/"*/; do
      local mod_name mod_mcp
      mod_name="$(basename "${mod_dir}")"
      mod_mcp="${mod_dir}mcp.json"
      [[ -f "${mod_mcp}" ]] || continue

      if echo "${disabled_modules}" | grep -Fxq "${mod_name}" 2>/dev/null; then
        continue
      fi
      # Plugin-provided servers are NOT MCP-registered (opencode loads them
      # from plugin.opencode.json) — their env refs are not init's business.
      if [[ -f "${mod_dir}plugin.opencode.json" ]]; then
        continue
      fi

      local server env_key var
      while IFS=$'\t' read -r server env_key var; do
        [[ -n "${server}" ]] || continue
        if [[ -z "${!var:-}" ]]; then
          echo "${mod_name}|${server}|${env_key}|${var}"
        fi
      done < <(python3 "${refs_script}" "${mod_mcp}" 2>/dev/null)
    done
  done
}

_devbot_present_missing_env_vars() {
  local refs="$1"
  local mode="${2:-report}"
  [[ -n "${refs}" ]] || return 0

  # reinit --all defers the dialog to the end of the run: each per-project
  # init emits only a COMPACT notice (the end-of-run dialog dedupes and shows
  # the full detail). SKIP_CONFIRM and a non-TTY stdin mean nobody is there
  # to answer — emit the full notice but never prompt.
  if [[ "${DEV_BOT_DEFER_ENV_DIALOG:-0}" == "1" ]]; then
    local compact_vars=""
    local line
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      local var="${line##*|}"
      if ! echo "${compact_vars}" | grep -Fxq "${var}" 2>/dev/null; then
        compact_vars+="${var} "
      fi
    done <<<"${refs}"
    _warn "MCP configs reference unset env var(s): ${compact_vars}— full notice at end of reinit"
    return 0
  fi

  local effective_mode="${mode}"
  if [[ "${SKIP_CONFIRM:-0}" == "1" || ! -t 0 ]]; then
    effective_mode="report"
  fi

  _warn "MCP configs reference environment variables that are not set:"
  local line
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    local module="${line%%|*}"
    local rest="${line#*|}"
    local server="${rest%%|*}"
    rest="${rest#*|}"
    local env_key="${rest%%|*}"
    local var="${rest#*|}"
    _log "  ${var} (${module} MCP '${server}', env key '${env_key}')"
  done <<<"${refs}"

  # One export suggestion per unique variable (the refs may repeat a var).
  _warn "Add them to your shell profile (e.g. ~/.bashrc or equivalent):"
  local unique_vars=""
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    local var="${line##*|}"
    if ! echo "${unique_vars}" | grep -Fxq "${var}" 2>/dev/null; then
      unique_vars+="${var}"$'\n'
      _log "  export ${var}=..."
    fi
  done <<<"${refs}"
  _info "Then start devbot from a NEW terminal so it picks up the new variables."

  case "${effective_mode}" in
    ack)
      _info "Press any key to acknowledge and continue..."
      read -r -n 1 -s 2>/dev/null || true
      _ok "Continuing."
      ;;
    gate)
      _warn "Launch the harness anyway? [y/N]"
      local answer
      read -r answer 2>/dev/null || true
      if [[ "${answer}" =~ ^[yY](es)?$ ]]; then
        return 0
      fi
      return 1
      ;;
  esac
  return 0
}

_devbot_check_mcp_env_vars() {
  local project_dir="${1:-$(pwd)}"
  local mode="${2:-report}"
  local refs
  refs="$(_devbot_missing_mcp_env_vars "${project_dir}")"
  _devbot_present_missing_env_vars "${refs}" "${mode}"
}

# ── Config-change → auto-reinit (devbot start) ──────────────────────────────────
#
# A project's wiring depends on BOTH the global config
# (${DEV_BOT_ROOT}/.devbot.global.jsonc) and its own project config
# (${project_dir}/.devbot.project.jsonc). The reinit trigger is a single
# per-project content hash over the two files, stored at
# <project>/.devbot.project.sha (the project config path with its .jsonc
# extension REPLACED). A change in either file — including the `version` bump
# `devbot update` writes to the global config — makes the stored hash differ, so
# that project reinits on its next start. Baselines are refreshed by init.sh at
# the end of every init/reinit; a missing .sha (fresh project, or an install
# upgrading from the retired per-file baselines) counts as changed, so one
# reinit establishes it.
#
# _devbot_config_sha_path <project_config>
#   Prints the sibling .sha path (extension replaced) — the per-project wiring
#   baseline.
#
# _devbot_config_sha <file> [<file>...]
#   Prints the sha256 over the given files' contents joined with a NUL byte, so
#   file boundaries can never alias. A missing file contributes an empty
#   segment. Empty when python3 is unavailable.
#
# _devbot_wiring_sha <project_dir>
#   Combined hash of the global config and the project config.
#
# _devbot_config_changed <project_dir>
#   0 when the wiring hash differs from the stored .sha, or when no .sha
#   baseline exists (E1). 1 when neither config exists or the hash matches.
#
# _devbot_write_config_sha <project_dir>
#   Writes the project's wiring hash to <project>/.devbot.project.sha.
#
# _devbot_auto_reinit_if_config_changed <project_dir>
#   0 and no-op when the project's wiring hash is unchanged. When it changed:
#   runs `bash $DEV_BOT_ROOT/bin/reinit.sh` from the project dir (single-project
#   reinit; the init.sh it ends with refreshes the baseline). On reinit failure:
#   warns and, in a non-interactive run (SKIP_CONFIRM / no TTY), returns 0 =
#   continue the start anyway; interactively asks y/N.

_devbot_config_sha_path() {
  local config="$1"
  echo "${config%.jsonc}.sha"
}

_devbot_config_sha() {
  [[ $# -gt 0 ]] || return 0
  python3 - "$@" <<'PY' 2>/dev/null || true
import hashlib
import sys

h = hashlib.sha256()
for i, path in enumerate(sys.argv[1:]):
    if i:
        h.update(b"\0")
    try:
        with open(path, "rb") as fh:
            h.update(fh.read())
    except OSError:
        pass
print(h.hexdigest())
PY
}

_devbot_wiring_sha() {
  local project_dir="${1:-$(pwd)}"
  _devbot_config_sha \
    "${DEV_BOT_ROOT}/.devbot.global.jsonc" \
    "${project_dir}/.devbot.project.jsonc"
}

_devbot_config_changed() {
  local project_dir="${1:-$(pwd)}"
  local project_config="${project_dir}/.devbot.project.jsonc"
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ -f "${project_config}" || -f "${global_config}" ]] || return 1
  local sha_path current stored
  sha_path="$(_devbot_config_sha_path "${project_config}")"
  [[ -f "${sha_path}" ]] || return 0  # no baseline → changed
  current="$(_devbot_wiring_sha "${project_dir}")"
  stored="$(<"${sha_path}")"
  [[ -n "${current}" && "${current}" == "${stored}" ]] && return 1
  return 0
}

_devbot_write_config_sha() {
  local project_dir="${1:-$(pwd)}"
  local project_config="${project_dir}/.devbot.project.jsonc"
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ -f "${project_config}" || -f "${global_config}" ]] || return 0
  local sha_path current
  sha_path="$(_devbot_config_sha_path "${project_config}")"
  current="$(_devbot_wiring_sha "${project_dir}")"
  [[ -n "${current}" ]] || return 0
  printf '%s\n' "${current}" > "${sha_path}"
}

_devbot_auto_reinit_if_config_changed() {
  local project_dir="${1:-$(pwd)}"
  _devbot_config_changed "${project_dir}" || return 0

  _header_3 "Config changed — running devbot reinit before start..."
  local reinit_script="${DEV_BOT_ROOT}/bin/reinit.sh"
  local reinit_exit=0
  if [[ -f "${reinit_script}" ]]; then
    (cd "${project_dir}" && bash "${reinit_script}") || reinit_exit=$?
  else
    reinit_exit=127
  fi
  if [[ ${reinit_exit} -eq 0 ]]; then
    _ok "Reinit complete after config change"
    return 0
  fi

  _warn "Automatic reinit failed (exit ${reinit_exit}) — the start would run on stale wiring."
  # Non-interactive: never block a scripted/CI start — warn and continue.
  if [[ "${SKIP_CONFIRM:-0}" == "1" || ! -t 0 ]]; then
    _warn "Non-interactive run — continuing the start anyway."
    return 0
  fi
  _warn "Continue the start anyway? [y/N]"
  local answer
  read -r answer 2>/dev/null || true
  if [[ "${answer}" =~ ^[yY](es)?$ ]]; then
    return 0
  fi
  return 1
}

# ── Auto-update (devbot start) ──────────────────────────────────────────────────
#
# _devbot_auto_update_if_enabled
#   Runs `bin/update.sh --auto` before the start wiring when the global config's
#   `auto_update` is not explicitly false (absent => enabled). `update.sh --auto`
#   is a clean no-op when already on the newest release; a failure (offline,
#   conflict) is reported and swallowed — a start must never be blocked by it.
#   Returns 0 always.
#
#   NOTE: when update.sh moves the checkout, this process keeps the functions.sh
#   it already sourced while the child scripts on disk (up.sh / reinit.sh /
#   start.sh) are the new version — the upgrade start runs a mix of old and new
#   code. Keep the contract between this file and those children (project dir,
#   argv, config files) stable, or re-exec the new bin/devbot after a move.

_devbot_auto_update_if_enabled() {
  local global_config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  local enabled="true"
  if [[ -f "${global_config}" ]]; then
    local shared_dir reader
    shared_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    reader="${shared_dir}/read_jsonc.py"
    enabled="$(python3 "${reader}" "${global_config}" auto_update 2>/dev/null || true)"
  fi
  [[ "${enabled}" == "false" ]] && return 0

  local update_script="${DEV_BOT_ROOT}/bin/update.sh"
  [[ -f "${update_script}" ]] || return 0

  local rc=0
  bash "${update_script}" --auto || rc=$?
  if [[ ${rc} -ne 0 ]]; then
    _warn "devbot auto-update failed (exit ${rc}) — continuing on the current version."
  fi
  return 0
}

# ── Harness-arg passthrough (devbot -- …) ─────────────────────────────────────
#
# _devbot_passthrough_args [args...]
#   The devbot CLI escape: when a bare `devbot` start carries `--`, everything
#   after the FIRST `--` is forwarded verbatim to the underlying harness and
#   everything before it is devbot's own (consumed, never forwarded). No `--`
#   in the args → all args forward unchanged (the documented "unknown
#   argument starts the harness" behaviour). Only the first `--` splits — a
#   later `--` is a literal part of the harness argv.
#
#   Prints one arg per line (NOT a single line — args keep their boundaries,
#   so quoting survives: `-c "two words"` forwards as two argv elements).
#   Callers assemble an argv array with a while-read loop (bash 3.2-safe —
#   macOS default bash has no mapfile), exactly as cmd_harness in bin/devbot
#   does. Output is empty when there is nothing to forward.

_devbot_passthrough_args() {
  # Nothing to forward — no output at all (printf '%s\n' "$@" with zero args
  # would emit one empty line and corrupt the caller's argv).
  if [[ $# -eq 0 ]]; then
    return 0
  fi

  # First pass: does the arg list carry a -- separator at all? No -- → every
  # arg forwards unchanged (documented "unknown argument" harness start).
  local has_sep=false
  local a
  for a in "$@"; do
    if [[ "${a}" == "--" ]]; then
      has_sep=true
      break
    fi
  done
  if [[ "${has_sep}" == "false" ]]; then
    printf '%s\n' "$@"
    return 0
  fi

  # Second pass: emit only the args AFTER the first -- (pre-`--` args are
  # devbot's own and are consumed; a later -- is a literal tail arg).
  local started=false
  for a in "$@"; do
    if [[ "${started}" == "false" && "${a}" == "--" ]]; then
      started=true
      continue
    fi
    if [[ "${started}" == "true" ]]; then
      printf '%s\n' "${a}"
    fi
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

# _devbot_detect_gpu
#   Detects GPU availability and records the result in the global config's
#   `gpu_enabled` key via _devbot_set_bool. Semantics (moved verbatim from
#   src/tools/ollama/install.sh, audit-25 F5):
#     - no docker daemon  → gpu_enabled follows the HOST probe (_has_gpu):
#       the host's ollama serves the API and local processes (qmd) can use
#       the GPU directly even though no ollama container runs here.
#     - docker daemon     → gpu_enabled follows _has_docker_gpu (container
#       passthrough): a host GPU without the container toolkit does NOT
#       enable passthrough.
#   Runs from the devbot lifecycle (bin/install.sh, bin/update.sh) — NOT from
#   the ollama module install — so GPU detection survives the ollama module
#   being disabled in the `modules` map (it is disabled by default; consumer
#   compose fragments boot it on demand).
#   Never fails the caller: prints informational messages, returns 0.

_devbot_detect_gpu() {
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  if [[ ! -f "${config}" ]]; then
    _skip "gpu detection skipped — no .devbot.global.jsonc yet (run install's config step first)"
    return 0
  fi

  if ! docker info >/dev/null 2>&1; then
    if _has_gpu; then
      _info "GPU detected on this machine — recording gpu_enabled=true (qmd etc. can use it locally); ollama container skipped (no docker daemon)"
      _devbot_set_bool "gpu_enabled" "true"
    else
      _info "No GPU detected — recording gpu_enabled=false"
      _devbot_set_bool "gpu_enabled" "false"
    fi
    return 0
  fi

  if _has_docker_gpu; then
    local vendor
    vendor="$(_gpu_vendor)"
    _info "$(printf '%s' "${vendor}" | tr '[:lower:]' '[:upper:]') GPU detected — enabling GPU passthrough for ollama."
    _devbot_set_bool "gpu_enabled" "true"
  else
    if _has_gpu; then
      local vendor
      vendor="$(_gpu_vendor)"
      case "$(uname -s)" in
        Darwin)
          _info "Apple Silicon GPU detected but Docker Desktop does not support GPU passthrough."
          _info "Ollama will run on CPU inside Docker."
          ;;
        Linux)
          case "${vendor}" in
            nvidia)
              _info "NVIDIA GPU detected but NVIDIA Container Toolkit is not installed."
              _info "Install it from: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/"
              ;;
            amd)
              _info "AMD GPU detected but ROCm kernel driver (/dev/kfd) is not accessible."
              _info "Ensure the amdgpu kernel module is loaded and user has render group access."
              ;;
            intel)
              _info "Intel GPU detected but /dev/dri is not accessible from containers."
              _info "Ensure the user has video/render group membership."
              ;;
          esac
          _info "Ollama will run on CPU."
          ;;
      esac
    else
      _info "No GPU detected — ollama will run on CPU."
    fi
    _devbot_set_bool "gpu_enabled" "false"
  fi
  return 0
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

# _devbot_ollama_exec <args...>
#   Runs `ollama <args...>` inside the dev-bot-ollama container, booting the
#   container first when it is not running and taking it back DOWN afterwards
#   when THIS helper started it. A container that was already running is left
#   running. Backs `devbot models pull/list-local/remove` — those commands
#   must work even though the ollama module is disabled by default (it only
#   runs when an enabled consumer fragment includes it).
#   The temporary boot mirrors the qmd share script's compose opts: when
#   gpu_enabled, docker-compose.gpu.yml is appended so a GPU machine does not
#   serve CPU-only after a temporary boot. Returns the ollama command's exit
#   code; fails cleanly (exit 1) when there is no docker daemon.

_devbot_ollama_exec() {
  if ! docker info >/dev/null 2>&1; then
    _skip "no docker daemon (inside a container?) — ollama exec skipped; the host serves the ollama API instead"
    return 1
  fi

  local compose_file="${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml"
  local container_was_running=false
  local started_container=false
  local -a compose_opts=("-f" "${compose_file}")
  # Absolute path — this helper runs from the caller's cwd (devbot models),
  # not from DEV_BOT_ROOT, so a relative gpu overlay would not resolve.
  if _devbot_is_true "gpu_enabled" && [[ -f "${DEV_BOT_ROOT}/docker-compose.gpu.yml" ]]; then
    compose_opts+=("-f" "${DEV_BOT_ROOT}/docker-compose.gpu.yml")
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'dev-bot-ollama'; then
    container_was_running=true
  else
    _info "Ollama container not running — starting it temporarily..."
    if docker compose "${compose_opts[@]}" up -d ollama 2>/dev/null; then
      started_container=true
      # Wait for ollama to be ready before exec'ing into it.
      local retries=15
      while ! docker exec dev-bot-ollama ollama list >/dev/null 2>&1; do
        if [[ ${retries} -le 0 ]]; then
          _warn "Ollama container did not become ready in time — stopping it"
          docker compose "${compose_opts[@]}" down ollama 2>/dev/null || true
          return 1
        fi
        sleep 1
        (( retries-- ))
      done
    else
      _warn "Failed to start Ollama container"
      return 1
    fi
  fi

  docker exec dev-bot-ollama ollama "$@"
  local exec_rc=$?

  if [[ "${started_container}" == true && "${container_was_running}" == false ]]; then
    _info "Stopping temporary Ollama container..."
    docker compose "${compose_opts[@]}" down ollama 2>/dev/null || true
  fi
  return "${exec_rc}"
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
