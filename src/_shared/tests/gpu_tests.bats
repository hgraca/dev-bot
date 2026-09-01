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
