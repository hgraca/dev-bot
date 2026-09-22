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
  # Holds the image id `docker image inspect` reports. Empty = image absent.
  # A `build` with MOCK_REBUILD_CHANGES_ID=yes rewrites it, emulating a rebuild
  # that actually produced new layers.
  export IMAGE_ID_FILE="${SANDBOX_DIR}/image-id"
  : > "${IMAGE_ID_FILE}"
  cat > "${SANDBOX_DIR}/mockbin/docker" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${DOCKER_ARGS_FILE}"
if [[ "$1" == "ps" ]]; then
  has_all=0
  for a in "$@"; do [[ "$a" == "-a" ]] && has_all=1; done
  [[ "${has_all}" -eq 1 && -s "${STALE_CONTAINERS_FILE}" ]] && cat "${STALE_CONTAINERS_FILE}"
  exit 0
fi
if [[ "$1" == "image" && "$2" == "inspect" ]]; then
  cat "${IMAGE_ID_FILE}" 2>/dev/null || true
  exit 0
fi
if [[ "$1" == "compose" ]]; then
  case " $* " in
    *" build "*)
      [[ "${MOCK_REBUILD_CHANGES_ID:-no}" == "yes" ]] && echo "sha256:rebuilt" > "${IMAGE_ID_FILE}"
      ;;
  esac
  # `config --format json` answers from ${MOCK_COMPOSE_CONFIG_FILE} (nothing
  # when unset); ${MOCK_COMPOSE_CONFIG_RC} forces a resolution failure.
  case " $* " in
    *" config "*)
      if [[ -n "${MOCK_COMPOSE_CONFIG_RC:-}" ]]; then
        exit "${MOCK_COMPOSE_CONFIG_RC}"
      fi
      if [[ -n "${MOCK_COMPOSE_CONFIG_FILE:-}" && -f "${MOCK_COMPOSE_CONFIG_FILE}" ]]; then
        cat "${MOCK_COMPOSE_CONFIG_FILE}"
      fi
      exit 0
      ;;
  esac
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

# Seed the model `docker compose config --format json` answers with, as
# "SOURCE|rw" / "SOURCE|ro" rows — one service, one bind mount each.
_seed_compose_model() {
  local row source ro vols=""
  for row in "$@"; do
    source="${row%%|*}"
    ro=false
    [[ "${row##*|}" == "ro" ]] && ro=true
    vols="${vols}${vols:+, }{\"type\": \"bind\", \"source\": \"${source}\", \"target\": \"/t\", \"read_only\": ${ro}}"
  done
  MOCK_COMPOSE_CONFIG_FILE="${SANDBOX_DIR}/compose-model.json"
  printf '{"services": {"svc": {"volumes": [%s]}}}\n' "${vols}" > "${MOCK_COMPOSE_CONFIG_FILE}"
  export MOCK_COMPOSE_CONFIG_FILE
}

# Run the bind-source pre-create the way main() does.
_run_ensure_sources() {
  # shellcheck disable=SC1091
  source "${SANDBOX_DIR}/bin/up.sh"
  _ensure_writable_bind_sources
}

