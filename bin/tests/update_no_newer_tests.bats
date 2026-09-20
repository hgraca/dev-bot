#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_no_newer_tests.bats
# bin/update.sh — every path that ends without moving the checkout:
#   - already at / ahead of the newest tag, no tags at all
#   - fetch failure and fetch timeout
#   - --auto's quiet no-op
#   - argument errors and the concurrent-update lock
#
# Fixtures live in update_helpers.bash.
# =============================================================================

load update_helpers

setup_file() { _update_file_setup; }
setup() { _update_setup; }
teardown() { _update_teardown; }

# ── No-newer-release paths (echo + exit, nothing else) ───────────────────────

@test "already at the newest tag: says latest and exits 0 with no refresh" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on the latest version (1.1.0)"* ]]
  ! _refresh_ran
}

@test "ahead of the newest tag (dev on main): says latest and exits 0" {
  _new_sandbox "1.0.0:1.1.0"
  # Local commit beyond the newest tag — newest tag is an ancestor of HEAD.
  git -C "${INSTALL}" checkout -q main
  printf 'local work\n' > "${INSTALL}/dev.txt"
  git -C "${INSTALL}" add dev.txt
  git -C "${INSTALL}" commit -qm "local commit after latest release"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on the latest version (1.1.0)"* ]]
  ! _refresh_ran
}

@test "no tags at all: reports nothing to update and exits 0" {
  _new_sandbox ""
  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"release tags"* ]]
  ! _refresh_ran
}

@test "fetch failure: exits 1 with an error" {
  _new_sandbox "1.0.0:1.1.0"
  git -C "${INSTALL}" remote set-url origin "${SANDBOX}/does-not-exist"
  _run_update

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"fetch"* ]]
  ! _refresh_ran
}

@test "fetch timeout: a stalled fetch is killed and exits 1" {
  _new_sandbox "1.0.0:1.1.0"
  # Fake git: stall on `fetch`, delegate every other subcommand to the real git.
  # The stall stays just past the 1s cap: the timeout must be what ends the
  # fetch, and a longer sleep would only outlive the assertion — it keeps the
  # captured stdout open, so the test would wait for it in full.
  local real_git
  real_git="$(command -v git)"
  mkdir -p "${SANDBOX}/mockbin"
  cat > "${SANDBOX}/mockbin/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == "fetch" ]]; then sleep 3; exit 0; fi
done
exec "${real_git}" "\$@"
EOF
  chmod +x "${SANDBOX}/mockbin/git"

  # PATH scoped to this invocation only — never leak the mock into other tests.
  PATH="${SANDBOX}/mockbin:${PATH}" DEV_BOT_FETCH_TIMEOUT=1 _run_update

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"within 1s"* ]]
  ! _refresh_ran
}

# ── Auto mode (bare-`devbot` start), quiet paths ─────────────────────────────

@test "--auto at the newest tag: one-line no-op, no banner" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update --auto

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on the latest version (1.1.0)"* ]]
  [[ "$UPDATE_OUTPUT" != *"DevBot Update"* ]]
  [[ "$UPDATE_OUTPUT" != *"Fetching release tags"* ]]
  ! _refresh_ran
}

@test "--auto after the tag is honored (flag order independent)" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update 1.1.0 --auto

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on 1.1.0"* ]]
  # --auto was parsed: no banner, no fetch chatter.
  [[ "$UPDATE_OUTPUT" != *"DevBot Update"* ]]
  [[ "$UPDATE_OUTPUT" != *"Fetching release tags"* ]]
}

# ── Argument errors and the update lock ──────────────────────────────────────

@test "unknown option: errors and exits 1" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update --bogus

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"Unknown option"* ]]
}

@test "two tags: errors and exits 1" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update 1.0.0 1.1.0

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"Unexpected extra argument"* ]]
}

@test "concurrent update: skips when the update lock is held" {
  _new_sandbox "1.0.0:1.1.0"
  mkdir -p "${INSTALL}/storage/run"
  # Hold the update lock for the duration (same flock fd the script uses).
  ( exec 200>"${INSTALL}/storage/run/update.lock"; flock -x 200; sleep 3 ) &
  local holder=$!
  sleep 0.3

  DEV_BOT_UPDATE_LOCK_WAIT=0 _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"another devbot update is in progress"* ]]
  ! _refresh_ran

  kill "${holder}" 2>/dev/null || true
}
