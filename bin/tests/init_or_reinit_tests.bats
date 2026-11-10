#!/usr/bin/env bats
# =============================================================================
# bin/tests/init_or_reinit_tests.bats
#
# `devbot init` is the single lifecycle command: a project that is not
# initialised is wired from scratch; an initialised one is reset first. This
# file pins the dispatch (which branch runs), the argument parsing that used to
# live only in reinit.sh, and the in-process hand-off from the reset path to the
# wiring — a child `bash bin/init.sh` would re-enter detection and recurse.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  FRESH="$(mktemp -d)"
  INITED="$(mktemp -d)"
  OTHER="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"

  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared"
  # Production init.sh under a non-colliding name, `main "$@"` stripped so the
  # test can source it. It resolves DEV_BOT_ROOT to $SANDBOX from its own path.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/init.sh" > "${SANDBOX}/bin/init-flow.sh"
  cp "${PROJECT_ROOT}/src/_shared/read_jsonc.py" "${SANDBOX}/src/_shared/read_jsonc.py"
  cp "${PROJECT_ROOT}/src/_shared/migrate_workspace_config.py" "${SANDBOX}/src/_shared/"

  # The wiring child `_wire_project` spawns. Records the call and exits with
  # WIRE_RC, so the tests drive the real child-process boundary.
  cat > "${SANDBOX}/bin/init.sh" <<'WIRE'
#!/usr/bin/env bash
[[ -n "${WIRE_LOG:-}" ]] && echo "WIRING" >> "${WIRE_LOG}"
echo "WIRING"
exit "${WIRE_RC:-0}"
WIRE
  chmod +x "${SANDBOX}/bin/init.sh"

  cat > "${SANDBOX}/src/_shared/functions.sh" <<'STUB'
#!/usr/bin/env bash
_header_1() { true; }
_header_2() { echo "$*"; }
_header_3() { true; }
_info() { echo "INFO: $*"; }
_ok() { true; }
_skip() { true; }
_warn() { echo "WARN: $*"; }
_log() { true; }
_step() { true; }
_error() { echo "ERROR: $*" >&2; }
_fatal() { echo "FATAL: $*" >&2; exit 1; }
_fmt_duration() { echo "0s"; }
_devbot_global_config() { printf '%s' "${DEV_BOT_GLOBAL_CONFIG:-${DEV_BOT_ROOT}/.devbot.global.jsonc}"; }
_devbot_get_disabled_modules() { echo '[]'; }
_devbot_get_project_dir() { echo "${DEVBOT_DIR_STUB:-.agents}"; }
_devbot_clear_config_sha() { true; }
_devbot_write_config_sha() { true; }
_devbot_missing_mcp_env_vars() { true; }
_devbot_present_missing_env_vars() { true; }
_devbot_get_external_modules() { true; }
_devbot_disabled_external_names() { true; }
_collect_module_scripts() { true; }
_get_projects() { printf '%s\n' "${PROJECTS_JSON:-[]}"; }
TEXT_BOLD=''; TEXT_BLUE=''; TEXT_CLEAR=''; TEXT_DIM=''
TEXT_GREEN=''; TEXT_YELLOW=''; TEXT_ORANGE=''; TEXT_RED=''
STUB

  # Real helpers, extracted verbatim so the stub cannot drift.
  {
    awk '/^_devbot_is_plain_relative_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_module_memory_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_project_initialized\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_migrate_workspace_config\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
  } >> "${SANDBOX}/src/_shared/functions.sh"

  printf '{"project_name": "inited"}\n' > "${INITED}/.devbot.project.jsonc"
}

teardown() {
  rm -rf "${SANDBOX}" "${FRESH}" "${INITED}" "${OTHER}" 2>/dev/null || true
}

# Run a snippet in a child shell that sources the sandboxed init flow. Passed
# through the environment, so the snippet is evaluated by the inner shell after
# the library is loaded (and can override any function it just defined).
_sandbox_bash() {
  SANDBOX="${SANDBOX}" SNIPPET="$1" bash -c '
    export DEV_BOT_ROOT="$SANDBOX"
    cd "$SANDBOX" || exit 1
    source ./bin/init-flow.sh
    eval "$SNIPPET"
  '
}

# ── Dispatch: initialised vs not ─────────────────────────────────────────────

@test "an uninitialised project runs the wiring only" {
  run _sandbox_bash '_reinit_project() { echo REINIT; }; _process_project "'"${FRESH}"'"'

  assert_success
  assert_output --partial "WIRING"
  refute_output --partial "REINIT"
}

@test "an initialised project runs the reset path first" {
  run _sandbox_bash '_reinit_project() { echo REINIT; }; _process_project "'"${INITED}"'"'

  assert_success
  assert_output --partial "REINIT"
  refute_output --partial "WIRING"
}

# ── Argument parsing (moved out of reinit.sh) ────────────────────────────────

@test "init --all processes every registered project" {
  run _sandbox_bash "_get_projects() { printf '%s\\n' '[\"${FRESH}\",\"${OTHER}\"]'; }; _process_project() { echo PROCESS \"\$1\"; }; main --all"

  assert_success
  assert_output --partial "PROCESS ${FRESH}"
  assert_output --partial "PROCESS ${OTHER}"
}