# Swap the sandbox stub of _devbot_get_disabled_modules for the REAL
# implementation, extracted verbatim from the shared library together with the
# two provider helpers it calls and the JSONC reader they resolve beside
# functions.sh.
#
# The stub reads only the global modules map, so it accepts a project_dir
# argument and ignores it — which makes it structurally incapable of observing
# whether the caller passed one. Appended after the stub, these definitions win.
_use_real_disabled_modules() {
  cp "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX_DIR}/src/_shared/read_jsonc.py"
  {
    awk '/^_devbot_get_codebase_provider\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_get_memory_search_provider\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_get_disabled_modules\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
  } >> "${SANDBOX_DIR}/src/_shared/functions.sh"
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
  # The GPU overlay follows the compose it overrides (the root base here).
  assert_output --regexp 'compose -f docker-compose\.yml -f docker-compose\.gpu\.yml -f src/tools/litellm/docker-compose\.yml up -d --no-recreate'
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

@test "per-project module enable overrides a global disable — compose is started" {
  # Regression: _docker_up must resolve disabled modules WITH the project dir.
  # Calling _devbot_get_disabled_modules with no argument reads only the global
  # modules map, so a module that is false globally and true per-project — which
  # is exactly how `signoz` is configured — had its compose silently excluded
  # from every `devbot up`, no matter which directory it ran in.
  mkdir -p "${SANDBOX_DIR}/src/agentic/signoz"
  touch "${SANDBOX_DIR}/src/agentic/signoz/docker-compose.yml"
  _setup_sandbox '{"modules": {"litellm": false, "signoz": false}}'
  printf '%s\n' '{"modules": {"signoz": true}}' > "${SANDBOX_DIR}/.devbot.project.jsonc"
  _use_real_disabled_modules
  cd "${SANDBOX_DIR}"

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial 'src/agentic/signoz/docker-compose.yml'
}

@test "per-project module enable is not honoured for a module left disabled in both" {
  # The complement: honouring the project override must not degenerate into
  # "always enabled". A module false globally and absent from the project stays
  # disabled.
  mkdir -p "${SANDBOX_DIR}/src/agentic/signoz"
  touch "${SANDBOX_DIR}/src/agentic/signoz/docker-compose.yml"
  _setup_sandbox '{"modules": {"litellm": false, "signoz": false}}'
  printf '%s\n' '{"modules": {"mdctx": true}}' > "${SANDBOX_DIR}/.devbot.project.jsonc"
  _use_real_disabled_modules
  cd "${SANDBOX_DIR}"

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  [[ "$output" != *"signoz"* ]] || fail "globally-disabled signoz compose was started"
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

@test "GPU overlay follows a consumer fragment that ships its own" {
  # codebase-index runs no container of its own — it needs ollama — so it ships
  # a docker-compose.gpu.yml that `include:`s ollama's. The overlay is appended
  # right after the fragment it belongs to, and only when GPU is available.
  _setup_sandbox '{"gpu_enabled": true, "modules": {"litellm": false, "ollama": false}}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml"
  mkdir -p "${SANDBOX_DIR}/src/agentic/codebase-index"
  cat > "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.yml" <<'YAML'
name: devbot
include:
  - ${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml
YAML
  cat > "${SANDBOX_DIR}/src/agentic/codebase-index/docker-compose.gpu.yml" <<'YAML'
name: devbot
include:
  - ${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.gpu.yml
YAML
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --regexp 'compose -f src/agentic/codebase-index/docker-compose\.yml -f src/agentic/codebase-index/docker-compose\.gpu\.yml up -d --no-recreate'
}

@test "a module's GPU overlay is omitted when the module ships none" {
  # mdctx ships a compose but no GPU overlay — nothing to append.
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

# ── GPU overlay de-duplication (the skip-if-included marker) ────────────────

# Lay out a provider (ollama) with its own GPU overlay, plus a consumer fragment
# whose GPU overlay carries the skip marker pointing at the provider's compose.
_setup_provider_and_consumer() {
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
}

@test "GPU: consumer overlay is skipped when the compose it stands in for is already in the set" {
  # Review F10. codebase-index's GPU overlay exists only to cover the case where
  # the ollama MODULE is disabled. With ollama enabled its own overlay is
  # applied directly and the consumer's would merge the same device reservation
  # twice (docker compose config then shows two identical capabilities: [gpu]).
  _setup_sandbox '{"gpu_enabled": true, "modules": {"litellm": false}}'
  _setup_provider_and_consumer
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  # The provider's overlay IS applied...
  assert_output --partial '-f src/tools/ollama/docker-compose.gpu.yml'
  # ...and the consumer's is skipped.
  [[ "$output" != *"src/agentic/codebase-index/docker-compose.gpu.yml"* ]] \
    || fail "consumer GPU overlay was applied on top of the provider's"
}

@test "GPU: consumer overlay is still applied when the provider's module is disabled" {
  # The complement — the marker must not over-skip. With ollama disabled, its
  # overlay is absent and the consumer's include is the only thing that gives
  # the ollama it pulls in its GPU.
  _setup_sandbox '{"gpu_enabled": true, "modules": {"litellm": false, "ollama": false}}'
  _setup_provider_and_consumer
  MOCK_HAS_DOCKER_GPU=yes

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial '-f src/agentic/codebase-index/docker-compose.gpu.yml'
}

@test "GPU: _gpu_overlay_skip_if reads the marker and ignores unmarked overlays" {
  # Source _shared/functions.sh, NOT bin/up.sh — sourcing the latter runs its
  # trailing `main \"$@\"` and would invoke a real `devbot up`.
  local overlay
  overlay="$(mktemp)"
  printf '# devbot:gpu-overlay-skip-if-included src/tools/ollama/docker-compose.yml\nname: devbot\n' > "${overlay}"
  run bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; _gpu_overlay_skip_if '${overlay}'"
  assert_success
  assert_output 'src/tools/ollama/docker-compose.yml'

  printf 'name: devbot\nservices:\n  ollama: {}\n' > "${overlay}"
  run bash -c "source '${PROJECT_ROOT}/src/_shared/functions.sh'; _gpu_overlay_skip_if '${overlay}'"
  assert_success
  assert_output ''
  rm -f "${overlay}"
}

# ── Rebuilding module images whose build input changed ───────────────────────
# A `build:` service is only built when its image is MISSING, and --no-recreate
# never applies a new image to a running container — so a Dockerfile edit used to
# have no effect until someone deleted the image by hand.

# A compose with a `build:` section, and the image id it currently has.
_setup_buildable_module() {
  rm -f "${SANDBOX_DIR}/docker-compose.yml"
  mkdir -p "${SANDBOX_DIR}/src/agentic/mdctx"
  cat > "${SANDBOX_DIR}/src/agentic/mdctx/docker-compose.yml" <<'YAML'
name: devbot
services:
  mdctx-mcp:
    build:
      context: .
    image: dev-bot-mdctx-mcp:local
YAML
  echo "sha256:original" > "${IMAGE_ID_FILE}"
}

@test "image rebuild: a module whose image changed is rebuilt and recreated" {
  _setup_sandbox '{"gpu_enabled": false, "modules": {"litellm": false}}'
  _setup_buildable_module
  # Exported: the mock docker is a child process, so it reads this from the env
  # (unlike MOCK_HAS_DOCKER_GPU, which a stubbed shell function reads in-process).
  export MOCK_REBUILD_CHANGES_ID=yes

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial 'src/agentic/mdctx/docker-compose.yml build'
  assert_output --partial 'docker-compose.yml up -d --force-recreate'
}

@test "image rebuild: an unchanged image does NOT recreate the container" {
  _setup_sandbox '{"gpu_enabled": false, "modules": {"litellm": false}}'
  _setup_buildable_module
  # Warm cache: the build runs but yields the same image id.
  MOCK_REBUILD_CHANGES_ID=no

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  assert_output --partial 'src/agentic/mdctx/docker-compose.yml build'
  [[ "$output" != *'force-recreate'* ]] \
    || fail "container was recreated even though the image did not change"
}

@test "image rebuild: a module that only references a published image is never built" {
  _setup_sandbox '{"gpu_enabled": false, "modules": {"litellm": false}}'
  rm -f "${SANDBOX_DIR}/docker-compose.yml"
  mkdir -p "${SANDBOX_DIR}/src/agentic/signoz"
  cat > "${SANDBOX_DIR}/src/agentic/signoz/docker-compose.yml" <<'YAML'
name: devbot
services:
  signoz-mcp:
    image: signoz/signoz-mcp-server:v0.14.0
YAML
  echo "sha256:original" > "${IMAGE_ID_FILE}"

  run _run_docker_up

  assert_success
  run cat "${DOCKER_ARGS_FILE}"
  [[ "$output" != *"build"* ]] || fail "an image-only module was rebuilt"
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

# ── Repo .env loading (compose interpolation) ──────────────────────────────
# Review F2: compose interpolation reads the PROJECT directory's .env. With a
# module-first -f list that is the module dir, not the repo root, so a var like
# ${SIGNOZ_AUTH_TOKEN} silently interpolated to empty. _load_env_file closes it.

@test ".env is loaded into the environment before compose runs" {
  _setup_sandbox '{}'
  printf 'SIGNOZ_AUTH_TOKEN=from-dotenv\n' > "${SANDBOX_DIR}/.env"

  # env -u: the ambient shell may already export SIGNOZ_AUTH_TOKEN, which would
  # otherwise mask whether the .env was actually read.
  run env -u SIGNOZ_AUTH_TOKEN bash -c "
    source '${SANDBOX_DIR}/bin/up.sh'
    _load_env_file
    echo \"resolved=\${SIGNOZ_AUTH_TOKEN:-UNSET}\"
  "

  assert_success
  assert_output --partial 'resolved=from-dotenv'
}

@test "a missing .env is tolerated (no error, nothing exported)" {
  _setup_sandbox '{}'
  rm -f "${SANDBOX_DIR}/.env"

  run env -u SIGNOZ_AUTH_TOKEN bash -c "
    source '${SANDBOX_DIR}/bin/up.sh'
    _load_env_file
    echo \"resolved=\${SIGNOZ_AUTH_TOKEN:-UNSET}\"
  "

  assert_success
  assert_output --partial 'resolved=UNSET'
}

@test "_docker_up is preceded by the .env load in main()" {
  # Guards the call site, not just the helper: a defined-but-never-called
  # _load_env_file would leave interpolation broken.
  run grep -A6 '^main()' "${PROJECT_ROOT}/bin/up.sh"
  assert_success
  assert_output --partial '_load_env_file'
}

# ── Writable bind-mount sources ────────────────────────────────────────────────
# Docker creates a missing bind-mount SOURCE on the host as root:root. A module
# service that runs as the host uid (e.g. mdctx-mcp) then finds
# its own state dir owned by root and refuses to start — a fresh-machine failure
# that never shows where the dir already exists (an existing image/dir means
# nobody looks). `_ensure_writable_bind_sources` creates the WRITABLE sources as
# the host user before compose can get there. READ-ONLY sources are deliberately
# left alone: a missing one is a misconfiguration (the module would read an empty
# dir), so it must fail loudly rather than be fabricated.

@test "a missing writable bind source is created 0700 before compose runs" {
  _setup_sandbox '{}'
  local missing="${SANDBOX_DIR}/state/writable"
  _seed_compose_model "${missing}|rw"

  run _run_ensure_sources

  assert_success
  [ -d "${missing}" ] || fail "writable bind source was not created"
  assert_equal "$(ls -ld "${missing}" | awk '{print $1}')" "drwx------"
}

@test "an existing bind source keeps its mode and contents" {
  _setup_sandbox '{}'
  local existing="${SANDBOX_DIR}/state/existing"
  mkdir -p -m 755 "${existing}"
  : > "${existing}/keep"
  _seed_compose_model "${existing}|rw"

  run _run_ensure_sources

  assert_success
  assert_equal "$(ls -ld "${existing}" | awk '{print $1}')" "drwxr-xr-x"
  [ -f "${existing}/keep" ] || fail "existing content was disturbed"
}

@test "a READ-ONLY bind source is never created" {
  _setup_sandbox '{}'
  local ro="${SANDBOX_DIR}/state/ro-missing"
  _seed_compose_model "${ro}|ro"

  run _run_ensure_sources

  assert_success
  [ ! -e "${ro}" ] || fail "a read-only bind source must not be fabricated"
}

@test "a failing compose config creates nothing and does not block the up" {
  _setup_sandbox '{}'
  local target="${SANDBOX_DIR}/state/x"
  _seed_compose_model "${target}|rw"
  export MOCK_COMPOSE_CONFIG_RC=1

  run _run_ensure_sources
  assert_success
  [ ! -e "${target}" ] || fail "nothing should be created when the model cannot be resolved"

  # A resolver failure is never fatal: the compose up must still run.
  run _run_docker_up
  assert_success
  run grep -E 'compose .*up -d --no-recreate' "${DOCKER_ARGS_FILE}"
  assert_success
}

@test "the read-only module mounts declare create_host_path: false" {
  # The counterpart of the writable pre-create: a missing READ-ONLY source must
  # error instead of being mounted as an empty root-owned directory.
  local f
  for f in "${PROJECT_ROOT}/src/agentic/codebase-memory/docker-compose.yml" \
    "${PROJECT_ROOT}/src/agentic/mdctx/docker-compose.yml"; do
    run python3 -c "
import re, sys
text = open(sys.argv[1]).read()
blocks = re.split(r'\n\s*-\s*type:', text)[1:]
ro = [b for b in blocks if re.search(r'read_only:\s*true', b)]
assert ro, 'no read-only long-syntax bind mount found'
assert not [b for b in ro if not re.search(r'create_host_path:\s*false', b)], 'a read-only mount is missing create_host_path: false'
" "${f}"
    assert_success
  done
}
