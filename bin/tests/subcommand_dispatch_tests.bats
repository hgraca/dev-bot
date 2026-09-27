#!/usr/bin/env bats
# =============================================================================
# bin/tests/subcommand_dispatch_tests.bats
# Tests for bin/devbot's main() dispatch: a `devbot <sub>` invocation must
# forward its OWN arguments to the delegated bin/<sub>.sh, never the subcommand
# name itself.
#
# Regression: the `down)` arm was the only one in main()'s case missing its
# `shift`, so `devbot down` invoked down.sh as `down.sh down`. down.sh reads $1
# as the project dir (bin/down.sh:19), so it printed
#   cd: down: No such file or directory
# and carried on with an EMPTY PROJECT_DIR — silently degrading the
# disabled-module / per-project config lookup to global-only. `devbot down
# <path>` was worse: the real path was never seen.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared"

  # The REAL dispatch: bin/devbot verbatim, including its `main "$@"` tail —
  # the thing under test. Its preamble sources these two.
  cp "${PROJECT_ROOT}/src/_shared/functions.sh" "${SANDBOX}/src/_shared/functions.sh"
  cp "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX}/src/_shared/read_jsonc.py"
  cp "${PROJECT_ROOT}/bin/devbot" "${SANDBOX}/bin/devbot"

  # Stub the delegated script — records the argv it was handed. The arg count
  # is logged separately: `printf '%s\n' "$@"` with no args still emits one
  # empty line, which would hide a zero-arg call.
  cat > "${SANDBOX}/bin/down.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${DEV_BOT_ROOT}/down-args.log"
printf '%s\n' "$#" > "${DEV_BOT_ROOT}/down-argc.log"
exit 0
EOF
  chmod +x "${SANDBOX}/bin/down.sh"

  # A copy with the trailing `main "$@"` stripped, so a test can source it and
  # invoke main() itself with cmd_harness stubbed — the dispatch table is the
  # thing under test, not the harness start it would otherwise launch.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/devbot" > "${SANDBOX}/bin/devbot-lib"
}

teardown() {
  rm -rf "${SANDBOX}"
}

@test "devbot down forwards no arguments — the subcommand name is not a project dir" {
  run bash "${SANDBOX}/bin/devbot" down
  [ "${status}" -eq 0 ]
  assert_equal "$(cat "${SANDBOX}/down-argc.log")" "0"
}

@test "devbot down <path> forwards exactly the path, not the subcommand first" {
  run bash "${SANDBOX}/bin/devbot" down /tmp/some/project
  [ "${status}" -eq 0 ]
  assert_equal "$(cat "${SANDBOX}/down-args.log")" "/tmp/some/project"
  assert_equal "$(cat "${SANDBOX}/down-argc.log")" "1"
}

# ── Unknown-subcommand guard (audit-71 C1) ──────────────────────────────────
# A bare unknown WORD must not fall through to cmd_harness: inside a project
# that path runs auto-update → auto-reinit → up → harness, so a typo like
# `devbot status` silently started a harness AND a destructive reinit. Flags
# (`-*`, including the `--` passthrough separator) keep the documented
# "unknown argument starts the harness" behaviour.

@test "a bare devbot still starts the harness" {
  run bash -c "source '${SANDBOX}/bin/devbot-lib'; cmd_harness() { echo HARNESS-STARTED; }; main"
  assert_success
  assert_output --partial "HARNESS-STARTED"
}

@test "harness flags still pass through to the harness start" {
  run bash -c "source '${SANDBOX}/bin/devbot-lib'; cmd_harness() { echo \"HARNESS-STARTED \$*\"; }; main --resume"
  assert_success
  assert_output --partial "HARNESS-STARTED --resume"
}

@test "the -- separator still passes through to the harness" {
  run bash -c "source '${SANDBOX}/bin/devbot-lib'; cmd_harness() { echo \"HARNESS-STARTED \$*\"; }; main -- -c 'two words'"
  assert_success
  assert_output --partial "HARNESS-STARTED -- -c two words"
}

@test "an unknown subcommand is refused, not treated as a harness start" {
  run bash -c "source '${SANDBOX}/bin/devbot-lib'; cmd_harness() { echo HARNESS-STARTED; }; main status"
  assert_failure
  refute_output --partial "HARNESS-STARTED"
  assert_output --partial "Unknown command"
}