@test "init refuses --all together with a project path" {
  run _sandbox_bash "main '${OTHER}' --all"

  assert_failure
  assert_output --partial "Cannot combine --all"
}

@test "init refuses an unknown option instead of treating it as a path" {
  run _sandbox_bash 'main --ful'

  assert_failure
  assert_output --partial "Unknown option"
}

@test "init refuses a second positional argument" {
  run _sandbox_bash "main '${OTHER}' '${FRESH}'"

  assert_failure
  assert_output --partial "Too many arguments"
}

@test "init --help documents both lifecycle paths" {
  run _sandbox_bash 'main --help'

  assert_success
  assert_output --partial "devbot init"
  assert_output --partial "--all"
  assert_output --partial "--full"
}

@test "init with no path processes the current directory" {
  run _sandbox_bash '_process_project() { echo "PROCESS $1"; }; cd "'"${FRESH}"'" && main'

  assert_success
  assert_output --partial "PROCESS ${FRESH}"
}

@test "init rejects a path that is not a directory" {
  run _sandbox_bash "main '${SANDBOX}/does-not-exist'"

  assert_failure
  assert_output --partial "Not a directory"
}

@test "init skips a registered project whose directory is gone" {
  run _sandbox_bash "_process_project '${FRESH}/gone'"

  assert_success
  assert_output --partial "Directory does not exist"
}

@test "init --all reads the global config from DEV_BOT_GLOBAL_CONFIG" {
  printf '{"projects": ["%s"]}\n' "${OTHER}" > "${SANDBOX}/custom-global.jsonc"

  run _sandbox_bash "DEV_BOT_GLOBAL_CONFIG='${SANDBOX}/custom-global.jsonc' _get_projects"

  assert_success
  assert_output --partial "${OTHER}"
}

# ── Reset path ───────────────────────────────────────────────────────────────

@test "the reset path runs the reset scripts before the wiring, in a child" {
  cat > "${SANDBOX}/fake-reset.sh" <<EOF
#!/usr/bin/env bash
echo "RESET \$1" >> "${SANDBOX}/order.log"
EOF
  chmod +x "${SANDBOX}/fake-reset.sh"

  run _sandbox_bash "export WIRE_LOG='${SANDBOX}/order.log'; _reinit_project '${INITED}' '${SANDBOX}/fake-reset.sh'"

  assert_success
  run cat "${SANDBOX}/order.log"
  assert_line --index 0 "RESET ${INITED}"
  assert_line --index 1 "WIRING"
}

@test "the reset path forwards --full to the reset scripts" {
  cat > "${SANDBOX}/fake-reset.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${SANDBOX}/reset-args.log"
EOF
  chmod +x "${SANDBOX}/fake-reset.sh"

  run _sandbox_bash "FULL_RESET=true; _reinit_project '${INITED}' '${SANDBOX}/fake-reset.sh'"

  assert_success
  run cat "${SANDBOX}/reset-args.log"
  assert_output --partial "--full"
}

@test "the reset path omits --full for a plain init" {
  cat > "${SANDBOX}/fake-reset.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${SANDBOX}/reset-args.log"
EOF
  chmod +x "${SANDBOX}/fake-reset.sh"

  run _sandbox_bash "FULL_RESET=false; _reinit_project '${INITED}' '${SANDBOX}/fake-reset.sh'"

  assert_success
  run cat "${SANDBOX}/reset-args.log"
  refute_output --partial "--full"
}

# ── Failure propagation ──────────────────────────────────────────────────────
# The wiring runs in a child so an uncaught error keeps its non-zero status:
# a function called under `if`/`||` loses errexit for its whole body.

@test "a fresh-project wiring failure fails init" {
  run _sandbox_bash "export WIRE_RC=1; _process_project '${FRESH}'"

  assert_failure
}

@test "a reset-path wiring failure fails init" {
  run _sandbox_bash "export WIRE_RC=1; _reinit_project '${INITED}'"

  assert_failure
}

@test "main exits non-zero when the wiring fails" {
  run _sandbox_bash "export WIRE_RC=1; main '${INITED}'"

  assert_failure
  refute_output --partial "DevBot init complete"
}

# ── Workspace-block migration ────────────────────────────────────────────────
# The schema rewrite is covered by migrate_workspace_config_tests.bats; these
# pin that init actually invokes it, per project and for the global config.

@test "_init_wiring migrates the project config it wires" {
  printf '{ "monorepo": true, "commit_memory": true }\n' > "${OTHER}/.devbot.project.jsonc"

  run _sandbox_bash "_init_wiring '${OTHER}' >/dev/null 2>&1 || true"

  run cat "${OTHER}/.devbot.project.jsonc"
  assert_output --partial '"type": "polyrepo"'
  assert_output --partial '"commit_memory": true'
  refute_output --partial '"monorepo"'
}

@test "init wires both migration call sites" {
  # Removing either line leaves every existing config unmigrated while the
  # end-to-end test above stayed green.
  grep -qF '_migrate_workspace_config "${PROJECT_DIR}/.devbot.project.jsonc"' "${PROJECT_ROOT}/bin/init.sh"
  grep -qF '_migrate_workspace_config "$(_devbot_global_config)"' "${PROJECT_ROOT}/bin/init.sh"
}
