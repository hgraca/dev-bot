#!/usr/bin/env bats
# =============================================================================
# bin/tests/init_parallel_tests.bats
#
# `devbot init --all -j N` wires several projects at once. The runner is the
# part that must hold whatever the projects do: every project runs, a failure
# does not stop the others, output is reported in launch order instead of
# interleaved, and each worker keeps its own log. A nested project is wired only
# once its ancestor has finished.
#
# _process_project is replaced here — the fan-out itself is under test, not the
# wiring. Byte-level parity of a real parallel run against a serial one is a
# manual check (the wiring cannot be sandboxed).
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared"

  # Production init.sh with `main "$@"` stripped, so sourcing it only defines
  # functions. It resolves DEV_BOT_ROOT from its own path → $SANDBOX.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/init.sh" > "${SANDBOX}/bin/init-flow.sh"

  cat > "${SANDBOX}/src/_shared/functions.sh" <<'STUB'
#!/usr/bin/env bash
_header_1() { echo "== $*"; }
_header_2() { echo "-- $*"; }
_header_3() { echo "--- $*"; }
_info() { echo "INFO: $*"; }
_ok() { echo "OK: $*"; }
_skip() { echo "SKIP: $*"; }
_warn() { echo "WARN: $*"; }
_error() { echo "ERROR: $*"; }
_fatal() { echo "FATAL: $*" >&2; return 1; }
_log() { true; }
_step() { true; }
_fmt_duration() { echo "0s"; }
_devbot_global_config() { printf '%s' "${DEV_BOT_GLOBAL_CONFIG:-${DEV_BOT_ROOT}/.devbot.global.jsonc}"; }
_devbot_get_disabled_modules() { echo '[]'; }
_devbot_get_memory_search_provider() { echo "mdctx"; }
_devbot_memory_collection_field() { echo ""; }
_devbot_lock_wait() { return 0; }
_devbot_rebuild_external_module_config() { true; }
STUB

  # Real helpers, extracted verbatim so the stub cannot drift: the fan-out orders
  # projects by depth, and the library itself is stubbed here.
  {
    awk '/^_path_depth\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_order_paths_by_depth\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_path_is_nested_under\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_default_jobs\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
    awk '/^_canonical_project_path\(\) \{/,/^\}/' "${PROJECT_ROOT}/src/_shared/functions.sh"
  } >> "${SANDBOX}/src/_shared/functions.sh"

  export DEV_BOT_ROOT="${SANDBOX}"
  export PARALLEL_LOG="${SANDBOX}/runs.log"
  export PARALLEL_FAIL_ON="${SANDBOX}/fail-on"

  source "${SANDBOX}/bin/init-flow.sh"

  # Stand-in for the real wiring: records entry, fails on demand.
  _process_project() {
    local project="$1"
    printf 'start %s\n' "${project}" >> "${PARALLEL_LOG}"
    if [[ -f "${PARALLEL_FAIL_ON}" ]] && [[ "$(cat "${PARALLEL_FAIL_ON}")" == "${project}" ]]; then
      printf 'wiring failed for %s\n' "${project}"
      return 3
    fi
    printf 'wired %s\n' "${project}"
  }
}

