#!/usr/bin/env bats
# =============================================================================
# bin/tests/init_reset_path_tests.bats
#
# `devbot init` on an already-initialised project runs the reset path before
# wiring: every module reset.sh, a wipe of `<devbot_dir>/memory/active/modules/`
# and the removal of the pre-modules memory files. Module memory is generated
# output — every enabled module rewrites its own file during wiring, so a module
# that is disabled now must leave nothing behind.
#
# A project that was never initialised takes the wiring-only path: none of the
# resets run.
#
# The wiring itself is stubbed: the real one needs the whole helper surface and
# is covered by init_tests.bats / the e2e fixture. The stub records what the
# reset path handed it.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  PROJECT="$(mktemp -d)"
  OTHER="$(mktemp -d)"
  FRESH="$(mktemp -d)"

  command -v python3 &>/dev/null || skip "python3 not installed"

  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared"
  # Production init.sh under a non-colliding name, `main "$@"` stripped so the
  # test can source it. It resolves DEV_BOT_ROOT to $SANDBOX from its own path.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/init.sh" > "${SANDBOX}/bin/init-flow.sh"

  # The wiring child `_wire_project` spawns: records the project it was handed
  # and whether the module memory folder still existed at that moment.
  cat > "${SANDBOX}/bin/init.sh" <<'WIRE'
#!/usr/bin/env bash
project="$1"
devbot_dir="${DEVBOT_DIR_STUB:-.agents}"
if [[ -d "${project}/${devbot_dir}/memory/active/modules" ]]; then
  echo present > "${INIT_LOG}.modules"
else
  echo absent > "${INIT_LOG}.modules"
fi
printf "%s\n" "$project" > "${INIT_LOG}.project"
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
_get_projects() { echo '[]'; }
TEXT_BOLD=''; TEXT_BLUE=''; TEXT_CLEAR=''; TEXT_DIM=''
TEXT_GREEN=''; TEXT_YELLOW=''; TEXT_ORANGE=''; TEXT_RED=''
STUB

  # Real helpers, extracted verbatim so the stub cannot drift.
  {
    awk '/^_devbot_is_plain_relative_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_module_memory_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_devbot_project_initialized\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
  } >> "${SANDBOX}/src/_shared/functions.sh"

  printf '{}\n' > "${SANDBOX}/.devbot.global.jsonc"
  printf '{"project_name": "demo"}\n' > "${PROJECT}/.devbot.project.jsonc"
  printf '{"project_name": "other"}\n' > "${OTHER}/.devbot.project.jsonc"

  export INIT_LOG="${SANDBOX}/init.log"
}

teardown() {
  rm -rf "${SANDBOX}" "${PROJECT}" "${OTHER}" "${FRESH}" 2>/dev/null || true
}

# Run the sandboxed init flow through main(). The wiring is the fake child
# `bin/init.sh`, which records what the reset path handed it.
_run_init() {
  SANDBOX="${SANDBOX}" INIT_LOG="${INIT_LOG}" RUN_DIR="${RUN_DIR:-}" \
    bash -c '
    export DEV_BOT_ROOT="$SANDBOX"
    cd "${RUN_DIR:-$DEV_BOT_ROOT}" || exit 1
    source "${DEV_BOT_ROOT}/bin/init-flow.sh"
    main "$@"
  ' _ "$@"
}

@test "init clears the module memory folder before wiring runs" {
  mkdir -p "${PROJECT}/.agents/memory/active/modules"
  printf '# stale\n' > "${PROJECT}/.agents/memory/active/modules/k8s.md"

  run _run_init "${PROJECT}"

  assert_success
  assert_equal "$(cat "${INIT_LOG}.modules")" "absent"
  refute [ -e "${PROJECT}/.agents/memory/active/modules" ]
}

@test "init leaves the rest of the vault alone" {
  mkdir -p "${PROJECT}/.agents/memory/active/modules"
  printf '# stale\n' > "${PROJECT}/.agents/memory/active/modules/k8s.md"
  printf '# project\n' > "${PROJECT}/.agents/memory/active/project.md"

  run _run_init "${PROJECT}"

  assert_success
  assert [ -f "${PROJECT}/.agents/memory/active/project.md" ]
}

@test "init is harmless when the module memory folder does not exist" {
  run _run_init "${PROJECT}"

  assert_success
  assert_equal "$(cat "${INIT_LOG}.modules")" "absent"
}

@test "init accepts a positional project path" {
  run _run_init "${OTHER}"

  assert_success
  assert_equal "$(cat "${INIT_LOG}.project")" "${OTHER}"
}

@test "init without a path processes the current directory" {
  RUN_DIR="${PROJECT}" run _run_init

  assert_success
  assert_equal "$(cat "${INIT_LOG}.project")" "${PROJECT}"
}

@test "init rejects a path that is not a directory" {
  run _run_init "${SANDBOX}/does-not-exist"

  assert_failure
  assert_output --partial "Not a directory"
}

@test "init refuses to combine --all with a project path" {
  run _run_init "${OTHER}" --all

  assert_failure
  assert_output --partial "Cannot combine --all"
}

