# =============================================================================
# src/_shared/tests/lib/scenario.bash
#
# One tool invocation per distinct input, instead of one per assertion.
#
# A scenario is a directory the tool under test has been run against exactly
# once per file. Tests that only read the result share it; tests that mutate
# first take a copy. The input — the "configuration set" — is whatever the
# file's builder writes into the directory before running the tool, so a
# scenario is named for the seed that makes it distinct.
#
# Load from a .bats file with:
#   load "${BATS_TEST_DIRNAME}/<relative>/scenario"
#
# The file supplies one builder, which receives the scenario name and the
# directory, writes the input and runs the tool:
#
#   _build_scenario() {
#     local name="$1" dir="$2"
#     printf '{ "harness": "opencode-v2" }\n' > "${dir}/.devbot.project.jsonc"
#     case "${name}" in
#       default) ;;
#       stale-link) ln -sfn /nowhere "${dir}/.opencode/gone.ts" ;;
#     esac
#     bash "${MODULE_DIR}/init.sh" "${dir}"
#   }
#   scenario() { scenario_once "$1" _build_scenario; }
#
# bats runs one file's tests on one process, in order, so building on first use
# is race-free. Trees live under BATS_FILE_TMPDIR (per file) and copies under
# BATS_TEST_TMPDIR (per test, removed by bats).
# =============================================================================

# scenario_once <name> <builder-function>
#   Builds the scenario on first use in this file, then sets SCENARIO to it.
#   The builder's stdout/stderr are kept beside the tree, and a non-zero status
#   fails the test that first asked for the scenario rather than passing quietly.
scenario_once() {
  local name="$1" build="$2" dir status
  dir="${BATS_FILE_TMPDIR}/scenarios/${name}"
  if [[ ! -d "${dir}" ]]; then
    mkdir -p "${dir}"
    "${build}" "${name}" "${dir}" >"${dir}.out" 2>&1
    printf '%s' "$?" >"${dir}.status"
  fi
  SCENARIO="${dir}"
  status="$(cat "${dir}.status" 2>/dev/null || printf '0')"
  if [[ "${status}" != "0" ]]; then
    output="$(cat "${dir}.out" 2>/dev/null || true)"
    fail "scenario '${name}': the tool under test failed (status ${status})"
  fi
}

# scenario_copy_once <name> <builder-function>
#   The scenario's tree, copied into this test's own directory: for a test that
#   plants a file and re-runs the tool, or resets, without disturbing the shared
#   tree. Copies keep the scenario's absolute paths, so a test asserting on those
#   re-runs the tool after it seeds.
scenario_copy_once() {
  scenario_once "$@"
  local copy="${BATS_TEST_TMPDIR}/scenario"
  mkdir -p "${copy}"
  cp -a "${SCENARIO}/." "${copy}/"
  SCENARIO="${copy}"
}

# scenario_output <name>
#   Loads the captured output of the scenario's run into $output/$status, so an
#   assertion about what the tool reported keeps its shape without a second run.
#   shellcheck disable=SC2034  # $output/$status are read by bats-assert
scenario_output() {
  local dir="${BATS_FILE_TMPDIR}/scenarios/$1"
  output="$(cat "${dir}.out" 2>/dev/null || true)"
  status="$(cat "${dir}.status" 2>/dev/null || printf '0')"
}
