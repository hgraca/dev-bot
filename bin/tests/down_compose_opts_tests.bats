#!/usr/bin/env bats
# =============================================================================
# bin/tests/down_compose_opts_tests.bats
# Tests for bin/down.sh — the machine-wide dev-bot container removal.
#
# down is NOT project-scoped: every module's services share the install-level
# compose project `devbot`, so removal is machine-wide and gated on the live
# session count. Validates:
#   - EVERY module compose is selected, including disabled modules
#   - no GPU overlays (down needs no device reservations)
#   - the root compose is selected first when one exists
#   - the lifetime gate: containers kept while any devbot instance is alive
#   - the gate runs BEFORE the module down-scripts (playwright is per-instance)
#   - module down-scripts run with --all, even with no compose files to stop
#   - no daemon and missing global config guards
#
# These tests do NOT require a Docker daemon.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "${SANDBOX_DIR}"
}

# ── Helpers ────────────────────────────────────────────────────────────────

_setup_sandbox() {
  local json_content="$1"

  # Per-test isolation for the gate inputs.
  unset MOCK_LIVE_SESSIONS MOCK_SESSIONS_DIR _DEVBOT_REGISTRY_LOCK_HELD 2>/dev/null || true

  # Directory structure
  mkdir -p "${SANDBOX_DIR}/bin"
  mkdir -p "${SANDBOX_DIR}/src/_shared"
  mkdir -p "${SANDBOX_DIR}/src/tools/litellm"
  mkdir -p "${SANDBOX_DIR}/src/agentic/codebase-index"
  mkdir -p "${SANDBOX_DIR}/mockbin"

  # Copy production down.sh, strip the `main "$@"` INVOCATION (the `main()`
  # definition is kept so tests can drive the real gate ordering).
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/down.sh" > "${SANDBOX_DIR}/bin/down.sh"

  # Stub _shared/functions.sh — only what down.sh actually calls. Note what is
  # ABSENT: no _devbot_get_disabled_modules, no _devbot_is_true, no
  # _has_docker_gpu, no _gpu_overlay_skip_if. down.sh must not depend on the
  # per-project config filter or on GPU capability.
  cat > "${SANDBOX_DIR}/src/_shared/functions.sh" <<'HEREDOC'
#!/usr/bin/env bash
_header_1() { true; }
_header_2() { true; }
_header_3() { true; }
_info()  { true; }
_ok()    { true; }
_skip()  { true; }
_warn()  { echo "WARN: $*" >&2; }
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

# The machine-wide lifetime gate reads this. Tests drive it via
# MOCK_LIVE_SESSIONS (default 0 → safe to remove).
_devbot_live_session_count() { echo "${MOCK_LIVE_SESSIONS:-0}"; }

_devbot_sessions_dir() { echo "${MOCK_SESSIONS_DIR:-/tmp/devbot-sessions-mock}"; }

# The real lock primitive is exercised in devbot_sessions_tests.bats; here we
# only pin WHERE the gate takes the lock (and that it never re-takes it when
# the caller already holds it — that would deadlock).
_devbot_lock_wait() { echo "lock-wait $*" >> "${LOCK_ARGS_FILE}"; return 0; }

# Module down-scripts: record the invocation so tests can pin the --all flag
# and prove the gate ordering.
_run_service_scripts() { echo "service-scripts $*" >> "${SCRIPTS_ARGS_FILE}"; }
HEREDOC

  # Create .devbot.global.jsonc (production name)
  if [[ -n "${json_content}" ]]; then
    printf '%s\n' "${json_content}" > "${SANDBOX_DIR}/.devbot.global.jsonc"
  else
    echo "{}" > "${SANDBOX_DIR}/.devbot.global.jsonc"
  fi

  # Compose files: root base + a tool + an agentic fragment. The root base
  # defines a service so it is a realistic member of the project.
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
  export SCRIPTS_ARGS_FILE="${SANDBOX_DIR}/scripts.args"
  export LOCK_ARGS_FILE="${SANDBOX_DIR}/lock.args"
  : > "${DOCKER_ARGS_FILE}"
  : > "${SCRIPTS_ARGS_FILE}"
  : > "${LOCK_ARGS_FILE}"
  PATH="${SANDBOX_DIR}/mockbin:${PATH}"
}

_run_docker_down() {
  # shellcheck disable=SC1091
  source "${SANDBOX_DIR}/bin/down.sh"
  _docker_down
}

