#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/config_sha_tests.bats
# Tests for the per-project wiring-hash helpers in src/_shared/functions.sh:
#
#   _devbot_config_sha_path   — <project>/.devbot.project.jsonc → <project>/.devbot.project.sha
#   _devbot_config_sha        — sha256 over one or more files joined with NUL
#   _devbot_wiring_sha        — combined hash of the global + project configs
#   _devbot_config_changed    — 0 when the wiring hash differs from the stored
#                               .sha, or when no baseline exists; 1 when neither
#                               config exists or the hash matches
#   _devbot_write_config_sha  — write the combined hash to <project>/.devbot.project.sha
#   _devbot_auto_reinit_if_config_changed
#                             — reinit the project when its wiring changed
#
# Run from project root:
#   bats src/_shared/tests/config_sha_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  # Fake dev-bot root: the GLOBAL config lives here, plus a fake reinit.sh.
  export DEV_BOT_ROOT="$(mktemp -d)"
  mkdir -p "${DEV_BOT_ROOT}/bin"
  cat > "${DEV_BOT_ROOT}/.devbot.global.jsonc" <<'JSON'
{
  "gpu_enabled": false,
  "version": "1.0.0"
}
JSON

  PROJECT="$(mktemp -d)"
  echo '{"project_name": "demo"}' > "${PROJECT}/.devbot.project.jsonc"

  # Source the REAL shared library (helpers live there). DEV_BOT_ROOT is
  # already exported so functions.sh keeps the sandbox root.
  source "${PROJECT_ROOT}/src/_shared/functions.sh"

  # Fake reinit.sh: records the invocation (cwd) and refreshes the wiring
  # baseline for the project it runs in (init.sh does this at the end of a
  # real reinit). FAIL_REINIT=1 makes it exit non-zero.
  cat > "${DEV_BOT_ROOT}/bin/reinit.sh" <<EOF
#!/usr/bin/env bash
source "${PROJECT_ROOT}/src/_shared/functions.sh"
echo "reinit-called \$(pwd)" >> "${DEV_BOT_ROOT}/reinit.log"
if [[ "\${FAIL_REINIT:-0}" == "1" ]]; then exit 3; fi
_devbot_write_config_sha "\$(pwd)"
exit 0
EOF
  chmod +x "${DEV_BOT_ROOT}/bin/reinit.sh"
}

teardown() {
  unset DEV_BOT_ROOT FAIL_REINIT
  rm -rf "${DEV_BOT_ROOT}" "${PROJECT}" 2>/dev/null || true
}

# ── sha path naming ───────────────────────────────────────────────────────────

@test "sha path replaces the jsonc extension, keeping the directory" {
  run _devbot_config_sha_path "${PROJECT}/.devbot.project.jsonc"
  assert_success
  assert_output "${PROJECT}/.devbot.project.sha"
}

# ── hash computation ──────────────────────────────────────────────────────────

@test "config sha matches the known sha256 of a single file" {
  # sha256("hello\n") — hardcoded so a hash-function regression is caught.
  echo "hello" > "${PROJECT}/sample.jsonc"
  run _devbot_config_sha "${PROJECT}/sample.jsonc"
  assert_success
  assert_output "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
}

@test "config sha over two files differs from either file alone" {
  echo "one" > "${PROJECT}/a.jsonc"
  echo "two" > "${PROJECT}/b.jsonc"
  local only_a only_b both
  only_a="$(_devbot_config_sha "${PROJECT}/a.jsonc")"
  only_b="$(_devbot_config_sha "${PROJECT}/b.jsonc")"
  both="$(_devbot_config_sha "${PROJECT}/a.jsonc" "${PROJECT}/b.jsonc")"
  [ -n "${both}" ]
  [ "${both}" != "${only_a}" ]
  [ "${both}" != "${only_b}" ]
}

@test "wiring sha changes when the GLOBAL config changes" {
  local before after
  before="$(_devbot_wiring_sha "${PROJECT}")"
  echo '{"gpu_enabled": true, "version": "1.0.0"}' > "${DEV_BOT_ROOT}/.devbot.global.jsonc"
  after="$(_devbot_wiring_sha "${PROJECT}")"
  [ -n "${before}" ]
  [ "${before}" != "${after}" ]
}

@test "wiring sha changes when the PROJECT config changes" {
  local before after
  before="$(_devbot_wiring_sha "${PROJECT}")"
  echo '{"project_name": "edited"}' > "${PROJECT}/.devbot.project.jsonc"
  after="$(_devbot_wiring_sha "${PROJECT}")"
  [ "${before}" != "${after}" ]
}

# ── change detection ──────────────────────────────────────────────────────────

