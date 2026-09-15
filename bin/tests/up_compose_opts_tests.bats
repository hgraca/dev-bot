#!/usr/bin/env bats
# =============================================================================
# bin/tests/up_compose_opts_tests.bats
# Tests for _docker_up() compose_opts construction in bin/up.sh.
#
# Validates that:
#   - -f docker-compose.yml is ALWAYS the first element (if root compose exists)
#   - Tool compose files (e.g. litellm) discoverable under src/tools/
#   - Disabled modules are filtered from compose opts
#   - GPU override appended conditionally after base + tool composes
#   - Missing .devbot.global.jsonc produces error exit
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
  mkdir -p "${SANDBOX_DIR}/mockbin"

  # Copy production up.sh, strip main call
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/up.sh" > "${SANDBOX_DIR}/bin/up.sh"

  # Stub _shared/functions.sh — all helpers _docker_up calls
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

# Container GPU passthrough is a LIVE capability probe — a persisted
# gpu_enabled that no longer matches the host must not gate the overlay.
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

  # Create .devbot.global.jsonc (production name)
  if [[ -n "${json_content}" ]]; then
    printf '%s\n' "${json_content}" > "${SANDBOX_DIR}/.devbot.global.jsonc"
  else
    echo "{}" > "${SANDBOX_DIR}/.devbot.global.jsonc"
  fi

  # Compose files: root base + GPU override, tool-specific under src/tools/
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

  # Mock docker — records every invocation; `ps -a` answers from a fixture file
  # of "ID|NAME|PROJECT" rows (empty unless a test seeds a stale container).
  export STALE_CONTAINERS_FILE="${SANDBOX_DIR}/stale-containers"
  : > "${STALE_CONTAINERS_FILE}"
  cat > "${SANDBOX_DIR}/mockbin/docker" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${DOCKER_ARGS_FILE}"
if [[ "$1" == "ps" ]]; then
  has_all=0
  for a in "$@"; do [[ "$a" == "-a" ]] && has_all=1; done
  [[ "${has_all}" -eq 1 && -s "${STALE_CONTAINERS_FILE}" ]] && cat "${STALE_CONTAINERS_FILE}"
  exit 0
fi
exit 0
MOCK
  chmod +x "${SANDBOX_DIR}/mockbin/docker"

  export DOCKER_ARGS_FILE="${SANDBOX_DIR}/docker.args"
  : > "${DOCKER_ARGS_FILE}"
  PATH="${SANDBOX_DIR}/mockbin:${PATH}"
}

# Seed the containers `docker ps -a` reports, as "ID|NAME|PROJECT" rows.
_seed_container() {
  printf '%s\n' "$1" >> "${STALE_CONTAINERS_FILE}"
}

_run_docker_up() {
  # shellcheck disable=SC1091
  source "${SANDBOX_DIR}/bin/up.sh"
  _docker_up
}

# ── Tests ──────────────────────────────────────────────────────────────────

@test "litellm included by default (no disabled_modules)" {
  _setup_sandbox '{}'

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml up -d --no-recreate'
}

@test "litellm excluded when in disabled_modules" {
  _setup_sandbox '{"modules": {"litellm": false}}'

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml up -d --no-recreate'
  [[ "$output" != *"litellm"* ]]
}

@test "litellm still included when disabled_modules has other entries" {
  _setup_sandbox '{"modules": {"graphify": false}}'

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml up -d --no-recreate'
}

@test "GPU enabled — base compose first, then GPU override" {
  _setup_sandbox '{"gpu_enabled": true, "modules": {"litellm": false}}'
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f docker-compose\.gpu\.yml up -d --no-recreate'
  [[ "$output" != *"litellm"* ]]
}

@test "GPU and litellm together" {
  _setup_sandbox '{"gpu_enabled": true}'
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml -f docker-compose\.gpu\.yml up -d --no-recreate'
}

@test "GPU enabled but no container passthrough — no overlay (Docker Desktop macOS)" {
  # gpu_enabled is a persisted intent; the overlay must ALSO require a live
  # _has_docker_gpu. On Docker Desktop (macOS/Windows) passthrough is never
  # available, so a stale/over-eager gpu_enabled=true must not append the
  # device reservation — docker compose would fail and abort the whole start.
  _setup_sandbox '{"gpu_enabled": true, "modules": {"litellm": false}}'
  MOCK_HAS_DOCKER_GPU=no

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml up -d --no-recreate'
  [[ "$output" != *"gpu"* ]]
}

@test "GPU false and litellm disabled — base only" {
  _setup_sandbox '{"gpu_enabled": false, "modules": {"litellm": false}}'

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml up -d --no-recreate'
  [[ "$output" != *"gpu"* ]]
  [[ "$output" != *"litellm"* ]]
}

@test "neither flag set — base + litellm" {
  _setup_sandbox '{"some_other_var": "hello"}'

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml up -d --no-recreate'
  [[ "$output" != *"gpu"* ]]
}

@test "empty config — base + litellm" {
  _setup_sandbox ''

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml up -d --no-recreate'
}

