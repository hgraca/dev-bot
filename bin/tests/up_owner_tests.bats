#!/usr/bin/env bats
# =============================================================================
# bin/tests/up_owner_tests.bats
# Tests for `devbot up --owner`: a caller that is not a devbot session claims
# the stack, so the last-session teardown (and an explicit `devbot down`) leaves
# it alone until that owner releases it. herdr is the first such caller.
#
# Covers:
#   - --owner / --owner-pid parsing (explicit pid, default pid, refusals)
#   - a completed start records the claim
#   - a SKIPPED start records it too (the stack is up either way)
#   - a plain start records nothing (sessions stay the implicit owners)
#   - a failed start records nothing
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX="$(mktemp -d)"
  export SANDBOX

  mkdir -p "${SANDBOX}/bin" "${SANDBOX}/src/_shared"

  # The callable half of up.sh — everything but the `main "$@"` tail — so the
  # option parsing and the owner hook can be driven without booting anything.
  sed '/^main "\$@"/d' "${PROJECT_ROOT}/bin/up.sh" >"${SANDBOX}/bin/up.sh.src"

  # Minimal shared library: the primitives up.sh's parse block and owner hook
  # call. The claim itself is recorded, not written — the registry primitives
  # are tested in src/_shared/tests/devbot_sessions_tests.bats.
  cat >"${SANDBOX}/src/_shared/functions.sh" <<'STUB'
#!/usr/bin/env bash
_header_1() { true; }
_header_2() { true; }
_header_3() { true; }
_info() { true; }
_ok() { true; }
_skip() { true; }
_log() { true; }
_warn() { echo "WARN: $*"; }
_error() { echo "ERROR: $*" >&2; }
_fatal() { echo "FATAL: $*" >&2; }
_fmt_duration() { echo "0s"; }
TEXT_BOLD=''
TEXT_BLUE=''
TEXT_CLEAR=''
TEXT_DIM=''
TEXT_GREEN=''
TEXT_ORANGE=''
TEXT_RED=''
TEXT_YELLOW=''
_devbot_codebase_memory_root() { echo "${HOME:-/tmp}"; }
_devbot_get_disabled_modules() { echo "[]"; }
_devbot_lock_wait() { return 0; }
_devbot_owner_name_ok() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }
_devbot_owner_claim() {
  [[ "${SANDBOX_FAIL_CLAIM:-0}" == "1" ]] && return 1
  echo "$*" >> "${SANDBOX}/claim.args"
}
STUB
}

teardown() {
  rm -rf "${SANDBOX}" 2>/dev/null || true
}

# ── Option parsing ───────────────────────────────────────────────────────────

@test "--owner keeps an explicit pid" {
  run bash -c "
    set -- --owner herdr --owner-pid 4242
    source '${SANDBOX}/bin/up.sh.src'
    echo \"\${UP_OWNER} \${UP_OWNER_PID}\"
  "

  assert_success
  assert_output "herdr 4242"
}