@test "init removes the pre-modules memory files" {
  # A disabled module's init.sh never runs, so the migration cannot live there.
  mkdir -p "${PROJECT}/.agents/memory/active"
  printf '# g\n' > "${PROJECT}/.agents/memory/active/graphify.md"
  printf '# a\n' > "${PROJECT}/.agents/memory/active/aws-agent-rules.md"
  printf '# p\n' > "${PROJECT}/.agents/memory/active/project.md"

  run _run_init "${PROJECT}"

  assert_success
  refute [ -e "${PROJECT}/.agents/memory/active/graphify.md" ]
  refute [ -e "${PROJECT}/.agents/memory/active/aws-agent-rules.md" ]
  assert [ -f "${PROJECT}/.agents/memory/active/project.md" ]
}

# ── Detection: a never-initialised project keeps its resets untouched ────────

@test "a project without a project config takes the wiring-only path" {
  # Contrived leftover: the point is that the reset path does not run, so
  # nothing is wiped and the wiring receives the project as-is.
  mkdir -p "${FRESH}/.agents/memory/active/modules"
  printf '# keep\n' > "${FRESH}/.agents/memory/active/modules/k8s.md"

  run _run_init "${FRESH}"

  assert_success
  assert_equal "$(cat "${INIT_LOG}.modules")" "present"
  assert [ -f "${FRESH}/.agents/memory/active/modules/k8s.md" ]
  assert_equal "$(cat "${INIT_LOG}.project")" "${FRESH}"
}

@test "a project config is enough even when the wiring baseline is missing" {
  # The baseline is cleared by every run and absent after a crash; it must not
  # decide the branch.
  mkdir -p "${PROJECT}/.agents/memory/active/modules"
  printf '# stale\n' > "${PROJECT}/.agents/memory/active/modules/k8s.md"
  refute [ -e "${PROJECT}/.devbot.project.sha" ]

  run _run_init "${PROJECT}"

  assert_success
  assert_equal "$(cat "${INIT_LOG}.modules")" "absent"
}

# ── Containment ──────────────────────────────────────────────────────────────

@test "init refuses a devbot_dir that escapes the project" {
  mkdir -p "${PROJECT}/.agents/memory/active/modules"
  printf '# stale\n' > "${PROJECT}/.agents/memory/active/modules/k8s.md"
  export DEVBOT_DIR_STUB="../outside"

  run _run_init "${PROJECT}"

  assert_failure
  assert_output --partial "not a plain relative path"
  assert [ -f "${PROJECT}/.agents/memory/active/modules/k8s.md" ]
  refute [ -e "${INIT_LOG}.project" ]
}

@test "init refuses an absolute devbot_dir" {
  mkdir -p "${PROJECT}/.agents/memory/active/modules"
  printf '# stale\n' > "${PROJECT}/.agents/memory/active/modules/k8s.md"
  export DEVBOT_DIR_STUB="/tmp"

  run _run_init "${PROJECT}"

  assert_failure
  assert_output --partial "not a plain relative path"
  assert [ -f "${PROJECT}/.agents/memory/active/modules/k8s.md" ]
}

@test "init refuses a modules folder that symlinks outside the project" {
  local outside
  outside="$(mktemp -d)"
  mkdir -p "${outside}/modules"
  printf '# stale\n' > "${outside}/modules/k8s.md"
  mkdir -p "${PROJECT}/.agents/memory/active"
  ln -s "${outside}/modules" "${PROJECT}/.agents/memory/active/modules"

  run _run_init "${PROJECT}"

  assert_failure
  assert_output --partial "is a symlink"
  assert [ -f "${outside}/modules/k8s.md" ]
  # Wiring must not run: the module writers would recreate the escaped folder.
  refute [ -e "${INIT_LOG}.project" ]
  rm -rf "${outside}"
}

@test "init refuses a memory vault that symlinks outside the project" {
  local outside
  outside="$(mktemp -d)"
  printf '# stale\n' > "${outside}/graphify.md"
  mkdir -p "${PROJECT}/.agents/memory"
  ln -s "${outside}" "${PROJECT}/.agents/memory/active"

  run _run_init "${PROJECT}"

  assert_failure
  assert_output --partial "is a symlink"
  assert [ -f "${outside}/graphify.md" ]
  refute [ -e "${INIT_LOG}.project" ]
  rm -rf "${outside}"
}

@test "init refuses a symlinked modules folder even when it stays in the project" {
  mkdir -p "${PROJECT}/.agents/memory/active/target"
  printf '# stale\n' > "${PROJECT}/.agents/memory/active/target/k8s.md"
  ln -s "${PROJECT}/.agents/memory/active/target" "${PROJECT}/.agents/memory/active/modules"

  run _run_init "${PROJECT}"

  assert_failure
  assert_output --partial "is a symlink"
  assert [ -L "${PROJECT}/.agents/memory/active/modules" ]
  assert [ -f "${PROJECT}/.agents/memory/active/target/k8s.md" ]
  refute [ -e "${INIT_LOG}.project" ]
}

@test "init rejects more than one positional argument" {
  run _run_init "${PROJECT}" "${OTHER}"

  assert_failure
  assert_output --partial "Too many arguments"
  refute [ -e "${INIT_LOG}.project" ]
}
