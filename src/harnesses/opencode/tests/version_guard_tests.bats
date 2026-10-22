#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode/tests/version_guard_tests.bats
# Tests the opencode version guard.
#
# dev-bot's plugin surface is the opencode V1 plugin API (server hooks + TUI
# plugins), so a v2 host loads none of it while the config still seeds — a
# silent half-working install. The guard refuses it with an actionable message.
#
# Two call sites, both covered:
#   - up.sh     — surfaces it on `devbot` / `devbot up` / `make up`.
#   - start.sh  — the hard gate. _run_service_scripts warns with a failed
#                 module script's exit code but still returns 0, so only
#                 start.sh can refuse the launch itself.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"

  FAKE_HOME="$(mktemp -d)"
  FAKE_PROJECT="$(mktemp -d)"
  FAKE_ROOT="$(mktemp -d)"
  LAUNCH_LOG="$(mktemp)"
  mkdir -p "${FAKE_HOME}/.opencode/bin"

  # A module-free dev-bot root so start.sh's MCP env-var gate scans nothing.
  # Its own _shared/reader copies let harness resolution work against the
  # sandbox instead of the real checkout.
  mkdir -p "${FAKE_ROOT}/src/tools" "${FAKE_ROOT}/src/agentic" "${FAKE_ROOT}/src/harnesses" \
           "${FAKE_ROOT}/src/_shared"
  cp "${MODULE_DIR}/../../_shared/read_jsonc.py" "${FAKE_ROOT}/src/_shared/"
  echo '{ "modules": { "memory": false } }' > "${FAKE_ROOT}/.devbot.global.jsonc"
}

teardown() {
  rm -rf "${FAKE_HOME}" "${FAKE_PROJECT}" "${FAKE_ROOT}"
  rm -f "${LAUNCH_LOG}"
}

# A fake opencode that reports $1 from --version and records every launch
# (any non---version invocation) to LAUNCH_LOG — so a test can prove the guard
# refused BEFORE the harness started.
_fake_opencode() {
  local version="$1"
  cat > "${FAKE_HOME}/.opencode/bin/opencode" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
  printf '%s\n' "${version}"
  exit 0
fi
printf 'launch:%s\n' "\$*" >> "${LAUNCH_LOG}"
EOF
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode"
}

_fake_opencode_no_version() {
  cat > "${FAKE_HOME}/.opencode/bin/opencode" <<EOF
#!/usr/bin/env bash
printf 'launch:%s\n' "\$*" >> "${LAUNCH_LOG}"
exit 0
EOF
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode"
}

# ── up.sh ────────────────────────────────────────────────────────────────────

@test "up.sh refuses opencode 2.x with an actionable fatal" {
  _fake_opencode "2.0.30"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_failure
  [[ "${combined}" == *"2.0.30"* ]]
  [[ "${combined}" == *"1.x"* ]]
  [[ "${combined}" == *"plugin"* ]]
}

@test "up.sh allows opencode 1.x silently" {
  _fake_opencode "1.18.35"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "FATAL"
}

@test "up.sh is a no-op when the opencode binary is absent" {
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "FATAL"
}

@test "up.sh allows a source-build version (0.0.0--<timestamp>)" {
  _fake_opencode "0.0.0--20261016120000"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "FATAL"
}

@test "up.sh warns but proceeds when --version yields nothing" {
  _fake_opencode_no_version
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_success
  [[ "${combined}" == *"WARN"* ]]
  [[ "${combined}" != *"FATAL"* ]]
}

@test "up.sh refuses a v-prefixed opencode 2.x (opencode tags use the v form)" {
  # The parse must tolerate a leading `v`: a version it cannot match falls
  # through to the fail-open warn branch, silently allowing a 2.x host.
  _fake_opencode "v2.0.30"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_failure
  [[ "${combined}" == *"v2.0.30"* ]]
}

@test "up.sh allows a v-prefixed opencode 1.x" {
  _fake_opencode "v1.19.0"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "FATAL"
}

@test "up.sh warns but proceeds on a version with no leading digit" {
  # The fail-open path: pin it, so a future format change is a conscious choice.
  _fake_opencode "bogus"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_success
  [[ "${combined}" == *"WARN"* ]]
  [[ "${combined}" != *"FATAL"* ]]
}

@test "up.sh stays silent on a claudecode-configured project" {
  _fake_opencode "2.0.30"
  printf '{ "harness": "claudecode" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"

  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"

  assert_success
  refute_output --partial "FATAL"
  refute_output --partial "2.0.30"
}

# ── start.sh (the hard gate) ─────────────────────────────────────────────────

@test "start.sh refuses to launch on opencode 2.x and never starts the harness" {
  _fake_opencode "2.0.0"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_failure
  [[ "${combined}" == *"2.0.0"* ]]
  [[ "${combined}" == *"1.x"* ]]
  [ ! -s "${LAUNCH_LOG}" ]
}

@test "start.sh still launches on opencode 1.x" {
  _fake_opencode "1.18.35"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  run cat "${LAUNCH_LOG}"
  assert_output --partial "launch:"
}

@test "start.sh allows the 1.x upper boundary (1.99.0)" {
  _fake_opencode "1.99.0"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" \
    run bash "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
}
