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

# Mirrors bin/up.sh: the GPU overlay also needs a live passthrough capability.
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
HEREDOC

  # The real GPU-overlay marker parser, extracted verbatim from the shared
  # library, so this stub cannot drift from production behaviour.
  awk '/^_gpu_overlay_skip_if\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh" \
    >> "${SANDBOX_DIR}/src/_shared/functions.sh"

  # Create .devbot.global.jsonc (production name)
  if [[ -n "${json_content}" ]]; then
    printf '%s\n' "${json_content}" > "${SANDBOX_DIR}/.devbot.global.jsonc"
  else
    echo "{}" > "${SANDBOX_DIR}/.devbot.global.jsonc"
  fi

  # Compose files: root base + GPU override, tool + agentic consumer fragments
  # The root base defines the `ollama` service so the GPU overlay (which only
  # overrides `ollama`) is applicable — the overlay is appended only when
  # ollama is actually in the set.
  cat > "${SANDBOX_DIR}/docker-compose.yml" <<'YAML'
name: devbot
services:
  ollama:
    image: ollama/ollama
YAML
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

@test "down appends the GPU override when gpu_enabled and passthrough is available" {
  _setup_sandbox '{"gpu_enabled": true}'
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_down

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  # The GPU overlay follows the compose it overrides (the root base here).
  assert_output --regexp 'compose -f docker-compose\.yml -f docker-compose\.gpu\.yml -f src/tools/litellm/docker-compose\.yml -f src/agentic/codebase-index/docker-compose\.yml down --remove-orphans'
}

@test "down omits the GPU override when gpu_enabled but no passthrough" {
  # Docker Desktop (macOS/Windows) never has passthrough — the persisted flag
  # alone must not append the overlay (mirrors the bin/up.sh gate).
  _setup_sandbox '{"gpu_enabled": true}'
  MOCK_HAS_DOCKER_GPU=no

  run _run_docker_down

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml -f src/agentic/codebase-index/docker-compose\.yml down --remove-orphans'
  [[ "$output" != *"gpu"* ]]
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

@test "down omits the GPU override when ollama is absent from the set" {
  # Mirrors bin/up.sh: the overlay only overrides `ollama`, so appending it
  # when ollama is not in the set makes compose reject the project.
  _setup_sandbox '{"gpu_enabled": true, "modules": {"litellm": false, "codebase-index": false, "ollama": false}}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml"
  mkdir -p "${SANDBOX_DIR}/src/agentic/mdctx"
  touch "${SANDBOX_DIR}/src/agentic/mdctx/docker-compose.yml"
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_down

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f src/agentic/mdctx/docker-compose\.yml down --remove-orphans'
  [[ "$output" != *"gpu"* ]]
}

# ── GPU overlay de-duplication (the skip-if-included marker) ────────────────

@test "down skips a consumer GPU overlay when the compose it stands in for is in the set" {
  # Kept in step with bin/up.sh (review F10): up and down must select the same
  # compose set, or down operates on a different project than up created.
  _setup_sandbox '{"gpu_enabled": true, "modules": {"litellm": false}}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml" "${SANDBOX_DIR}/docker-compose.gpu.yml"

  mkdir -p "${SANDBOX_DIR}/src/tools/ollama"
  cat > "${SANDBOX_DIR}/src/tools/ollama/docker-compose.yml" <<'YAML'
name: devbot
services:
  ollama:
    image: ollama/ollama
YAML
  cat > "${SANDBOX_DIR}/src/tools/ollama/docker-compose.gpu.yml" <<'YAML'
name: devbot
services:
  ollama:
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
YAML

  mkdir -p "${SANDBOX_DIR}/src/agentic/codebase-index"
  cat > "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.yml" <<'YAML'
name: devbot
include:
  - ${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml
YAML
  cat > "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.gpu.yml" <<'YAML'
# devbot:gpu-overlay-skip-if-included src/tools/ollama/docker-compose.yml
name: devbot
include:
  - ${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.gpu.yml
YAML
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_down

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial '-f src/tools/ollama/docker-compose.gpu.yml'
  [[ "$output" != *"src/agentic/codebase-index/docker-compose.gpu.yml"* ]] \
    || fail "consumer GPU overlay was applied on top of the provider's"
}

@test "down still applies a consumer GPU overlay when the provider's module is disabled" {
  _setup_sandbox '{"gpu_enabled": true, "modules": {"litellm": false, "ollama": false}}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml" "${SANDBOX_DIR}/docker-compose.gpu.yml"

  mkdir -p "${SANDBOX_DIR}/src/tools/ollama"
  cat > "${SANDBOX_DIR}/src/tools/ollama/docker-compose.yml" <<'YAML'
name: devbot
services:
  ollama:
    image: ollama/ollama
YAML
  mkdir -p "${SANDBOX_DIR}/src/agentic/codebase-index"
  cat > "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.yml" <<'YAML'
name: devbot
include:
  - ${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml
YAML
  cat > "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.gpu.yml" <<'YAML'
# devbot:gpu-overlay-skip-if-included src/tools/ollama/docker-compose.yml
name: devbot
include:
  - ${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.gpu.yml
YAML
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_down

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial '-f src/agentic/codebase-index/docker-compose.gpu.yml'
}

# ── Guards: no daemon, and missing global config ─────────────────────────────

@test "down skips cleanly (no compose call) when there is no docker daemon" {
  _setup_sandbox '{}'
  # Override the mock: \`docker info\` fails (as inside a container).
  cat > "${SANDBOX_DIR}/mockbin/docker" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "info" ]]; then exit 1; fi
echo "$@" >> "${DOCKER_ARGS_FILE}"
MOCK
  chmod +x "${SANDBOX_DIR}/mockbin/docker"

  run _run_docker_down
  assert_success
  # The daemon guard skipped before any `docker compose down` call.
  [ ! -s "${DOCKER_ARGS_FILE}" ]
}

@test "down reports missing global config even when no compose files exist" {
  _setup_sandbox '{}'
  rm -f "${SANDBOX_DIR}/.devbot.global.jsonc"
  rm -f "${SANDBOX_DIR}/docker-compose.yml"
  rm -f "${SANDBOX_DIR}/src/tools/litellm/docker-compose.yml"
  rm -f "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.yml"

  run _run_docker_down
  assert_failure
  assert_output --partial "No .devbot.global.jsonc found"
}
