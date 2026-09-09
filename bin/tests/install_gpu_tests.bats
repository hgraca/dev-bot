#!/usr/bin/env bats
# =============================================================================
# bin/tests/install_gpu_tests.bats
# Tests that bin/install.sh (devbot install — module installs, NOT the
# standalone bootstrap installer) calls _devbot_detect_gpu AFTER
# _setup_devbot_config. GPU detection lives at the devbot level so gpu_enabled
# is recorded even when the ollama module is disabled (it is off by default).
#
# bin/install.sh DEFINES _setup_env / _setup_devbot_config / print_summary
# itself (they override anything in functions.sh), so the real config-setup
# steps run against a sandbox: a minimal .devbot.global.dist.jsonc is provided,
# _setup_devbot_config copies it to .devbot.global.jsonc, then main()'s GPU
# call records into a marker via a stubbed _devbot_detect_gpu. The heavy steps
# (prereqs, npm, module installs) are stubbed no-ops. No docker/network.
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

@test "install.sh runs GPU detection after the config is set up" {
  mkdir -p "${SANDBOX_DIR}/bin" "${SANDBOX_DIR}/src/_shared" \
    "${SANDBOX_DIR}/src/tools" "${SANDBOX_DIR}/src/agentic" \
    "${SANDBOX_DIR}/src/harnesses"

  # Minimal dist — the real _setup_devbot_config copies it to
  # .devbot.global.jsonc (gpu_enabled key present so _devbot_set_bool's sed
  # has something to match, mirroring the shipped dist).
  printf '{\n  "gpu_enabled": false\n}\n' > "${SANDBOX_DIR}/.devbot.global.dist.jsonc"

  # Copy production install.sh, strip the main call tail (re-added by the
  # runner below).
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/install.sh" > "${SANDBOX_DIR}/bin/install.sh"

  # Stub functions.sh: only what install.sh does NOT define itself. The real
  # _setup_env / _setup_devbot_config / print_summary come from the copied
  # script. _devbot_detect_gpu is recorded (not run) so the test needs no
  # docker/GPU.
  cat > "${SANDBOX_DIR}/src/_shared/functions.sh" <<EOF
#!/usr/bin/env bash
_header_1() { true; }
_header_2() { true; }
_header_3() { true; }
_info()  { true; }
_ok()    { true; }
_skip()  { true; }
_warn()  { true; }
_error() { echo "ERROR: \$*" >&2; exit 1; }
_fatal() { echo "FATAL: \$*" >&2; exit 1; }
_log()   { true; }
_fmt_duration() { echo "0s"; }
TEXT_BOLD=''; TEXT_BLUE=''; TEXT_CLEAR=''; TEXT_DIM=''
TEXT_GREEN=''; TEXT_YELLOW=''; TEXT_ORANGE=''; TEXT_RED=''
_check_prerequisites() { true; }
_check_python3() { true; }
_check_flock() { true; }
_run_module_prereqs() { true; }
_devbot_detect_gpu() {
  # Ordering assertion: when main() reaches GPU detection, the config must
  # already exist — detection's first guard skips without it (and the real
  # _setup_devbot_config runs earlier in main()).
  if [[ -f "${SANDBOX_DIR}/.devbot.global.jsonc" ]]; then
    echo "gpu-detect-after-config" >> "${SANDBOX_DIR}/order.log"
  else
    echo "gpu-detect-BEFORE-config" >> "${SANDBOX_DIR}/order.log"
  fi
}
_install_dependencies() { true; }
_install_modules() { true; }
EOF

  export DEV_BOT_ROOT="${SANDBOX_DIR}"
  : > "${SANDBOX_DIR}/order.log"

  run bash -c "source '${SANDBOX_DIR}/bin/install.sh' && main"
  assert_success

  # The real _setup_devbot_config copied the dist → config exists.
  [ -f "${SANDBOX_DIR}/.devbot.global.jsonc" ]
  # And main() reached _devbot_detect_gpu AFTER the config was set up (the
  # stub records which ordering it observed).
  run cat "${SANDBOX_DIR}/order.log"
  assert_output "gpu-detect-after-config"
}
