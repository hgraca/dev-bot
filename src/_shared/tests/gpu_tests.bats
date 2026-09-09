#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/gpu_tests.bats
# Tests for GPU detection helpers in src/_shared/functions.sh:
#   _has_gpu, _has_docker_gpu, _qmd_gpu_value
#
# audit-25 F5: gpu_enabled (the docker-passthrough flag set by
# ollama/install.sh) was conflated with native host-GPU capability. qmd runs
# as a plain local process, so its QMD_LLAMA_GPU selection must be driven by
# _has_gpu (the host probe), not by whether the ollama *container* can get GPU
# passthrough. On Docker-Desktop-on-macOS hosts that conflation forced qmd
# CPU-only despite a usable Metal GPU.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  # Isolated DEV_BOT_ROOT so _devbot_is_true reads a temp config we control.
  TEST_TEMP="$(mktemp -d)"
  MOCK="$(mktemp -d)"
}

teardown() {
  unset DETECT_HAS_GPU DETECT_DOCKER_GPU 2>/dev/null || true
  rm -rf "$TEST_TEMP" "$MOCK"
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# Write a global config with the given gpu_enabled value, then source the
# shared library against it.
_source_with_config() {
  local gpu_enabled="$1"
  printf '{\n  "gpu_enabled": %s\n}\n' "${gpu_enabled}" \
    > "${TEST_TEMP}/.devbot.global.jsonc"
  export DEV_BOT_ROOT="$TEST_TEMP"
  source "$PROJECT_ROOT/src/_shared/functions.sh"
}

_mock_uname() {
  cat > "$MOCK/uname" <<SCRIPT
#!/bin/bash
echo "$1"
SCRIPT
  chmod +x "$MOCK/uname"
}

# ── _has_docker_gpu: container passthrough probe ──────────────────────────────

@test "_has_docker_gpu: false on non-Linux (Docker Desktop macOS has no passthrough)" {
  _source_with_config false
  _mock_uname "Darwin"

  PATH="$MOCK:/usr/bin:/bin" run _has_docker_gpu
  assert_failure
}

# ── _qmd_gpu_value: must follow the HOST GPU, not the config flag ────────────

@test "audit-25 F5: metal on Darwin when host GPU present, even with gpu_enabled=false" {
  _source_with_config false
  # Stub the host probe to simulate Apple Silicon with a usable Metal GPU.
  _has_gpu() { return 0; }
  _mock_uname "Darwin"

  PATH="$MOCK:/usr/bin:/bin" run _qmd_gpu_value
  assert_success
  assert_output "metal"
}

@test "audit-25 F5: false when host has no GPU, even with gpu_enabled=true" {
  _source_with_config true
  _has_gpu() { return 1; }

  run _qmd_gpu_value
  assert_success
  assert_output "false"
}

@test "qmd_gpu_value: cuda on Linux with NVIDIA host GPU" {
  _source_with_config false
  _has_gpu() { return 0; }

  # Fake nvidia-smi so the vendor branch resolves to cuda.
  cat > "$MOCK/nvidia-smi" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
  chmod +x "$MOCK/nvidia-smi"
  _mock_uname "Linux"

  PATH="$MOCK:/usr/bin:/bin" run _qmd_gpu_value
  assert_success
  assert_output "cuda"
}

# ── _has_gpu: host probe ─────────────────────────────────────────────────────

@test "_has_gpu: true on Apple Silicon (Darwin arm64)" {
  _source_with_config false
  cat > "$MOCK/uname" <<'SCRIPT'
#!/bin/bash
if [[ "$1" == "-s" ]]; then echo "Darwin"; else echo "arm64"; fi
SCRIPT
  chmod +x "$MOCK/uname"

  PATH="$MOCK:/usr/bin:/bin" run _has_gpu
  assert_success
}

@test "_has_gpu: false on Intel Mac (Darwin x86_64)" {
  _source_with_config false
  cat > "$MOCK/uname" <<'SCRIPT'
#!/bin/bash
if [[ "$1" == "-s" ]]; then echo "Darwin"; else echo "x86_64"; fi
SCRIPT
  chmod +x "$MOCK/uname"

  PATH="$MOCK:/usr/bin:/bin" run _has_gpu
  assert_failure
}

# ── _devbot_detect_gpu: records gpu_enabled in the global config ────────────
# Relocated from src/tools/ollama/install.sh to the shared library so GPU
# detection runs from bin/install.sh / bin/update.sh (devbot lifecycle) even
# when the ollama module itself is disabled in the `modules` map. Semantics
# preserved verbatim:
#   - no docker daemon → gpu_enabled follows the HOST probe (_has_gpu); the
#     host's ollama serves the API and local processes (qmd) can use the GPU.
#   - docker daemon present → gpu_enabled follows _has_docker_gpu (container
#     passthrough); a host GPU without the container toolkit does NOT enable
#     passthrough.

_detect_with() {
  local docker_ok="$1"   # "yes" | "no"
  local has_gpu="$2"     # "yes" | "no"  (host probe)
  local docker_gpu="$3"  # "yes" | "no"  (container passthrough probe)

  # Stored as module-level flags — the mock functions run later (inside
  # `run _devbot_detect_gpu`) when _detect_with's locals are gone.
  DETECT_HAS_GPU="${has_gpu}"
  DETECT_DOCKER_GPU="${docker_gpu}"

  # Fresh config with gpu_enabled present (the key must exist for
  # _devbot_set_bool's sed to find it).
  printf '{\n  "gpu_enabled": false\n}\n' > "${TEST_TEMP}/.devbot.global.jsonc"
  export DEV_BOT_ROOT="$TEST_TEMP"
  source "$PROJECT_ROOT/src/_shared/functions.sh"

  if [[ "${docker_ok}" == "yes" ]]; then
    cat > "$MOCK/docker" <<'SCRIPT'
#!/bin/bash
if [[ "$1" == "info" ]]; then exit 0; fi
exit 1
SCRIPT
  else
    cat > "$MOCK/docker" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
  fi
  chmod +x "$MOCK/docker"

  _has_gpu() { [[ "${DETECT_HAS_GPU}" == "yes" ]]; }
  _has_docker_gpu() { [[ "${DETECT_DOCKER_GPU}" == "yes" ]]; }
  _gpu_vendor() { echo "nvidia"; }
}

@test "detect_gpu: no docker daemon + host GPU → gpu_enabled=true" {
  _detect_with no yes no
  PATH="$MOCK:/usr/bin:/bin" run _devbot_detect_gpu
  assert_success
  grep -q '"gpu_enabled": true' "${TEST_TEMP}/.devbot.global.jsonc"
}

@test "detect_gpu: no docker daemon + no host GPU → gpu_enabled=false" {
  _detect_with no no no
  PATH="$MOCK:/usr/bin:/bin" run _devbot_detect_gpu
  assert_success
  grep -q '"gpu_enabled": false' "${TEST_TEMP}/.devbot.global.jsonc"
}

@test "detect_gpu: docker daemon + container passthrough → gpu_enabled=true" {
  _detect_with yes yes yes
  PATH="$MOCK:/usr/bin:/bin" run _devbot_detect_gpu
  assert_success
  grep -q '"gpu_enabled": true' "${TEST_TEMP}/.devbot.global.jsonc"
}

@test "detect_gpu: docker daemon + host GPU but no toolkit → gpu_enabled=false" {
  # audit-25 F5: a host GPU without container passthrough must NOT enable the
  # GPU compose override (ollama would run CPU in docker anyway).
  _detect_with yes yes no
  PATH="$MOCK:/usr/bin:/bin" run _devbot_detect_gpu
  assert_success
  grep -q '"gpu_enabled": false' "${TEST_TEMP}/.devbot.global.jsonc"
}