@test "missing .devbot.global.jsonc prints error and exits 1" {
  _setup_sandbox ""
  rm -f "${SANDBOX_DIR}/.devbot.global.jsonc"

  run _run_docker_up

  assert_failure
  assert_output --partial "No .devbot.global.jsonc found"
}

# ── Docker service discovery: consumer-driven (compose fragments) ────────────
# Since v1.4, docker services start only when an ENABLED module needs them:
# provider composes (ollama, litellm) are discovered across src/tools +
# src/agentic + src/harnesses; a module disabled in the `modules` map has its
# compose excluded. A consumer module that needs a service ships its own
# docker-compose.yml fragment that `include:`s the provider's compose — so an
# enabled consumer boots the provider even when the provider module is
# disabled. If NO enabled module ships a compose file, the docker section is
# skipped entirely (no `docker compose` invocation).

@test "agentic module compose fragment is discovered and added" {
  mkdir -p "${SANDBOX_DIR}/src/agentic/codebase-index"
  touch "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.yml"

  _setup_sandbox '{}'

  run _run_docker_up
  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  # Discovery order is tools → agentic, so litellm (tools) precedes the
  # codebase-index fragment (agentic).
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml -f src/agentic/codebase-index/docker-compose\.yml up -d --no-recreate'
}

@test "disabled agentic module compose is excluded" {
  mkdir -p "${SANDBOX_DIR}/src/agentic/codebase-index"
  touch "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.yml"

  _setup_sandbox '{"modules": {"codebase-index": false}}'

  run _run_docker_up
  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml up -d --no-recreate'
  [[ "$output" != *"codebase-index"* ]]
}

@test "no enabled module ships a compose file — docker section is skipped entirely" {
  # All provider modules disabled and no consumer fragments → nothing to start.
  # The sandbox fabricates a root docker-compose.yml the real repo lacks
  # (only docker-compose.gpu.yml exists there) — drop it so the empty set is
  # reachable the way production reaches it.
  _setup_sandbox '{"modules": {"litellm": false, "ollama": false}}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml"

  run _run_docker_up
  assert_success
  # The mock docker must never have been invoked.
  [ ! -s "${DOCKER_ARGS_FILE}" ]
}

@test "GPU enabled but ollama absent from the set — no overlay (invalid project guard)" {
  # ollama disabled while another module (mdctx) ships a compose fragment: the
  # GPU overlay only overrides `ollama`, so appending it makes compose reject
  # the whole project — "service ollama has neither an image nor a build
  # context specified: invalid compose project".
  _setup_sandbox '{"gpu_enabled": true, "modules": {"litellm": false, "ollama": false}}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml"
  mkdir -p "${SANDBOX_DIR}/src/agentic/mdctx"
  touch "${SANDBOX_DIR}/src/agentic/mdctx/docker-compose.yml"
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f src/agentic/mdctx/docker-compose\.yml up -d --no-recreate'
  [[ "$output" != *"gpu"* ]]
}

@test "GPU overlay appended when a consumer fragment includes ollama" {
  # codebase-index's fragment `include:`s ollama's compose, so ollama IS in the
  # set even though the ollama module is disabled — the overlay is valid.
  _setup_sandbox '{"gpu_enabled": true, "modules": {"litellm": false, "ollama": false}}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml"
  mkdir -p "${SANDBOX_DIR}/src/agentic/codebase-index"
  cat > "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.yml" <<'YAML'
name: devbot
include:
  - ${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml
YAML
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f src/agentic/codebase-index/docker-compose\.yml -f docker-compose\.gpu\.yml up -d --no-recreate'
}

# ── Stale container-name reclaim ─────────────────────────────────────────────
# Every dev-bot container declares a fixed `container_name` in the `dev-bot-*`
# namespace. A container created under a DIFFERENT compose project (e.g. the
# retired `dev-bot` project, renamed to `devbot` in 6cced698) is not a member of
# `devbot`, so `down --remove-orphans` never removes it — and its fixed name
# makes `docker compose up` fail with "Conflict. The container name ... is
# already in use". _docker_up must remove such containers first.

@test "stale container from a foreign compose project is removed before up" {
  _setup_sandbox '{"modules": {"litellm": false}}'
  _seed_container 'acc7b95dfc16|dev-bot-ollama|dev-bot'

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial 'rm -f acc7b95dfc16'
  # ...and the compose up still runs afterwards.
  assert_output --regexp 'compose -f docker-compose\.yml up -d --no-recreate'
}

@test "container already owned by project devbot is left alone" {
  _setup_sandbox '{"modules": {"litellm": false}}'
  _seed_container 'acc7b95dfc16|dev-bot-ollama|devbot'

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  refute_output --partial 'rm -f'
}

@test "container with no compose project label (manual run) is removed" {
  _setup_sandbox '{"modules": {"litellm": false}}'
  _seed_container 'acc7b95dfc16|dev-bot-ollama|'

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial 'rm -f acc7b95dfc16'
}

@test "a container outside the dev-bot- namespace is never removed" {
  _setup_sandbox '{"modules": {"litellm": false}}'
  _seed_container 'deadbeefcafe|some-other-project|dev-bot'

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  refute_output --partial 'rm -f'
}
