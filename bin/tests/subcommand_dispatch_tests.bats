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