_run_down_main() {
  # Drives the real main(): gate → module down-scripts → compose removal.
  # shellcheck disable=SC1091
  source "${SANDBOX_DIR}/bin/down.sh"
  main
}

# ── Compose selection: machine-wide, config-independent ────────────────────

@test "down selects every module compose, including disabled ones" {
  # The disabled set is a PER-PROJECT view; removal is machine-wide, so a
  # module disabled here may still own a container (signoz enabled elsewhere).
  _setup_sandbox '{"modules": {"litellm": false, "codebase-index": false}}'

  run _run_docker_down

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  # Root compose first, then tools, then agentic.
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml -f src/agentic/codebase-index/docker-compose\.yml down --remove-orphans'
}

@test "down never appends a GPU overlay" {
  # `down` needs no device reservations — the up.sh overlay machinery has no
  # counterpart here. The stub defines no GPU helpers at all, so this also pins
  # that `down` does not consult GPU state, gpu_enabled notwithstanding.
  _setup_sandbox '{"gpu_enabled": true}'
  touch "${SANDBOX_DIR}/src/tools/litellm/docker-compose.gpu.yml"

  run _run_docker_down

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial '-f src/tools/litellm/docker-compose.yml'
  [[ "$output" != *"gpu"* ]] || fail "down appended a GPU overlay"
}

@test "down skips the compose call when no compose files exist" {
  _setup_sandbox '{}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml" "${SANDBOX_DIR}/docker-compose.gpu.yml" \
    "${SANDBOX_DIR}/src/tools/litellm/docker-compose.yml" \
    "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.yml"

  run _run_docker_down

  assert_success
  # No `docker compose down` call. (`docker info` is never reached either — the
  # empty-set guard returns before the daemon check.)
  [ ! -s "${DOCKER_ARGS_FILE}" ]
}

# ── Lifetime gate ──────────────────────────────────────────────────────────

@test "down keeps all containers while another devbot instance is alive" {
  _setup_sandbox '{}'
  MOCK_LIVE_SESSIONS=2

  run _run_down_main

  assert_success
  assert_output --partial "2 devbot instance(s) still running — containers kept"
  # Nothing removed, and the module down-scripts never ran either.
  [ ! -s "${DOCKER_ARGS_FILE}" ]
  [ ! -s "${SCRIPTS_ARGS_FILE}" ]
}

@test "down removes containers when no devbot instance is alive" {
  _setup_sandbox '{}'
  MOCK_LIVE_SESSIONS=0

  run _run_down_main

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial 'down --remove-orphans'
}

@test "down takes the registry lock before deciding (atomic gate)" {
  # The probe and the removal must not straddle the lock release, or a session
  # registering in the window has its containers removed underneath it.
  _setup_sandbox '{}'
  MOCK_LIVE_SESSIONS=0

  run _run_down_main

  assert_success
  run cat "${LOCK_ARGS_FILE}"
  assert_output --partial 'lock-wait'
}

@test "down does not re-lock when the teardown already holds the registry lock" {
  # _devbot_session_teardown invokes down.sh from inside its critical section;
  # a second flock on the same directory would block forever.
  _setup_sandbox '{}'
  MOCK_LIVE_SESSIONS=0
  export _DEVBOT_REGISTRY_LOCK_HELD=1

  run _run_down_main

  assert_success
  [ ! -s "${LOCK_ARGS_FILE}" ]
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial 'down --remove-orphans'
}

@test "down runs module down-scripts with --all" {
  # A module disabled here may still own a NON-compose container (playwright
  # reaps its own by label). The unfiltered run is what collects it.
  _setup_sandbox '{}'

  run _run_down_main

  assert_success
  run cat "${SCRIPTS_ARGS_FILE}"
  assert_output --partial 'service-scripts --all down.sh'
}

@test "down still runs module down-scripts when no compose files exist" {
  # The reapers (playwright) must run even when compose has nothing to stop.
  _setup_sandbox '{}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml" "${SANDBOX_DIR}/docker-compose.gpu.yml" \
    "${SANDBOX_DIR}/src/tools/litellm/docker-compose.yml" \
    "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.yml"

  run _run_down_main

  assert_success
  [ ! -s "${DOCKER_ARGS_FILE}" ]
  run cat "${SCRIPTS_ARGS_FILE}"
  assert_output --partial '--all'
}

# ── Guards: no daemon, and missing global config ─────────────────────────────

@test "down skips cleanly (no compose call) when there is no docker daemon" {
  _setup_sandbox '{}'
  # Override the mock: `docker info` fails (as inside a container).
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
