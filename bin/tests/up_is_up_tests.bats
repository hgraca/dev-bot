#!/usr/bin/env bats
# =============================================================================
# bin/tests/up_is_up_tests.bats
# Tests for the `bin/up.sh --is-up` probe — the read-only check the bare
# `devbot` start uses to skip a warm up sequence.
#
# Contract: exit 0 only when this project's start already completed here (its
# stamp matches the current wiring) AND every docker service the project's
# enabled modules declare is running. Everything else — no stamp, another
# project's stamp, a changed wiring, no daemon, no config, an unresolvable
# compose model, no declared service — exits 1, so the caller falls back to the
# normal start rather than skipping it. The probe prints nothing.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"

  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared" \
    "${SANDBOX}/src/tools/litellm" "${SANDBOX}/src/harnesses" \
    "${SANDBOX}/mockbin"

  # Production up.sh without its main call — sourced so _up_is_up is callable.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/up.sh" > "${SANDBOX}/bin/up.sh"
  # The untouched script, for the tests that run the real `--is-up` dispatch.
  cp "${PROJECT_ROOT}/bin/up.sh" "${SANDBOX}/bin/up-full.sh"

  # Stub the shared helpers _compose_opts depends on; the real GPU-overlay
  # marker parser is extracted verbatim so it cannot drift from production.
  cat > "${SANDBOX}/src/_shared/functions.sh" <<'HEREDOC'
#!/usr/bin/env bash
_header_1() { true; }
_header_2() { true; }
_header_3() { true; }
_info()  { true; }
_ok()    { true; }
_skip()  { echo "SKIP: $*"; }
_warn()  { true; }
_error() { echo "ERROR: $*" >&2; exit 1; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
_log()   { true; }
_fmt_duration() { echo "0s"; }
TEXT_BOLD=''
TEXT_BLUE=''
TEXT_CLEAR=''
TEXT_DIM=''
TEXT_GREEN=''
TEXT_YELLOW=''
TEXT_ORANGE=''
TEXT_RED=''

_devbot_is_true() {
  local key="$1"
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ ! -f "${config}" ]] && return 1
  grep -q "\"${key}\"[[:space:]]*:[[:space:]]*true" "${config}" 2>/dev/null && return 0
  return 1
}

_has_docker_gpu() { [[ "${MOCK_HAS_DOCKER_GPU:-no}" == "yes" ]]; }

_devbot_get_disabled_modules() {
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ ! -f "${config}" ]] && echo "[]" && return 0
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    states = data.get('modules', {})
    print(json.dumps(sorted(m for m, v in states.items() if v is False)))
except:
    print('[]')
" "${config}" 2>/dev/null || echo "[]"
}

# The wiring hash the stamp records. Fixed per test: the real one is covered by
# src/_shared/tests/config_sha_tests.bats.
_devbot_wiring_sha() { echo "${MOCK_WIRING_SHA:-sha-1}"; }

# The mount root the stamp records; the probe compares it so a widened root is
# never skipped over.
_devbot_codebase_memory_root() { echo "${MOCK_MEMORY_ROOT:-/home/probe}"; }