@test "--owner defaults the pid to the invoking process" {
  run bash -c "
    set -- --owner herdr
    source '${SANDBOX}/bin/up.sh.src'
    [ \"\${UP_OWNER_PID}\" = \"\${PPID}\" ] || { echo \"pid=\${UP_OWNER_PID} ppid=\${PPID}\"; exit 1; }
    echo ok
  "

  assert_success
  assert_output "ok"
}

@test "--owner without a name is refused" {
  run bash -c "
    set -- --owner
    source '${SANDBOX}/bin/up.sh.src'
  "

  assert_failure
  assert_output --partial "--owner needs a name"
}

@test "--owner-pid without a value is refused" {
  run bash -c "
    set -- --owner-pid
    source '${SANDBOX}/bin/up.sh.src'
  "

  assert_failure
  assert_output --partial "--owner-pid needs a pid"
}

@test "an unsafe owner name is refused" {
  run bash -c "
    set -- --owner '../evil'
    source '${SANDBOX}/bin/up.sh.src'
  "

  assert_failure
  assert_output --partial "invalid owner name"
}

@test "a pid that is not a number is refused" {
  run bash -c "
    set -- --owner herdr --owner-pid abc
    source '${SANDBOX}/bin/up.sh.src'
  "

  assert_failure
  assert_output --partial "invalid owner pid"
}

@test "pid 0 is refused — a process group is not a process" {
  run bash -c "
    set -- --owner herdr --owner-pid 0
    source '${SANDBOX}/bin/up.sh.src'
  "

  assert_failure
  assert_output --partial "invalid owner pid"
}

@test "a pid with a leading zero is refused" {
  run bash -c "
    set -- --owner herdr --owner-pid 0123
    source '${SANDBOX}/bin/up.sh.src'
  "

  assert_failure
  assert_output --partial "invalid owner pid"
}

@test "--owner-pid without --owner is refused, not silently ignored" {
  run bash -c "
    set -- --owner-pid 4242
    source '${SANDBOX}/bin/up.sh.src'
  "

  assert_failure
  assert_output --partial "pass --owner too"
}

@test "an unknown option is refused instead of read as a project dir" {
  run bash -c "
    set -- --nope
    source '${SANDBOX}/bin/up.sh.src'
  "

  assert_failure
  assert_output --partial "unknown option: --nope"
}

@test "the flags leave the project dir as the positional argument" {
  run bash -c "
    set -- --owner herdr --owner-pid 4242 '${SANDBOX}'
    source '${SANDBOX}/bin/up.sh.src'
    echo \"\${PROJECT_DIR}\"
  "

  assert_success
  assert_output "${SANDBOX}"
}

# ── Claiming ─────────────────────────────────────────────────────────────────

@test "a completed start registers the requested owner" {
  run bash -c "
    set -- --owner herdr --owner-pid 4242
    source '${SANDBOX}/bin/up.sh.src'
    main() { :; }
    _up_run_locked
  "

  assert_success
  run cat "${SANDBOX}/claim.args"
  assert_output "herdr 4242"
}

@test "claiming the owner leaves the start's up lock held" {
  # The claim takes the registry lock, so it must do it on a descriptor of its
  # own: _devbot_lock_wait opens fd 200, which is the lock a start is holding,
  # and re-pointing it would release the up lock mid-sequence.
  cat >>"${SANDBOX}/src/_shared/functions.sh" <<'PATHS'
_devbot_up_lock_path() { echo "${SANDBOX}/storage/run/up.lock"; }
_devbot_sessions_dir() { echo "${SANDBOX}/storage/run/sessions"; }
_devbot_owners_dir() { echo "${SANDBOX}/storage/run/owners"; }
_devbot_owner_claim_path() { printf '%s/owner-%s-%s' "$(_devbot_owners_dir)" "$1" "$2"; }
PATHS
  for name in _devbot_lock_acquire _devbot_lock_wait _devbot_owner_name_ok \
    _devbot_process_start _devbot_owner_pid_live _devbot_owner_lock_take \
    _devbot_owner_lock_drop _devbot_owner_claim; do
    sed -n "/^${name}() {/,/^}/p" "${PROJECT_ROOT}/src/_shared/functions.sh" \
      >>"${SANDBOX}/src/_shared/functions.sh"
  done

  run bash -c "
    set -- --owner herdr --owner-pid \$\$
    source '${SANDBOX}/bin/up.sh.src'
    main() { :; }
    _up_run_locked
    if flock -n '${SANDBOX}/storage/run/up.lock' -c true 2>/dev/null; then
      echo FREE
    else
      echo HELD
    fi
  "

  assert_success
  assert_output --partial "HELD"
}

@test "a skipped start still registers the requested owner" {
  # The stack is up either way — that is exactly what the owner claimed.
  run bash -c "
    set -- --if-needed --owner herdr --owner-pid 4242
    source '${SANDBOX}/bin/up.sh.src'
    _up_is_up() { return 0; }
    _up_run_locked
  "

  assert_success
  [ -f "${SANDBOX}/claim.args" ]
  run cat "${SANDBOX}/claim.args"
  assert_output "herdr 4242"
}

@test "a plain start registers no owner" {
  run bash -c "
    set --
    source '${SANDBOX}/bin/up.sh.src'
    main() { :; }
    _up_run_locked
  "

  assert_success
  [ ! -f "${SANDBOX}/claim.args" ]
}

@test "a failed start registers no owner" {
  run bash -c "
    set -- --owner herdr --owner-pid 4242
    source '${SANDBOX}/bin/up.sh.src'
    main() { return 1; }
    _up_run_locked
  "

  assert_failure
  [ ! -f "${SANDBOX}/claim.args" ]
}

@test "a claim the registry refused is reported, never printed as registered" {
  # The claim is the only thing protecting the stack from the next session
  # exit, so a silent failure would cost the containers it was meant to keep.
  export SANDBOX_FAIL_CLAIM=1
  run bash -c "
    set -- --owner herdr --owner-pid 4242
    source '${SANDBOX}/bin/up.sh.src'
    main() { :; }
    _up_run_locked
  "

  assert_success
  assert_output --partial "container owner 'herdr' NOT registered"
  refute_output --partial "container owner registered"
}

@test "-- terminates the flags so a leading-dash project dir stays possible" {
  run bash -c "
    set -- --owner herdr --owner-pid 4242 -- '${SANDBOX}'
    source '${SANDBOX}/bin/up.sh.src'
    echo \"\${PROJECT_DIR}\"
  "

  assert_success
  assert_output "${SANDBOX}"
}

@test "the --is-up probe never claims" {
  run bash -c "
    set -- --is-up --owner herdr --owner-pid 4242
    source '${SANDBOX}/bin/up.sh.src'
    _up_is_up() { return 0; }
    echo sourced
  "

  assert_success
  assert_output "sourced"
  [ ! -f "${SANDBOX}/claim.args" ]
}
