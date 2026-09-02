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
  touch "${SANDBOX_DIR}/docker-compose.yml"
  touch "${SANDBOX_DIR}/docker-compose.gpu.yml"
  touch "${SANDBOX_DIR}/src/tools/litellm/docker-compose.yml"

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

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f docker-compose\.gpu\.yml up -d --no-recreate'
  [[ "$output" != *"litellm"* ]]
}

@test "GPU and litellm together" {
  _setup_sandbox '{"gpu_enabled": true}'

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f docker-compose\.yml -f src/tools/litellm/docker-compose\.yml -f docker-compose\.gpu\.yml up -d --no-recreate'
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

# ── External module config rebuild (install.sh parity) ─────────────────────────

_setup_rebuild_sandbox() {
  local json_content="$1"

  mkdir -p "${SANDBOX_DIR}/bin"
  mkdir -p "${SANDBOX_DIR}/src/_shared"
  mkdir -p "${SANDBOX_DIR}/src/tools/external-modules"

  # Strip the main call, then use the stub shared library for helpers.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/up.sh" > "${SANDBOX_DIR}/bin/up.sh"

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

_devbot_get_disabled_modules() {
  local config="${DEV_BOT_ROOT}/.devbot.global.jsonc"
  [[ ! -f "${config}" ]] && echo "[]" && return 0
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
states = data.get('modules', {})
print(json.dumps(sorted(m for m, v in states.items() if v is False)))
" "${config}" 2>/dev/null || echo "[]"
}
HEREDOC

  # Real python support files the rebuild/prune path needs.
  cp "${PROJECT_ROOT}/src/_shared/merge_modules_jsonc.py" "${SANDBOX_DIR}/src/_shared/"
  cp "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX_DIR}/src/_shared/"
  cp "${PROJECT_ROOT}/src/tools/external-modules/functions.sh" "${SANDBOX_DIR}/src/tools/external-modules/"

  printf '%s\n' "${json_content}" > "${SANDBOX_DIR}/.devbot.global.jsonc"
}

@test "rebuild: declares with owner provenance, propagates updates, prunes stale" {
  _setup_rebuild_sandbox '{
    "modules": { "ghostmod": false },
    "external_modules": {
      "existing/mod": { "url": "https://example.com/existing/mod.git", "paths": { "skills": "skills" } },
      "ghost/mod": { "url": "https://example.com/ghost/mod.git", "paths": { "skills": "skills" }, "_declared_by": ["ghostmod"] }
    }
  }'

  # Enabled declarer module.
  mkdir -p "${SANDBOX_DIR}/src/agentic/some-mod"
  cat > "${SANDBOX_DIR}/src/agentic/some-mod/external-modules.json" <<'EOF'
{
  "live/mod": { "url": "https://example.com/live/mod.git", "paths": { "skills": "skills" } },
  "existing/mod": { "url": "https://example.com/existing/mod.git", "paths": { "skills": "skills2", "agents": "agents" } }
}
EOF
  # Disabled declarer module — its declaration must not re-add ghost/mod after prune.
  mkdir -p "${SANDBOX_DIR}/src/agentic/ghostmod"
  cat > "${SANDBOX_DIR}/src/agentic/ghostmod/external-modules.json" <<'EOF'
{
  "ghost/mod": { "url": "https://example.com/ghost/mod.git", "paths": { "skills": "skills" } }
}
EOF

  # shellcheck disable=SC1091
  source "${SANDBOX_DIR}/bin/up.sh"
  run _rebuild_external_module_config

  assert_success
  run python3 -c "
import sys
sys.path.insert(0, '${SANDBOX_DIR}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${SANDBOX_DIR}/.devbot.global.jsonc')
entries = d['external_modules']
# Insert carries owner provenance, not _user_added (parity with install.sh).
assert 'live/mod' in entries, entries
assert entries['live/mod']['_declared_by'] == ['some-mod'], entries['live/mod']
assert '_user_added' not in entries['live/mod'], entries['live/mod']
# Update propagates declaration paths over existing entry.
assert entries['existing/mod']['paths'] == {'skills': 'skills2', 'agents': 'agents'}, entries['existing/mod']
# Prune removes entries whose only declarer is disabled.
assert 'ghost/mod' not in entries, entries
print('ok')
"
  assert_success
  assert_output "ok"
}