teardown() {
  chmod -R u+w "${SANDBOX}" 2>/dev/null || true
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

@test "every project runs, and the report follows launch order" {
  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2" p3="${SANDBOX}/p3"
  mkdir -p "$p1" "$p2" "$p3"

  run _run_projects_parallel 2 "$p1" "$p2" "$p3"

  assert_success
  assert_equal "$(printf '%s\n' "$output" | grep -c '^OK: Project')" "3"
  assert_equal "$(printf '%s\n' "$output" | grep '^OK: Project' | head -1)" "OK: Project 1/3: $p1"
  assert_equal "$(printf '%s\n' "$output" | grep '^OK: Project' | tail -1)" "OK: Project 3/3: $p3"
}

@test "a nested project is wired after its ancestor, never beside it" {
  # A project's wiring writes no plugin package an ancestor supplies, so an
  # ancestor and its descendant wired together both write one and the host then
  # fails the duplicate plugin id.
  local parent="${SANDBOX}/parent" child="${SANDBOX}/parent/child"
  mkdir -p "$parent" "$child"

  # The parent holds its turn long enough that a concurrent run always records
  # the child starting first; a depth-ordered run cannot produce that at all.
  _process_project() {
    printf 'start %s\n' "$1" >> "${PARALLEL_LOG}"
    case "$1" in
      */child) ;;
      *) sleep 0.5 ;;
    esac
    printf 'end %s\n' "$1" >> "${PARALLEL_LOG}"
  }

  # The child is listed first: the order must come from nesting, not the list.
  run _run_projects_parallel 2 "$child" "$parent"

  assert_success
  local parent_end child_start
  parent_end="$(grep -nxF "end ${parent}" "${PARALLEL_LOG}" | cut -d: -f1)"
  child_start="$(grep -nxF "start ${child}" "${PARALLEL_LOG}" | cut -d: -f1)"
  [ -n "$parent_end" ]
  [ -n "$child_start" ]
  [ "$parent_end" -lt "$child_start" ]
}

@test "a failing project does not stop the others and fails the run" {
  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2" p3="${SANDBOX}/p3"
  mkdir -p "$p1" "$p2" "$p3"
  printf '%s' "$p2" > "${PARALLEL_FAIL_ON}"

  run _run_projects_parallel 2 "$p1" "$p2" "$p3"

  assert_failure
  assert_output --partial "Project 2/3: $p2 failed (exit 3)"
  assert_output --partial "log: ${SANDBOX}/storage/.init-all/02.log"
  # The other two still completed.
  assert_equal "$(printf '%s\n' "$output" | grep -c '^OK: Project')" "2"
  assert_equal "$(grep -c '^start ' "${PARALLEL_LOG}")" "3"
}

@test "a worker failure is aggregated when the caller suppresses errexit" {
  # main calls the runner as `... || failed=1`, which turns errexit off inside
  # it. The tests otherwise run with errexit on, so pin the production shape.
  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2"
  mkdir -p "$p1" "$p2"
  printf '%s' "$p2" > "${PARALLEL_FAIL_ON}"

  local rc=0
  _run_projects_parallel 2 "$p1" "$p2" >/dev/null 2>&1 || rc=$?

  assert_equal "${rc}" "1"
}

@test "reset scripts travel as arguments and reach the workers" {
  local p1="${SANDBOX}/p1"
  local reset="${SANDBOX}/reset.sh"
  mkdir -p "$p1"
  : > "$reset"

  _process_project() {
    printf 'reset-count=%s\n' "$#" >> "${PARALLEL_LOG}"
  }

  run _run_projects_parallel 1 "$p1" -- "$reset"

  assert_success
  assert_equal "$(cat "${PARALLEL_LOG}")" "reset-count=2"
}

