#!/usr/bin/env bats
# =============================================================================
# bin/tests/down_compose_opts_tests.bats
# Tests for _docker_down() compose-opts construction in bin/down.sh.
#
# down.sh mirrors bin/up.sh's consumer-driven discovery: docker services are
# only ever stopped for ENABLED modules (a consumer fragment may `include:` a
# disabled provider's compose, so the same discovery drives down). Validates:
#   - tool compose files discoverable under src/tools
#   - agentic compose fragments (consumer-driven) discovered and added
#   - disabled modules filtered from the compose opts
#   - GPU override appended when gpu_enabled
#   - NO enabled module ships a compose file → down is skipped entirely
#     (mock docker never invoked)
#
# These tests do NOT require a Docker daemon.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_DIR="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"
}

teardown() {
  rm -rf "${SANDBOX_DIR}"
}

# ── Helpers ────────────────────────────────────────────────────────────────

_setup_sandbox() {
  local json_content="$1"

  # Directory structure
  mkdir -p "${SANDBOX_DIR}/bin"
  mkdir -p "${SANDBOX_DIR}/src/_shared"
  mkdir -p "${SANDBOX_DIR}/src/tools/litellm"
  mkdir -p "${SANDBOX_DIR}/src/agentic/codebase-index"
  mkdir -p "${SANDBOX_DIR}/mockbin"

  # Copy production down.sh, strip main call
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/down.sh" > "${SANDBOX_DIR}/bin/down.sh"

  # Stub _shared/functions.sh — all helpers _docker_down calls
  cat > "${SANDBOX_DIR}/src/_shared/functions.sh" <<'HEREDOC'
#!/usr/bin/env bash
_header_1() { true; }
_header_2() { true; }
_header_3() { true; }
_info()  { true; }
_ok()    { true; }
_skip()  { true; }
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
HEREDOC

  # Create .devbot.global.jsonc (production name)
  if [[ -n "${json_content}" ]]; then
    printf '%s\n' "${json_content}" > "${SANDBOX_DIR}/.devbot.global.jsonc"
  else
    echo "{}" > "${SANDBOX_DIR}/.devbot.global.jsonc"
  fi

  # Compose files: root base + GPU override, tool + agentic consumer fragments
  touch "${SANDBOX_DIR}/docker-compose.yml"
  touch "${SANDBOX_DIR}/docker-compose.gpu.yml"
  touch "${SANDBOX_DIR}/src/tools/litellm/docker-compose.yml"
  touch "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.yml"

  # Mock docker
  cat > "${SANDBOX_DIR}/mockbin/docker" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${DOCKER_ARGS_FILE}"
MOCK
  chmod +x "${SANDBOX_DIR}/mockbin/docker"

  export DOCKER_ARGS_FILE="${SANDBOX_DIR}/docker.args"
  : > "${DOCKER_ARGS_FILE}"
  PATH="${SANDBOX_DIR}/mockbin:${PATH}"
}

_run_docker_down() {
  # shellcheck disable=SC1091
  source "${SANDBOX_DIR}/bin/down.sh"
  _docker_down
}

# ── Tests ──────────────────────────────────────────────────────────────────

@test "down stops litellm + codebase-index fragment when both enabled" {
  _setup_sandbox '{}'

  run _run_docker_down

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  # Discovery order is tools → agentic.
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml -f src/agentic/codebase-index/docker-compose\.yml down --remove-orphans'
}

@test "down filters disabled modules from the compose set" {
  _setup_sandbox '{"modules": {"litellm": false, "codebase-index": false}}'

  run _run_docker_down

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml down --remove-orphans'
  [[ "$output" != *"litellm"* ]]
  [[ "$output" != *"codebase-index"* ]]
}

@test "down appends the GPU override when gpu_enabled" {
  _setup_sandbox '{"gpu_enabled": true}'

  run _run_docker_down

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml -f src/agentic/codebase-index/docker-compose\.yml -f docker-compose\.gpu\.yml down --remove-orphans'
}

@test "down skips entirely when no enabled module ships a compose file" {
  # The sandbox fabricates a root docker-compose.yml the real repo lacks —
  # drop it so the empty set is reachable the way production reaches it.
  _setup_sandbox '{"modules": {"litellm": false, "codebase-index": false}}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml"

  run _run_docker_down

  assert_success
  # The mock docker must never have been invoked.
  [ ! -s "${DOCKER_ARGS_FILE}" ]
}
