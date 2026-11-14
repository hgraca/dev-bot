#!/usr/bin/env bats
# =============================================================================
# src/harnesses/opencode-v2/tests/version_guard_tests.bats
# Tests the opencode 2.x version guard.
#
# This module's plugin surface is the opencode V2 plugin API, so a 1.x host
# loads none of it while the config still seeds — a silent half-working
# install. The guard refuses it with an actionable message.
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

  # Keep the real ~/.opencode/v2 and any opencode2 on PATH out of the guard's
  # resolution chain, so "binary absent" really means absent.
  FAKE_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

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

# A fake opencode2 that reports $1 from --version and records every launch
# (any non---version invocation) to LAUNCH_LOG — so a test can prove the guard
# refused BEFORE the harness started.
_fake_opencode2() {
  local version="$1"
  cat > "${FAKE_HOME}/.opencode/bin/opencode2" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == "--version" ]]; then
  printf '%s\n' "${version}"
  exit 0
fi
printf 'launch:%s\n' "\$*" >> "${LAUNCH_LOG}"
EOF
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode2"
}

_fake_opencode2_no_version() {
  cat > "${FAKE_HOME}/.opencode/bin/opencode2" <<EOF
#!/usr/bin/env bash
printf 'launch:%s\n' "\$*" >> "${LAUNCH_LOG}"
exit 0
EOF
  chmod +x "${FAKE_HOME}/.opencode/bin/opencode2"
}

# ── up.sh ────────────────────────────────────────────────────────────────────

@test "up.sh refuses opencode 1.x with an actionable fatal" {
  _fake_opencode2 "1.18.35"
  printf '{ "harness": "opencode-v2" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_failure
  [[ "${combined}" == *"1.18.35"* ]]
  [[ "${combined}" == *"2.x"* ]]
  [[ "${combined}" == *"plugin"* ]]
}

@test "up.sh allows opencode 2.x silently" {
  _fake_opencode2 "2.3.0"
  printf '{ "harness": "opencode-v2" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "FATAL"
}

@test "up.sh is a no-op when the opencode2 binary is absent" {
  printf '{ "harness": "opencode-v2" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "FATAL"
}

@test "up.sh allows a source-build version (0.0.0--<timestamp>)" {
  _fake_opencode2 "0.0.0--20261016120000"
  printf '{ "harness": "opencode-v2" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "FATAL"
}

@test "up.sh warns but proceeds when --version yields nothing" {
  _fake_opencode2_no_version
  printf '{ "harness": "opencode-v2" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_success
  [[ "${combined}" == *"WARN"* ]]
  [[ "${combined}" != *"FATAL"* ]]
}

@test "up.sh refuses a v-prefixed opencode 1.x (tags use the v form)" {
  # The parse must tolerate a leading `v`: a version it cannot match falls
  # through to the fail-open warn branch, silently allowing a 1.x host.
  _fake_opencode2 "v1.19.0"
  printf '{ "harness": "opencode-v2" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_failure
  [[ "${combined}" == *"v1.19.0"* ]]
}

@test "up.sh allows a v-prefixed opencode 2.x" {
  _fake_opencode2 "v2.0.30"
  printf '{ "harness": "opencode-v2" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  assert_success
  refute_output --partial "FATAL"
}

@test "up.sh warns but proceeds on a version with no leading digit" {
  # The fail-open path: pin it, so a future format change is a conscious choice.
  _fake_opencode2 "bogus"
  printf '{ "harness": "opencode-v2" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_success
  [[ "${combined}" == *"WARN"* ]]
  [[ "${combined}" != *"FATAL"* ]]
}

@test "up.sh stays silent on a claudecode-configured project" {
  _fake_opencode2 "1.18.35"
  printf '{ "harness": "claudecode" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"

  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"

  assert_success
  refute_output --partial "FATAL"
  refute_output --partial "1.18.35"
}

@test "up.sh stays silent on an opencode v1-configured project" {
  _fake_opencode2 "2.3.0"
  printf '{ "harness": "opencode" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"

  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"

  assert_success
  refute_output --partial "FATAL"
}

# ── start.sh (the hard gate) ─────────────────────────────────────────────────

@test "start.sh refuses to launch on opencode 1.x and never starts the harness" {
  _fake_opencode2 "1.18.35"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_failure
  [[ "${combined}" == *"1.18.35"* ]]
  [[ "${combined}" == *"2.x"* ]]
  [ ! -s "${LAUNCH_LOG}" ]
}

@test "start.sh still launches on opencode 2.x" {
  _fake_opencode2 "2.3.0"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  run cat "${LAUNCH_LOG}"
  assert_output --partial "launch:"
}

@test "start.sh allows the 2.x lower boundary (2.0.0)" {
  _fake_opencode2 "2.0.0"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
}

@test "start.sh parses the real 2.x version banner (opencode v2.3.0)" {
  # The 2.x binary prints the product name before the version; a guard that
  # only strips a leading `v` sees a non-numeric major and fails open.
  _fake_opencode2 "opencode v2.3.0"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  assert_success
  run cat "${LAUNCH_LOG}"
  assert_output --partial "launch:"
}

@test "start.sh fails clearly when no 2.x binary is installed" {
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/start.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_failure
  [[ "${combined}" == *"opencode 2.x binary not found"* ]]
  [ ! -s "${LAUNCH_LOG}" ]
}

@test "up.sh refuses an unverified host major (3.x)" {
  _fake_opencode2 "3.1.0"
  printf '{ "harness": "opencode-v2" }\n' > "${FAKE_PROJECT}/.devbot.project.jsonc"
  DEV_BOT_ROOT="${FAKE_ROOT}" HOME="${FAKE_HOME}" PATH="${FAKE_PATH}" \
    run bash "${MODULE_DIR}/up.sh" "${FAKE_PROJECT}"
  local combined="${output}${stderr:-}"
  assert_failure
  [[ "${combined}" == *"3.1.0"* ]]
  [[ "${combined}" == *"unverified"* ]]
}