@test "each worker keeps its own log, and stale logs are cleared" {
  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2"
  mkdir -p "$p1" "$p2"
  mkdir -p "${SANDBOX}/storage/.init-all"
  : > "${SANDBOX}/storage/.init-all/99.log"

  run _run_projects_parallel 3 "$p1" "$p2"

  assert_success
  run grep -l "wired $p1" "${SANDBOX}"/storage/.init-all/*.log
  assert_success
  run test -e "${SANDBOX}/storage/.init-all/99.log"
  assert_failure
}

@test "the default fan-out is half of nproc, clamped to 2..16" {
  cat > "${SANDBOX}/bin/nproc" <<'STUB'
#!/usr/bin/env bash
echo "${STUB_NPROC:-2}"
STUB
  chmod +x "${SANDBOX}/bin/nproc"
  export PATH="${SANDBOX}/bin:${PATH}"

  STUB_NPROC=8 run _default_jobs
  assert_output "4"

  STUB_NPROC=20 run _default_jobs
  assert_output "10"

  STUB_NPROC=2 run _default_jobs
  assert_output "2"

  STUB_NPROC=64 run _default_jobs
  assert_output "16"
}

@test "--jobs rejects a non-numeric value before doing any work" {
  # The real script: the sandbox copy has `main` stripped, so the parser is
  # only reachable through bin/init.sh. Parsing happens before any wiring.
  run bash "${PROJECT_ROOT}/bin/init.sh" --all -j two

  assert_failure
  assert_output --partial "--jobs expects a positive integer, got: two"
}

@test "a zero-padded --jobs is read as decimal, not octal" {
  # `-j 08` used to reach arithmetic as invalid octal and abort before wiring.
  # An empty project list keeps this to the parser: a real `--all` would wire
  # every project the developer has registered, including this checkout.
  local cfg
  cfg="$(mktemp)"
  printf '{"projects": {}}\n' > "${cfg}"
  run env DEV_BOT_GLOBAL_CONFIG="${cfg}" bash "${PROJECT_ROOT}/bin/init.sh" --all -j 08
  rm -f "${cfg}"

  # It must fail only because there is nothing to wire, never on the number.
  refute_output --partial "value too great for base"
  refute_output --partial "unbound variable"
}

# ── Parent passes ────────────────────────────────────────────────────────────

@test "the pre-pass registers every project in one batch" {
  cat > "${SANDBOX}/src/_shared/add_project.py" <<'STUB'
#!/usr/bin/env python3
import os, sys
with open(os.environ["BATCH_LOG"], "a") as f:
    f.write("%s\n" % " ".join(sys.argv[2:]))
STUB

  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2"
  mkdir -p "$p1" "$p2"
  printf '{ "projects": [] }\n' > "${SANDBOX}/.devbot.global.jsonc"
  export BATCH_LOG="${SANDBOX}/batch.log"

  run _run_global_pre_passes "$p1" "$p2"

  assert_success
  assert_equal "$(wc -l < "${BATCH_LOG}" | tr -d ' ')" "1"
  assert_output --partial "2 project(s) registered"
}

@test "the pre-pass merges external declarations once" {
  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2"
  mkdir -p "$p1" "$p2"
  printf '{ "projects": [] }\n' > "${SANDBOX}/.devbot.global.jsonc"
  _devbot_rebuild_external_module_config() { printf 'rebuild\n' >> "${SANDBOX}/rebuild.log"; }

  run _run_global_pre_passes "$p1" "$p2"

  assert_success
  assert_equal "$(wc -l < "${SANDBOX}/rebuild.log" | tr -d ' ')" "1"
}

@test "the pre-pass rebuilds the shared store once per distinct target" {
  mkdir -p "${SANDBOX}/src/agentic/memory"
  cat > "${SANDBOX}/src/agentic/memory/init.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "${MEMORY_LOG}"
STUB

  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2"
  mkdir -p "$p1" "$p2"
  export MEMORY_LOG="${SANDBOX}/memory.log"

  # Same provider, path and index for both → one build.
  run _run_global_pre_passes "$p1" "$p2"
  assert_success
  assert_equal "$(wc -l < "${MEMORY_LOG}" | tr -d ' ')" "1"

  # Distinct stores → one build each.
  rm -f "${MEMORY_LOG}"
  _devbot_memory_collection_field() { printf '/store/%s' "$(basename "$1")"; }
  run _run_global_pre_passes "$p1" "$p2"
  assert_success
  assert_equal "$(wc -l < "${MEMORY_LOG}" | tr -d ' ')" "2"
}

@test "the pre-pass leaves the shared store alone when the memory module is disabled" {
  mkdir -p "${SANDBOX}/src/agentic/memory"
  cat > "${SANDBOX}/src/agentic/memory/init.sh" <<'STUB'
#!/usr/bin/env bash
printf 'called\n' >> "${MEMORY_LOG}"
STUB

  local p1="${SANDBOX}/p1"
  mkdir -p "$p1"
  export MEMORY_LOG="${SANDBOX}/memory.log"
  _devbot_get_disabled_modules() { echo '["memory"]'; }

  run _run_global_pre_passes "$p1"

  assert_success
  run test -e "${MEMORY_LOG}"
  assert_failure
}

@test "the post-pass prunes the module mirror exactly once" {
  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2"
  mkdir -p "$p1" "$p2"
  _prune_orphaned_external_modules() { printf 'prune\n' >> "${SANDBOX}/prune.log"; }

  run _run_global_post_passes "$p1" "$p2"

  assert_success
  assert_equal "$(wc -l < "${SANDBOX}/prune.log" | tr -d ' ')" "1"
}

@test "projects that are not nested run together whatever their depth" {
  # Depth orders projects; only nesting holds one back behind another.
  local shallow="${SANDBOX}/shallow" deep="${SANDBOX}/group/deep"
  mkdir -p "$shallow" "$deep"

  _process_project() {
    printf 'start %s\n' "$1" >> "${PARALLEL_LOG}"
    case "$1" in
      */shallow) sleep 0.5 ;;
    esac
    printf 'end %s\n' "$1" >> "${PARALLEL_LOG}"
  }

  run _run_projects_parallel 2 "$shallow" "$deep"

  assert_success
  local shallow_end deep_start
  shallow_end="$(grep -nxF "end ${shallow}" "${PARALLEL_LOG}" | cut -d: -f1)"
  deep_start="$(grep -nxF "start ${deep}" "${PARALLEL_LOG}" | cut -d: -f1)"
  [ -n "$shallow_end" ]
  [ -n "$deep_start" ]
  [ "$deep_start" -lt "$shallow_end" ]
}