# The playwright gateway root: recorded in the stamp AND exported before every
# compose hand-off (compose interpolates it as mandatory).
_devbot_playwright_root() {
  local r="${MOCK_PLAYWRIGHT_ROOT:-/home/probe}"
  r="${r%/}"
  [[ -n "${r}" && "${r}" == /* ]] || return 1
  printf '%s\n' "${r}"
}
_devbot_export_playwright_root() { export PLAYWRIGHT_ROOT="$(_devbot_playwright_root)"; }
_devbot_persist_playwright_root() { echo "$1" >> "${PERSIST_CALLS_FILE:-/dev/null}"; }

_devbot_load_env_file() { return 0; }

# The install-level up lock bin/up.sh holds and bin/down.sh waits on.
_devbot_up_lock_path() { echo "${DEV_BOT_ROOT}/storage/run/up.lock"; }

# Real flock, so the --if-needed tests can hold the up lock from another
# process. Mirrors the production cap semantics: the Nth two-second probe that
# fails is the timeout.
_devbot_lock_wait() {
  local lockfile="$1" cap="${2:-600}" msg="${3:-}"
  mkdir -p "$(dirname "${lockfile}")" 2>/dev/null || return 1
  { exec 200>"${lockfile}"; } 2>/dev/null || return 1
  local waited=0
  while ! flock -n 200 2>/dev/null; do
    waited=$((waited + 2))
    if (( waited >= cap )); then
      [[ -n "${msg}" ]] && _warn "${msg}"
      return 1
    fi
    sleep 2
  done
}
HEREDOC

  awk '/^_gpu_overlay_skip_if\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh" \
    >> "${SANDBOX}/src/_shared/functions.sh"

  echo '{}' > "${SANDBOX}/.devbot.global.jsonc"
  : > "${SANDBOX}/src/tools/litellm/docker-compose.yml"

  # Mock docker: `info` honours MOCK_DOCKER_INFO_RC; `compose config --services`
  # answers from MOCK_DECLARED (honouring MOCK_CONFIG_RC); `compose ps
  # --status running --services` answers from MOCK_RUNNING. Every call is
  # recorded so a test can assert the selected compose files reach compose.
  cat > "${SANDBOX}/mockbin/docker" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "${DOCKER_ARGS_FILE}"
if [[ "$1" == "info" ]]; then
  exit "${MOCK_DOCKER_INFO_RC:-0}"
fi
if [[ "$1" == "ps" ]]; then
  cat "${MOCK_CONTAINERS}"
  exit 0
fi
if [[ "$1" == "compose" ]]; then
  case " $* " in
    *" config --services "*)
      [[ -n "${MOCK_CONFIG_RC:-}" ]] && exit "${MOCK_CONFIG_RC}"
      cat "${MOCK_DECLARED}"
      exit 0
      ;;
    *" --status running --services "*)
      cat "${MOCK_RUNNING}"
      exit 0
      ;;
  esac
fi
exit 0
MOCK
  chmod +x "${SANDBOX}/mockbin/docker"

  export DOCKER_ARGS_FILE="${SANDBOX}/docker.args"
  : > "${DOCKER_ARGS_FILE}"
  PATH="${SANDBOX}/mockbin:${PATH}"

  MOCK_DECLARED="${SANDBOX}/declared"
  MOCK_RUNNING="${SANDBOX}/running"
  MOCK_CONTAINERS="${SANDBOX}/containers"
  : > "${MOCK_DECLARED}"
  : > "${MOCK_RUNNING}"
  printf 'dev-bot-mdctx-mcp\n' > "${MOCK_CONTAINERS}"
  export MOCK_DECLARED MOCK_RUNNING MOCK_CONTAINERS

  PROBE_PROJECT="${SANDBOX}/project"
  mkdir -p "${PROBE_PROJECT}"
}

teardown() {
  rm -rf "${SANDBOX}"
}

# Run the probe in a subshell so `set -e`/globals cannot leak between tests.
_run_is_up() {
  run bash -c '
    source "'"${SANDBOX}"'/bin/up.sh"
    PROJECT_DIR="'"${PROBE_PROJECT}"'"
    _up_is_up
  '
}

# Record a completed start for PROBE_PROJECT, the way a real up does.
_seed_stamp() {
  local project="${1:-${PROBE_PROJECT}}"
  MOCK_WIRING_SHA="${2:-sha-1}" bash -c '
    source "'"${SANDBOX}"'/bin/up.sh"
    PROJECT_DIR="'"${project}"'"
    _write_up_stamp
  '
}

# ── Tests ──────────────────────────────────────────────────────────────────

@test "is-up: a completed start plus every declared service running answers 0" {
  printf 'codebase-memory-mcp\nmdctx-mcp\nollama\n' > "${MOCK_DECLARED}"
  printf 'codebase-memory-mcp\nmdctx-mcp\nollama\n' > "${MOCK_RUNNING}"
  _seed_stamp

  _run_is_up

  assert_success
  [ -z "${output}" ]
}

@test "is-up: running services alone are not enough — a project that never ran answers 1" {
  # The compose scan cannot see what a module's up.sh starts (the datasources
  # gateway is rendered per project), so another project's session holding the
  # shared services up must not skip this project's first start.
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"

  _run_is_up

  assert_failure
}

@test "is-up: a stamp written for another project answers 1" {
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp "${SANDBOX}/other-project"

  _run_is_up

  assert_failure
}

@test "is-up: a stamp from another wiring answers 1 (config change or update)" {
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp "${PROBE_PROJECT}" sha-1

  MOCK_WIRING_SHA=sha-2 _run_is_up

  assert_failure
}

@test "is-up: a changed desired repo mount answers 1" {
  # The gateway's bind mount is fixed at container creation and only a module
  # up.sh recreates it, so a widened root must reach the real start.
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp

  MOCK_MEMORY_ROOT=/srv/other _run_is_up

  assert_failure
}

@test "is-up: a changed playwright mount root answers 1" {
  # Same rule for the browser gateway: its workspace mount is fixed at creation
  # too, so an explicit PLAYWRIGHT_ROOT override must not be skipped over.
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp

  MOCK_PLAYWRIGHT_ROOT=/srv/other _run_is_up

  assert_failure
}

@test "is-up: a stamped container that is gone answers 1" {
  # A module up.sh may have started it; the stamp remembers what was running, so
  # a container that stopped later is recreated rather than skipped over.
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp

  printf 'dev-bot-something-else\n' > "${MOCK_CONTAINERS}"
  _run_is_up

  assert_failure
}

@test "is-up: a failed module script clears the previous stamp" {
  # A tolerated failure must not leave the earlier success standing: the next
  # start has to retry what this one did not finish.
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp

  run bash -c '
    source "'"${SANDBOX}"'/bin/up.sh"
    PROJECT_DIR="'"${PROBE_PROJECT}"'"
    MODULE_SCRIPT_FAILED=1
    _record_start
  '
  assert_success
  [ -z "$(find "${SANDBOX}/storage/run/up" -name '*.stamp' 2>/dev/null)" ]

  _run_is_up
  assert_failure
}

# ── `--if-needed` under the install-level up lock ─────────────────────────────
# The bare start probes first, then calls `up.sh --if-needed`. A start that
# overlapped another one reaches that call with no stamp: it must wait for the
# in-flight up and re-probe before running a second sequence.

# Drive _up_run_locked with a stand-in main, so the decision is tested without
# the real sequence. The sourced script has its `main "$@"` tail stripped.
_run_locked() {
  local if_needed="$1" cap="${2:-600}"
  run bash -c '
    source "'"${SANDBOX}"'/bin/up.sh"
    PROJECT_DIR="'"${PROBE_PROJECT}"'"
    UP_IF_NEEDED='"${if_needed}"'
    DEVBOT_UP_LOCK_WAIT='"${cap}"'
    main() { echo "MAIN_RAN"; }
    _up_install_trap() { :; }
    _warn() { echo "WARN: $*"; }
    _up_run_locked
  '
}

# Hold the up lock for N seconds from another process; return only once it is
# actually held, so the caller cannot win the race to the lock.
_hold_up_lock() {
  local seconds="$1"
  local ready="${SANDBOX}/lock-ready"
  mkdir -p "${SANDBOX}/storage/run"
  rm -f "${ready}"
  flock -x "${SANDBOX}/storage/run/up.lock" -c "touch '${ready}'; sleep ${seconds}" &
  LOCK_HOLDER=$!
  local waited=0
  while [[ ! -f "${ready}" ]] && (( waited < 50 )); do
    sleep 0.1
    waited=$((waited + 1))
  done
}

_release_up_lock() {
  wait "${LOCK_HOLDER}" 2>/dev/null || true
}

@test "if-needed: waits for an in-flight up, re-probes and skips" {
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp
  _hold_up_lock 2

  _run_locked 1

  assert_success
  assert_output --partial "devbot services already running"
  refute_output --partial "MAIN_RAN"
  _release_up_lock
}

@test "if-needed: runs the sequence when no start completed while waiting" {
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _hold_up_lock 2

  _run_locked 1

  assert_success
  assert_output --partial "MAIN_RAN"
  refute_output --partial "devbot services already running"
  _release_up_lock
}

@test "up: an explicit run ignores a valid stamp (devbot up stays unchanged)" {
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp

  _run_locked 0

  assert_success
  assert_output --partial "MAIN_RAN"
  refute_output --partial "devbot services already running"
}

@test "up: the lock is held while the sequence runs" {
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"

  run bash -c '
    source "'"${SANDBOX}"'/bin/up.sh"
    PROJECT_DIR="'"${PROBE_PROJECT}"'"
    UP_IF_NEEDED=0
    main() {
      if flock -n "'"${SANDBOX}"'/storage/run/up.lock" -c true; then
        echo "LOCK_FREE"
      else
        echo "LOCK_HELD"
      fi
    }
    _up_install_trap() { :; }
    _up_run_locked
  '

  assert_success
  assert_output --partial "LOCK_HELD"
}

@test "if-needed: the fall-through still re-probes and skips" {
  # A wait that exceeds the cap releases the caller unlocked. If the in-flight
  # start completed at the boundary, a second sequence must still not run.
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp
  _hold_up_lock 1

  _run_locked 1 2

  assert_success
  assert_output --partial "devbot services already running"
  refute_output --partial "MAIN_RAN"
  _release_up_lock
}

@test "if-needed: the fall-through warns with the cap when nothing completed" {
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _hold_up_lock 1

  _run_locked 1 2

  assert_success
  assert_output --partial "MAIN_RAN"
  assert_output --partial "DEVBOT_UP_LOCK_WAIT"
  assert_output --partial "cap 2s"
  _release_up_lock
}

@test "is-up: a completed start records the stamp the probe then accepts" {
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"

  run bash -c '
    source "'"${SANDBOX}"'/bin/up.sh"
    PROJECT_DIR="'"${PROBE_PROJECT}"'"
    MODULE_SCRIPT_FAILED=0
    _record_start
  '
  assert_success

  _run_is_up
  assert_success
}

@test "is-up: a start that aborts leaves no stamp behind" {
  # main() invalidates the record before its first step, so an abort anywhere
  # (compose, a module script, the ERR trap) cannot leave the old one standing.
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp

  run bash -c '
    source "'"${SANDBOX}"'/bin/up.sh"
    PROJECT_DIR="'"${PROBE_PROJECT}"'"
    _clear_up_stamp
  '
  assert_success
  [ -z "$(find "${SANDBOX}/storage/run/up" -name '*.stamp' 2>/dev/null)" ]

  _run_is_up
  assert_failure
}

@test "is-up: a stamp with no containers is not written" {
  # A start whose containers the probe cannot list is not vouched for.
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  : > "${MOCK_CONTAINERS}"

  run bash -c '
    source "'"${SANDBOX}"'/bin/up.sh"
    PROJECT_DIR="'"${PROBE_PROJECT}"'"
    _write_up_stamp
  '
  assert_success
  [ -z "$(find "${SANDBOX}/storage/run/up" -name '*.stamp' 2>/dev/null)" ]
}

@test "is-up: a declared service that is not running answers 1" {
  printf 'litellm\nmdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp

  _run_is_up

  assert_failure
  [ -z "${output}" ]
}

@test "is-up: no running containers answers 1" {
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  : > "${MOCK_RUNNING}"
  _seed_stamp

  _run_is_up

  assert_failure
}

@test "is-up: no enabled module declares a service answers 1" {
  # Nothing is "up" when nothing was ever declared: the normal start still runs,
  # so the module up scripts get their turn.
  echo '{"modules": {"litellm": false}}' > "${SANDBOX}/.devbot.global.jsonc"
  _seed_stamp

  _run_is_up

  assert_failure
}

@test "is-up: no docker daemon answers 1" {
  printf 'litellm\n' > "${MOCK_DECLARED}"
  printf 'litellm\n' > "${MOCK_RUNNING}"
  _seed_stamp

  MOCK_DOCKER_INFO_RC=1 _run_is_up

  assert_failure
}

@test "is-up: an unresolvable compose model answers 1" {
  printf 'litellm\n' > "${MOCK_DECLARED}"
  printf 'litellm\n' > "${MOCK_RUNNING}"
  _seed_stamp

  MOCK_CONFIG_RC=1 _run_is_up

  assert_failure
}

@test "is-up: no global config answers 1" {
  rm -f "${SANDBOX}/.devbot.global.jsonc"
  printf 'litellm\n' > "${MOCK_DECLARED}"
  printf 'litellm\n' > "${MOCK_RUNNING}"
  _seed_stamp

  _run_is_up

  assert_failure
}

@test "is-up: asks compose with the selected compose files" {
  printf 'mdctx\n' > "${MOCK_DECLARED}"
  printf 'mdctx\n' > "${MOCK_RUNNING}"
  _seed_stamp

  _run_is_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial "-f src/tools/litellm/docker-compose.yml"
  assert_output --partial "config --services"
  assert_output --partial "ps --status running --services"
}

@test "is-up: is silent even when compose prints its own output" {
  # The probe must not leak compose chatter into the harness start.
  printf 'litellm\n' > "${MOCK_DECLARED}"
  printf 'litellm\n' > "${MOCK_RUNNING}"
  # A disabled-module skip line is printed by _compose_opts on stdout.
  echo '{"modules": {"ollama": false}}' > "${SANDBOX}/.devbot.global.jsonc"
  mkdir -p "${SANDBOX}/src/tools/ollama"
  : > "${SANDBOX}/src/tools/ollama/docker-compose.yml"
  _seed_stamp

  _run_is_up

  assert_success
  [ -z "${output}" ]
}

# ── The real dispatch: `bash bin/up.sh --is-up <dir>` ─────────────────────────
# Everything above sources the script with main stripped; these run it as the
# bare `devbot` start does, so a lost flag parse or guard cannot stay green.

_run_is_up_dispatch() {
  run bash "${SANDBOX}/bin/up-full.sh" --is-up "${PROBE_PROJECT}"
}

@test "is-up dispatch: answers 0 on a warm start, prints nothing, starts nothing" {
  printf 'litellm\n' > "${MOCK_DECLARED}"
  printf 'litellm\n' > "${MOCK_RUNNING}"
  _seed_stamp

  _run_is_up_dispatch

  assert_success
  [ -z "${output}" ]
  run cat "${DOCKER_ARGS_FILE}"
  refute_output --partial "up -d"
  refute_output --partial "config --format"
}

@test "is-up dispatch: never creates or takes the up lock" {
  # The probe is the fast path: it must stay lock-free, or a warm start would
  # wait on an in-flight sequence before it could answer.
  printf 'litellm\n' > "${MOCK_DECLARED}"
  printf 'litellm\n' > "${MOCK_RUNNING}"
  _seed_stamp
  [ ! -e "${SANDBOX}/storage/run/up.lock" ]

  _run_is_up_dispatch

  assert_success
  [ ! -e "${SANDBOX}/storage/run/up.lock" ]
}

@test "is-up dispatch: answers 1 when this project has not started here yet" {
  printf 'litellm\n' > "${MOCK_DECLARED}"
  printf 'litellm\n' > "${MOCK_RUNNING}"

  _run_is_up_dispatch

  assert_failure
  [ -z "${output}" ]
  run cat "${DOCKER_ARGS_FILE}"
  refute_output --partial "up -d"
}

@test "is-up: a disabled playwright module neither blocks the stamp nor the probe" {
  # Nothing interpolates the compose file when the module is off, so an unusable
  # PLAYWRIGHT_ROOT is not part of the recorded state. It must still let a stamp
  # through, or every start would look needed again (the round-2 symptom).
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  python3 -c "
import json, sys
path = sys.argv[1]
cfg = {'modules': {'playwright': False}}
with open(path, 'w') as fh:
    json.dump(cfg, fh)
" "${SANDBOX}/.devbot.global.jsonc"

  MOCK_PLAYWRIGHT_ROOT="relative/path" bash -c '
    source "'"${SANDBOX}"'/bin/up.sh"
    PROJECT_DIR="'"${PROBE_PROJECT}"'"
    _write_up_stamp
  '
  # The probe answering 0 IS the assertion: a stamp that was never written
  # could never match, and every launch would run the full up again.

  MOCK_PLAYWRIGHT_ROOT="relative/path" _run_is_up

  assert_success
}

@test "is-up: the probe never persists configuration" {
  # --is-up is a read-only liveness check: persisting a root there would rewrite
  # the global config (and the wiring sha that hashes it) from a probe.
  printf 'mdctx-mcp\n' > "${MOCK_DECLARED}"
  printf 'mdctx-mcp\n' > "${MOCK_RUNNING}"
  _seed_stamp
  export PERSIST_CALLS_FILE="${SANDBOX}/persist.calls"
  : > "${PERSIST_CALLS_FILE}"

  PLAYWRIGHT_ROOT=/home/probe _run_is_up

  assert_success
  run cat "${PERSIST_CALLS_FILE}"
  assert_output ""
}
