#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/config_sha_tests.bats
# Tests for the config-change → auto-reinit helpers in src/_shared/functions.sh:
#
#   _devbot_config_sha_path        — <file>.jsonc → <file>.sha (same location,
#                                    extension REPLACED, not appended)
#   _devbot_config_sha             — sha256 of a config file's bytes (python3)
#   _devbot_config_changed         — 0 when the current hash differs from the
#                                    stored .sha, or when no .sha baseline exists
#                                    (E1: missing baseline ⇒ changed ⇒ one reinit
#                                    establishes it); 1 when config is missing or
#                                    the hashes match
#   _devbot_write_config_sha       — write the current hash to the sibling .sha
#   _devbot_auto_reinit_if_config_changed <project_dir>
#                                  — 0 when no config changed; when the global or
#                                    project config changed, runs
#                                    `bash $DEV_BOT_ROOT/bin/reinit.sh` in the
#                                    project dir (baselines are refreshed by the
#                                    init.sh that reinit ends with); on reinit
#                                    failure, warns and (non-interactive) returns
#                                    0 = continue the start anyway
#
# Run from project root:
#   bats src/_shared/tests/config_sha_tests.bats
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"

  # ── Fake dev-bot root (configs live here + a fake reinit.sh) ────────────
  export DEV_BOT_ROOT="$(mktemp -d)"
  mkdir -p "${DEV_BOT_ROOT}/bin"
  echo '{"gpu_enabled": false}' > "${DEV_BOT_ROOT}/.devbot.global.jsonc"

  # Project dir with its own config.
  PROJECT="$(mktemp -d)"
  echo '{"project_name": "demo"}' > "${PROJECT}/.devbot.project.jsonc"

  # Source the REAL shared library (helpers live there). DEV_BOT_ROOT is
  # already exported so functions.sh keeps the sandbox root.
  source "${PROJECT_ROOT}/src/_shared/functions.sh"

  # Fake reinit.sh: records the invocation (cwd) and refreshes baselines the
  # way a real reinit does (it ends by running init.sh, which writes them).
  # FAIL_REINIT=1 makes it exit non-zero.
  cat > "${DEV_BOT_ROOT}/bin/reinit.sh" <<EOF
#!/usr/bin/env bash
source "${PROJECT_ROOT}/src/_shared/functions.sh"
echo "reinit-called \$(pwd)" >> "${DEV_BOT_ROOT}/reinit.log"
if [[ "\${FAIL_REINIT:-0}" == "1" ]]; then exit 3; fi
_devbot_write_config_sha "${DEV_BOT_ROOT}/.devbot.global.jsonc"
_devbot_write_config_sha "${PROJECT}/.devbot.project.jsonc"
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
  run _devbot_config_sha_path "${DEV_BOT_ROOT}/.devbot.global.jsonc"
  assert_success
  assert_output "${DEV_BOT_ROOT}/.devbot.global.sha"

  run _devbot_config_sha_path "${PROJECT}/.devbot.project.jsonc"
  assert_success
  assert_output "${PROJECT}/.devbot.project.sha"
}

# ── hash computation ──────────────────────────────────────────────────────────

@test "config sha matches the known sha256 of the file content" {
  # sha256("hello\n") — hardcoded so a hash-function regression is caught.
  echo "hello" > "${PROJECT}/sample.jsonc"
  run _devbot_config_sha "${PROJECT}/sample.jsonc"
  assert_success
  assert_output "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
}

# ── change detection ──────────────────────────────────────────────────────────

@test "config without a .sha baseline is changed (E1: establish baseline)" {
  run _devbot_config_changed "${PROJECT}/.devbot.project.jsonc"
  assert_success
}

@test "config matching its baseline is unchanged" {
  _devbot_write_config_sha "${PROJECT}/.devbot.project.jsonc"
  run _devbot_config_changed "${PROJECT}/.devbot.project.jsonc"
  assert_failure
}

@test "config differing from its baseline is changed" {
  _devbot_write_config_sha "${PROJECT}/.devbot.project.jsonc"
  echo '{"project_name": "changed"}' > "${PROJECT}/.devbot.project.jsonc"
  run _devbot_config_changed "${PROJECT}/.devbot.project.jsonc"
  assert_success
}

@test "missing config file is not changed (nothing to reinit for)" {
  run _devbot_config_changed "${PROJECT}/does-not-exist.jsonc"
  assert_failure
}

# ── baseline write ────────────────────────────────────────────────────────────

@test "write baseline creates a sibling .sha with the current hash" {
  _devbot_write_config_sha "${PROJECT}/.devbot.project.jsonc"
  [ -f "${PROJECT}/.devbot.project.sha" ]
  local stored current
  stored="$(<"${PROJECT}/.devbot.project.sha")"
  current="$(_devbot_config_sha "${PROJECT}/.devbot.project.jsonc")"
  assert_equal "${stored}" "${current}"
}

@test "write baseline skips a missing config file" {
  run _devbot_write_config_sha "${PROJECT}/missing.jsonc"
  assert_success
  [ ! -e "${PROJECT}/missing.sha" ]
}

# ── auto-reinit orchestration ─────────────────────────────────────────────────

@test "auto-reinit is a no-op when neither config changed" {
  _devbot_write_config_sha "${DEV_BOT_ROOT}/.devbot.global.jsonc"
  _devbot_write_config_sha "${PROJECT}/.devbot.project.jsonc"

  run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success
  [ ! -e "${DEV_BOT_ROOT}/reinit.log" ]
}

@test "auto-reinit runs reinit.sh in the project dir when the project config changed" {
  _devbot_write_config_sha "${DEV_BOT_ROOT}/.devbot.global.jsonc"
  _devbot_write_config_sha "${PROJECT}/.devbot.project.jsonc"
  echo '{"project_name": "edited"}' > "${PROJECT}/.devbot.project.jsonc"

  run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success
  assert_output --partial "reinit"
  run cat "${DEV_BOT_ROOT}/reinit.log"
  assert_output "reinit-called ${PROJECT}"
  # Baselines refreshed by the (fake) reinit — next check is clean.
  run _devbot_config_changed "${PROJECT}/.devbot.project.jsonc"
  assert_failure
}

@test "auto-reinit runs when the GLOBAL config changed" {
  _devbot_write_config_sha "${DEV_BOT_ROOT}/.devbot.global.jsonc"
  _devbot_write_config_sha "${PROJECT}/.devbot.project.jsonc"
  echo '{"gpu_enabled": true}' > "${DEV_BOT_ROOT}/.devbot.global.jsonc"

  run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success
  run cat "${DEV_BOT_ROOT}/reinit.log"
  assert_output --partial "reinit-called"
}

@test "auto-reinit on a project with no baselines runs one reinit to establish them" {
  run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success
  run cat "${DEV_BOT_ROOT}/reinit.log"
  assert_output --partial "reinit-called"
  [ -f "${DEV_BOT_ROOT}/.devbot.global.sha" ]
  [ -f "${PROJECT}/.devbot.project.sha" ]
}

@test "failed auto-reinit warns and continues in a non-interactive run" {
  _devbot_write_config_sha "${DEV_BOT_ROOT}/.devbot.global.jsonc"
  _devbot_write_config_sha "${PROJECT}/.devbot.project.jsonc"
  echo '{"project_name": "edited"}' > "${PROJECT}/.devbot.project.jsonc"

  SKIP_CONFIRM=1 FAIL_REINIT=1 run _devbot_auto_reinit_if_config_changed "${PROJECT}"
  assert_success
  assert_output --partial "failed"
  assert_output --partial "continuing the start anyway"
}