@test "a nested project starts when its own ancestor ends, not another's" {
  local slow="${SANDBOX}/slow" parent="${SANDBOX}/group/parent" child="${SANDBOX}/group/parent/child"
  mkdir -p "$slow" "$parent" "$child"

  _process_project() {
    printf 'start %s\n' "$1" >> "${PARALLEL_LOG}"
    case "$1" in
      */slow) sleep 1 ;;
    esac
    printf 'end %s\n' "$1" >> "${PARALLEL_LOG}"
  }

  run _run_projects_parallel 2 "$slow" "$parent" "$child"

  assert_success
  local slow_end child_start
  slow_end="$(grep -nxF "end ${slow}" "${PARALLEL_LOG}" | cut -d: -f1)"
  child_start="$(grep -nxF "start ${child}" "${PARALLEL_LOG}" | cut -d: -f1)"
  [ -n "$slow_end" ]
  [ -n "$child_start" ]
  [ "$child_start" -lt "$slow_end" ]
}

@test "a project reached through a symlink still waits for its ancestor" {
  local real="${SANDBOX}/real/parent" link="${SANDBOX}/link"
  mkdir -p "${real}/child"
  ln -s "${real}" "${link}"

  _process_project() {
    printf 'start %s\n' "$1" >> "${PARALLEL_LOG}"
    case "$1" in
      */parent) sleep 0.5 ;;
    esac
    printf 'end %s\n' "$1" >> "${PARALLEL_LOG}"
  }

  run _run_projects_parallel 2 "${real}" "${link}/child"

  assert_success
  local parent_end child_start
  parent_end="$(grep -nxF "end ${real}" "${PARALLEL_LOG}" | cut -d: -f1)"
  child_start="$(grep -nxF "start ${real}/child" "${PARALLEL_LOG}" | cut -d: -f1)"
  [ -n "$parent_end" ]
  [ -n "$child_start" ]
  [ "$parent_end" -lt "$child_start" ]
}

@test "one physical project is wired once however it is spelled" {
  local real="${SANDBOX}/real/project" link="${SANDBOX}/link"
  mkdir -p "${real}"
  ln -s "${real}" "${link}"

  _process_project() {
    printf 'start %s\n' "$1" >> "${PARALLEL_LOG}"
  }

  run _run_projects_parallel 2 "${real}" "${link}"

  assert_success
  assert_equal "$(grep -c '^start ' "${PARALLEL_LOG}")" "1"
}
