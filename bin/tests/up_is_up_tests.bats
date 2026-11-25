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

_devbot_load_env_file() { return 0; }
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

@test "is-up dispatch: answers 1 when this project has not started here yet" {
  printf 'litellm\n' > "${MOCK_DECLARED}"
  printf 'litellm\n' > "${MOCK_RUNNING}"

  _run_is_up_dispatch

  assert_failure
  [ -z "${output}" ]
  run cat "${DOCKER_ARGS_FILE}"
  refute_output --partial "up -d"
}
