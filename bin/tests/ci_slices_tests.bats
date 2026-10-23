#!/usr/bin/env bats
# =============================================================================
# bin/tests/ci_slices_tests.bats
# Tree-wide conventions for the CI test job's BATS slices.
#
# The `test-slice` job in .github/workflows/ci.yml runs the BATS suite as three
# parallel jobs (a build matrix), each taking `make test-bats-slice SLICE=n`.
# The partition is computed by bin/test-slices.sh, never listed, so a new test
# file cannot be forgotten — but a broken partition would still pass CI while
# silently not running someone's tests, and a broken handoff to bats would pass
# while running everything three times. These are repo-level guards, not
# behavioural tests: they fail the moment either stops holding.
# =============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
# Must match the `slice:` matrix in .github/workflows/ci.yml.
SLICES=3

setup_file() {
  local slice
  for slice in $(seq 1 "${SLICES}"); do
    "${PROJECT_ROOT}/bin/test-slices.sh" "${slice}" "${SLICES}" >"${BATS_FILE_TMPDIR}/slice-${slice}"
  done
}

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert
}

# The files assigned to slice $1, one per line, as paths relative to the repo root.
_slice_files() {
  cat "${BATS_FILE_TMPDIR}/slice-$1"
}

# All BATS files the suite runs, one per line, as bin/test-slices.sh reports them.
_all_files() {
  (cd "${PROJECT_ROOT}" && git -c core.quotePath=false ls-files 'bin/*.bats' 'src/*.bats' | LC_ALL=C sort)
}

# Run a command with make's own plumbing stripped from the environment. This
# guard test runs inside a slice, i.e. under `make test-bats-slice`, which
# exports SLICE, BATS_FILES_FILE and MAKEFLAGS (including that SLICE) into every
# recipe — inherited, they would make the invocation under test exercise the
# outer slice instead of the one the test constructs.
_make_clean() {
  env -u SLICE -u BATS_FILES_FILE -u MAKEFLAGS -u MFLAGS -u MAKELEVEL "$@"
}

# Number of @test cases in the given files. The partition weighs cases and file
# size together, so this only approximates it — enough to catch a slice that
# stopped taking its share.
_test_count() {
  local file total=0
  for file in "$@"; do
    total=$((total + $(grep -c -e '^[[:blank:]]*@test' -- "${PROJECT_ROOT}/${file}" || true)))
  done
  echo "${total}"
}

@test "the slices cover every BATS file exactly once" {
  local covered expected
  covered="$(for slice in $(seq 1 "${SLICES}"); do _slice_files "${slice}"; done | LC_ALL=C sort)"
  expected="$(_all_files)"

  [ -n "${expected}" ] || {
    echo "git ls-files found no .bats files — not a repo checkout?"
    return 1
  }
  if [ "${covered}" != "${expected}" ]; then
    echo "the slices do not partition the BATS suite; missing from every slice:"
    comm -13 <(echo "${covered}") <(echo "${expected}")
    echo "assigned more than once:"
    echo "${covered}" | uniq -d
    return 1
  fi
}

@test "the slices carry about a third of the suite each" {
  # A slice may sit under a third — the partition cannot split a file, and it
  # weighs runtime rather than cases — but a slice well above or below the
  # average means the partition stopped partitioning, and the job's wall clock
  # goes back to where it was before the split.
  local slice count total ceiling floor
  total="$(_test_count $(_all_files))"
  ceiling=$(((total + SLICES - 1) / SLICES * 6 / 5))
  floor=$((total * 3 / (5 * SLICES)))
  for slice in $(seq 1 "${SLICES}"); do
    # shellcheck disable=SC2046 # word splitting over the slice's paths is intended
    count="$(_test_count $(_slice_files "${slice}"))"
    if [ "${count}" -gt "${ceiling}" ] || [ "${count}" -lt "${floor}" ]; then
      echo "slice ${slice} carries ${count} of ${total} tests, outside ${floor}..${ceiling}"
      return 1
    fi
  done
}

@test "an out-of-range or missing SLICE fails instead of running nothing" {
  local slice
  for slice in "" 0 4 all; do
    run _make_clean sh -c "cd '${PROJECT_ROOT}' && make -s test-bats-slice ${slice:+SLICE=${slice}} FILES_ONLY=1"
    [ "${status}" -ne 0 ] || {
      echo "SLICE='${slice}' exited 0 — a workflow typo would run an empty slice"
      return 1
    }
  done
}

# The three slices only buy speed if `test-bats` runs the list it is handed. If
# it falls back to the whole tree, every job runs the full suite, stays green,
# and the split silently does nothing — so record what bats is actually given.
@test "test-bats runs the listed files, not the whole tree" {
  local shim="${BATS_TEST_TMPDIR}/shim" argv="${BATS_TEST_TMPDIR}/argv"
  _bats_shim "${shim}"
  printf '%s\n' "bin/tests/a_tests.bats" "src/b_tests.bats" >"${BATS_TEST_TMPDIR}/files"

  _make_clean env BATS_ARGV_FILE="${argv}" PATH="${shim}:${PATH}" \
    make -s -C "${PROJECT_ROOT}" test-bats BATS_FILES_FILE="${BATS_TEST_TMPDIR}/files"

  run cat "${argv}"
  assert_success
  assert_line "bin/tests/a_tests.bats"
  assert_line "src/b_tests.bats"
  refute_line "-r"
}

@test "test-bats falls back to the whole tree when given no list" {
  local shim="${BATS_TEST_TMPDIR}/shim" argv="${BATS_TEST_TMPDIR}/argv"
  _bats_shim "${shim}"

  _make_clean env BATS_ARGV_FILE="${argv}" PATH="${shim}:${PATH}" \
    make -s -C "${PROJECT_ROOT}" test-bats

  run cat "${argv}"
  assert_success
  assert_line "-r"
  assert_line "bin/"
  assert_line "src/"
}

# A fake `bats` that records its arguments to $BATS_ARGV_FILE and succeeds, so a
# test can assert what test-bats invoked without running the suite.
_bats_shim() {
  mkdir -p "$1"
  cat >"$1/bats" <<'SHIM'
#!/bin/sh
printf '%s\n' "$@" > "${BATS_ARGV_FILE}"
SHIM
  chmod +x "$1/bats"
}
