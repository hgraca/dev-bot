#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/ollama_exec_tests.bats
# Tests for _devbot_ollama_exec — runs an `ollama <args>` command inside the
# dev-bot-ollama container, booting the container first when it is not
# running (with the GPU overlay when gpu_enabled) and taking it back DOWN
# afterwards when this helper started it. A container that was already
# running is left running. Backs cmd_models (devbot models pull/list/remove).
#
# Run from project root:
#   bats src/_shared/tests/ollama_exec_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  # Sandbox dev-bot root with the ollama compose + gpu overlay + config.
  export DEV_BOT_ROOT="$(mktemp -d)"
  mkdir -p "${DEV_BOT_ROOT}/src/tools/ollama"
  cat > "${DEV_BOT_ROOT}/src/tools/ollama/docker-compose.yml" <<'EOF'
services:
  ollama:
    image: ollama/ollama
    container_name: dev-bot-ollama
EOF
  cat > "${DEV_BOT_ROOT}/docker-compose.gpu.yml" <<'EOF'
services:
  ollama:
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
EOF
  printf '{\n  "gpu_enabled": false\n}\n' > "${DEV_BOT_ROOT}/.devbot.global.jsonc"

  source "${PROJECT_ROOT}/src/_shared/functions.sh"

  # ── Mock docker ──────────────────────────────────────────────────────────
  MOCK="$(mktemp -d)"
  : > "${MOCK}/calls.log"
  # Container state: "up" | "down". Readiness: container responds to
  # `ollama list` once it has been started (compose up).
  echo "down" > "${MOCK}/container.state"
  echo "0" > "${MOCK}/exec.rc"

  cat > "${MOCK}/docker" <<EOF
#!/usr/bin/env bash
log() { printf '%s\n' "\$*" >> "${MOCK}/calls.log"; }
case "\$1" in
  info)
    if [[ -f "${MOCK}/no-daemon" ]]; then exit 1; fi
    exit 0
    ;;
  ps)
    if [[ "\$(cat "${MOCK}/container.state")" == "up" ]]; then
      printf 'dev-bot-ollama\n'
    fi
    ;;
  compose)
    # docker compose -f <file>... up -d ollama | down ollama
    log "\$*"
    local action=""
    for a in "\$@"; do
      [[ "\$a" == "up" || "\$a" == "down" ]] && action="\$a"
      [[ "\$a" == "ollama" && -n "\$action" ]] && break
    done
    if [[ "\${action}" == "up" ]]; then
      echo "up" > "${MOCK}/container.state"
    else
      echo "down" > "${MOCK}/container.state"
    fi
    exit 0
    ;;
  exec)
    # docker exec dev-bot-ollama ollama <args...>
    if [[ "\$(cat "${MOCK}/container.state")" != "up" ]]; then
      echo "container not running" >&2
      exit 1
    fi
    shift 2  # exec dev-bot-ollama
    log "exec \$*"
    if [[ "\$1" == "list" ]]; then exit 0; fi
    exit "\$(cat "${MOCK}/exec.rc")"
    ;;
  *)
    log "docker \$*"
    exit 0
    ;;
esac
EOF
  chmod +x "${MOCK}/docker"
  export PATH="${MOCK}:${PATH}"
}

teardown() {
  unset DEV_BOT_ROOT 2>/dev/null || true
  rm -rf "${DEV_BOT_ROOT}" "${MOCK}" 2>/dev/null || true
}

@test "exec runs directly when the container is already running (no boot, no down)" {
  echo "up" > "${MOCK}/container.state"
  echo "0" > "${MOCK}/exec.rc"

  run _devbot_ollama_exec list
  assert_success
  run cat "${MOCK}/calls.log"
  refute_output --partial "compose-up"
  refute_output --partial "compose-down"
  assert_output --partial "exec ollama list"
}

@test "exec boots the container, runs, and downs it again when it was down" {
  echo "down" > "${MOCK}/container.state"
  echo "0" > "${MOCK}/exec.rc"

  run _devbot_ollama_exec pull llama3.2:3b
  assert_success
  run cat "${MOCK}/calls.log"
  assert_output --partial "up -d ollama"
  assert_output --partial "exec ollama pull llama3.2:3b"
  assert_output --partial "down ollama"
}

@test "exec propagates the ollama command exit code" {
  echo "up" > "${MOCK}/container.state"
  echo "3" > "${MOCK}/exec.rc"

  run _devbot_ollama_exec rm llama3.2:3b
  assert_failure
  [ "$status" -eq 3 ]
}

@test "exec applies the GPU overlay when gpu_enabled and it boots the container" {
  printf '{\n  "gpu_enabled": true\n}\n' > "${DEV_BOT_ROOT}/.devbot.global.jsonc"
  echo "down" > "${MOCK}/container.state"
  echo "0" > "${MOCK}/exec.rc"

  # Re-source so _devbot_is_true reads the updated config.
  source "${PROJECT_ROOT}/src/_shared/functions.sh"
  run _devbot_ollama_exec list
  assert_success
  run cat "${MOCK}/calls.log"
  # The compose-up line must carry the gpu overlay file.
  assert_output --regexp "-f .*docker-compose\.gpu\.yml"
}

@test "exec fails cleanly when there is no docker daemon" {
  touch "${MOCK}/no-daemon"
  echo "down" > "${MOCK}/container.state"

  run _devbot_ollama_exec list
  assert_failure
  run cat "${MOCK}/calls.log"
  assert_output ""
}
