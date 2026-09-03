#!/usr/bin/env bats
# =============================================================================
# src/agentic/qmd/tests/share_with_ollama_tests.bats
# Tests for share-with-ollama.sh's qmd-cache mount guard.
#
# Regression: `devbot up` failed with ollama's misleading
# "400 Bad Request: invalid model name" whenever the host qmd cache dir
# (~/.cache/qmd/models) had been replaced after the dev-bot-ollama container
# was created. Docker bind mounts keep the source inode, so the container's
# /root/.qmd-cache stayed pinned to the orphaned (empty) directory — while
# `_ensure_qmd_cache_mount` only tested `test -d`, which an empty mount passes.
#
# These tests stub `docker` in PATH (module convention, see
# docs/tests/docs_tests.bats) and drive the guard through its four states:
# healthy mount, stale mount that heals on recreate, stale mount that never
# heals, and missing mount.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  TOOL="$MODULE_DIR/tools/share-with-ollama.sh"
}

# ── Fake docker ───────────────────────────────────────────────────────────────
# Stateful stub: logs every invocation to FAKE_DOCKER_LOG; behaviour selected by
# FAKE_MODE:
#   healthy         — mount dir present, GGUF visible inside the container
#   stale-heals     — mount dir present but GGUF invisible until a `compose`
#                     run touches FAKE_HEAL_MARKER (recreate re-resolves)
#   stale-permanent — mount dir present, GGUF never visible (recreate can't fix)
#   missing         — mount dir absent inside the container
# `ollama list` always reports the three qmd/ models as imported, so the
# import machinery (sha256sum / create) is never exercised — these tests only
# cover the mount guard that precedes it.

make_fake_docker() {
  local sandbox="$1"
  local bin_dir="${sandbox}/bin"
  mkdir -p "${bin_dir}"

  cat > "${bin_dir}/docker" <<'SCRIPT'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_DOCKER_LOG}"
case "$1" in
  info) exit 0 ;;
  ps) echo "dev-bot-ollama"; exit 0 ;;
  compose)
    touch "${FAKE_HEAL_MARKER}"
    exit 0
    ;;
  exec)
    shift  # container name
    shift
    cmd="$*"
    case "$cmd" in
      "ollama list")
        echo "qmd/embeddinggemma-300m:q8_0"
        echo "qmd/qmd-query-expansion-1.7b:q4_k_m"
        echo "qmd/qwen3-reranker-0.6b:q8_0"
        exit 0
        ;;
      *"test -d"*)
        [[ "${FAKE_MODE}" == "missing" ]] && exit 1 || exit 0
        ;;
      *"test -f"*)
        case "${FAKE_MODE}" in
          healthy) exit 0 ;;
          stale-heals) [[ -e "${FAKE_HEAL_MARKER}" ]] && exit 0 || exit 1 ;;
          stale-permanent) exit 1 ;;
          *) exit 0 ;;
        esac
        ;;
    esac
    exit 0
    ;;
esac
exit 0
SCRIPT
  chmod +x "${bin_dir}/docker"
}

# Scaffold: sandbox with fake docker, a fake host qmd cache holding one
# downloaded GGUF, and (optionally) a .devbot.global.jsonc.
# Writes sandbox path to $1 (caller-declared var). Note: the temp dir must NOT
# be stored in a local named like the caller's var, or eval assigns the local.
scaffold() {
  local sb
  sb="$(mktemp -d)"
  make_fake_docker "$sb"

  mkdir -p "${sb}/cache"
  printf 'fake-gguf-bytes' > "${sb}/cache/hf_ggml-org_embeddinggemma-300M-Q8_0.gguf"

  : > "${sb}/docker.log"

  eval "$1='${sb}'"
}

run_tool() {
  local sandbox="$1" mode="$2"
  run env \
    PATH="${sandbox}/bin:$(dirname "$(command -v python3)")" \
    DEV_BOT_ROOT="$sandbox" \
    QMD_MODELS_DIR="${sandbox}/cache" \
    FAKE_MODE="$mode" \
    FAKE_DOCKER_LOG="${sandbox}/docker.log" \
    FAKE_HEAL_MARKER="${sandbox}/healed" \
    bash "$TOOL"
}

assert_recreated_once() {
  local sandbox="$1"
  local count
  count="$(grep -c 'up -d --force-recreate ollama' "${sandbox}/docker.log" || true)"
  [[ "$count" -eq 1 ]] || fail "expected exactly 1 recreate, got ${count}"
}

# ── Healthy mount: no recreate ────────────────────────────────────────────────

@test "healthy mount: no recreate, exit 0" {
  local sandbox
  scaffold sandbox

  run_tool "$sandbox" healthy

  assert_success
  refute_output --partial "recreating"
  run grep -c "compose" "$sandbox/docker.log"
  assert_output "0"
}

@test "empty host cache: no recreate even when mount looks empty" {
  # With no GGUF downloaded on the host there is nothing to import and no way
  # to tell an empty mount from a stale one — the guard must not recreate.
  local sandbox
  sandbox="$(mktemp -d)"
  make_fake_docker "$sandbox"
  mkdir -p "${sandbox}/cache"
  : > "${sandbox}/docker.log"

  run_tool "$sandbox" stale-permanent

  assert_success
  run grep -c "compose" "$sandbox/docker.log"
  assert_output "0"
}

# ── Stale mount ───────────────────────────────────────────────────────────────

@test "stale mount: recreates once with --force-recreate, then proceeds" {
  local sandbox
  scaffold sandbox

  run_tool "$sandbox" stale-heals

  assert_success
  assert_recreated_once "$sandbox"
  assert_output --partial "re-resolve"
}

@test "stale mount that never heals: loud error and non-zero exit" {
  local sandbox
  scaffold sandbox

  run_tool "$sandbox" stale-permanent

  assert_failure
  assert_recreated_once "$sandbox"
}

@test "missing mount dir: recreates with --force-recreate (regression guard)" {
  local sandbox
  scaffold sandbox

  run_tool "$sandbox" missing

  assert_success
  assert_recreated_once "$sandbox"
}

# ── GPU overlay ───────────────────────────────────────────────────────────────

@test "recreate appends docker-compose.gpu.yml when gpu_enabled" {
  local sandbox
  scaffold sandbox
  printf '"gpu_enabled": true,\n' > "$sandbox/.devbot.global.jsonc"

  run_tool "$sandbox" stale-heals

  assert_success
  assert_recreated_once "$sandbox"
  run grep -c "docker-compose.gpu.yml" "$sandbox/docker.log"
  assert_output "1"
}

@test "recreate skips docker-compose.gpu.yml when gpu disabled" {
  local sandbox
  scaffold sandbox
  printf '"gpu_enabled": false,\n' > "$sandbox/.devbot.global.jsonc"

  run_tool "$sandbox" stale-heals

  assert_success
  assert_recreated_once "$sandbox"
  run grep -c "docker-compose.gpu.yml" "$sandbox/docker.log"
  assert_output "0"
}