@test "config without a baseline is changed (E1: establish baseline)" {
  run _devbot_config_changed "${PROJECT}"
  assert_success
}

@test "config matching its baseline is unchanged" {
  _devbot_write_config_sha "${PROJECT}"
  run _devbot_config_changed "${PROJECT}"
  assert_failure
}

@test "config differing from its baseline is changed" {
  _devbot_write_config_sha "${PROJECT}"
  echo '{"project_name": "changed"}' > "${PROJECT}/.devbot.project.jsonc"
  run _devbot_config_changed "${PROJECT}"
  assert_success
}

@test "a GLOBAL config change marks the project changed" {
  _devbot_write_config_sha "${PROJECT}"
  echo '{"gpu_enabled": true, "version": "2.0.0"}' > "${DEV_BOT_ROOT}/.devbot.global.jsonc"
  run _devbot_config_changed "${PROJECT}"
  assert_success
}

@test "missing configs are not changed (nothing to reinit for)" {
  rm -f "${PROJECT}/.devbot.project.jsonc" "${DEV_BOT_ROOT}/.devbot.global.jsonc"
  run _devbot_config_changed "${PROJECT}"
  assert_failure
}

# ── baseline write ────────────────────────────────────────────────────────────

@test "write baseline creates the project .sha with the wiring hash (no global .sha)" {
  _devbot_write_config_sha "${PROJECT}"
  [ -f "${PROJECT}/.devbot.project.sha" ]
  [ ! -e "${DEV_BOT_ROOT}/.devbot.global.sha" ]
  local stored
  stored="$(<"${PROJECT}/.devbot.project.sha")"
  assert_equal "${stored}" "$(_devbot_wiring_sha "${PROJECT}")"
}

@test "write baseline is a no-op when no config exists" {
  rm -f "${PROJECT}/.devbot.project.jsonc" "${DEV_BOT_ROOT}/.devbot.global.jsonc"
  run _devbot_write_config_sha "${PROJECT}"
  assert_success
  [ ! -e "${PROJECT}/.devbot.project.sha" ]
}

# ── auto-reinit orchestration ─────────────────────────────────────────────────

@test "auto-reinit is a no-op when the wiring is unchanged" {
  _devbot_write_config_sha "${PROJECT}"
  run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success
  [ ! -e "${DEV_BOT_ROOT}/reinit.log" ]
}

@test "auto-reinit runs when the project config changed" {
  _devbot_write_config_sha "${PROJECT}"
  echo '{"project_name": "edited"}' > "${PROJECT}/.devbot.project.jsonc"

  run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success
  run cat "${DEV_BOT_ROOT}/reinit.log"
  assert_output "reinit-called ${PROJECT}"
  # Baseline refreshed by the (fake) reinit — next check is clean.
  run _devbot_config_changed "${PROJECT}"
  assert_failure
}

@test "auto-reinit runs when the GLOBAL config changed" {
  _devbot_write_config_sha "${PROJECT}"
  echo '{"gpu_enabled": true, "version": "2.0.0"}' > "${DEV_BOT_ROOT}/.devbot.global.jsonc"

  run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success
  run cat "${DEV_BOT_ROOT}/reinit.log"
  assert_output --partial "reinit-called"
}

@test "a global change reinits EVERY project on its own next start" {
  # Two projects, both wired against the same global config.
  local project2
  project2="$(mktemp -d)"
  echo '{"project_name": "two"}' > "${project2}/.devbot.project.jsonc"
  _devbot_write_config_sha "${PROJECT}"
  _devbot_write_config_sha "${project2}"

  # A global change (e.g. the `version` bump devbot update writes).
  echo '{"gpu_enabled": false, "version": "9.9.9"}' > "${DEV_BOT_ROOT}/.devbot.global.jsonc"

  # Project 1 starts: reinits and refreshes ONLY its own baseline.
  run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success

  # Project 2 must still detect the change — its baseline was not touched.
  run _devbot_config_changed "${project2}"
  assert_success
  rm -rf "${project2}"
}

@test "auto-reinit on a project with no baseline runs one reinit to establish it" {
  run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success
  run cat "${DEV_BOT_ROOT}/reinit.log"
  assert_output --partial "reinit-called"
  [ -f "${PROJECT}/.devbot.project.sha" ]
  [ ! -e "${DEV_BOT_ROOT}/.devbot.global.sha" ]
}

@test "failed auto-reinit warns and continues in a non-interactive run" {
  _devbot_write_config_sha "${PROJECT}"
  echo '{"project_name": "edited"}' > "${PROJECT}/.devbot.project.jsonc"

  SKIP_CONFIRM=1 FAIL_REINIT=1 run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success
  assert_output --partial "failed"
  assert_output --partial "continuing the start anyway"
}
