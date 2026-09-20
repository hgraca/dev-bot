#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_diverged_tests.bats
# bin/update.sh — Path B: a diverged branch, and explicit `devbot update <tag>`.
# An implicit update never rewrites a branch (it skips); an explicit tag rebases
# onto it, aborting and restoring state on conflict. Also covers explicit
# downgrades, already-checked-out and nonexistent tags, --auto on a diverged
# branch, and shallow installs ahead of the tag.
#
# Fixtures live in update_helpers.bash.
# =============================================================================

load update_helpers

setup_file() { _update_file_setup; }
setup() { _update_setup; }
teardown() { _update_teardown; }

# ── Path B: diverged branch — implicit update skips, explicit tag rebases ─────

@test "diverged branch (no explicit tag): skips without rebasing, keeps the branch" {
  _new_sandbox "1.0.0:1.1.0"
  # Feature branch with its own commit (new file — no overlap with releases).
  git -C "${INSTALL}" checkout -q main
  git -C "${INSTALL}" checkout -qb feature
  printf 'feature work\n' > "${INSTALL}/feature.txt"
  git -C "${INSTALL}" add feature.txt
  git -C "${INSTALL}" commit -qm "feature commit"
  local pre_sha
  pre_sha="$(git -C "${INSTALL}" rev-parse HEAD)"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  # Branch and work untouched: no rebase, no detach, no refresh.
  assert_equal "$(git -C "${INSTALL}" symbolic-ref --short HEAD)" "feature"
  assert_equal "$(git -C "${INSTALL}" rev-parse HEAD)" "${pre_sha}"
  grep -q 'feature work' "${INSTALL}/feature.txt"
  [[ "$UPDATE_OUTPUT" == *"not a release checkout"* ]]
  [[ "$UPDATE_OUTPUT" == *"skipping update"* ]]
  ! _refresh_ran
}

@test "--auto on a diverged branch: echoes and continues without updating" {
  _new_sandbox "1.0.0:1.1.0"
  git -C "${INSTALL}" checkout -q main
  git -C "${INSTALL}" checkout -qb feature
  printf 'feature work\n' > "${INSTALL}/feature.txt"
  git -C "${INSTALL}" add feature.txt
  git -C "${INSTALL}" commit -qm "feature commit"
  local pre_sha
  pre_sha="$(git -C "${INSTALL}" rev-parse HEAD)"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update --auto

  [ "$UPDATE_STATUS" -eq 0 ]
  assert_equal "$(git -C "${INSTALL}" rev-parse HEAD)" "${pre_sha}"
  [[ "$UPDATE_OUTPUT" == *"skipping update"* ]]
  # Auto mode stays quiet: no banner, no fetch chatter.
  [[ "$UPDATE_OUTPUT" != *"Fetching release tags"* ]]
  [[ "$UPDATE_OUTPUT" != *"DevBot Update"* ]]
  ! _refresh_ran
}

@test "explicit tag, rebase conflict: aborts, restores state, exits 1" {
  _new_sandbox "1.0.0:1.1.0"
  # Feature commit edits f.txt; the requested tag also edits f.txt -> rebase
  # conflict. Capture the branch position before the run.
  git -C "${INSTALL}" checkout -q main
  git -C "${INSTALL}" checkout -qb feature
  printf 'feature edit\n' > "${INSTALL}/f.txt"
  git -C "${INSTALL}" add f.txt
  git -C "${INSTALL}" commit -qm "feature edit"
  _publish_release "f.txt" "release 1.2.0" "1.2.0"
  local pre_sha
  pre_sha="$(git -C "${INSTALL}" rev-parse HEAD)"

  _run_update 1.2.0

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"rebase"* ]]
  # State restored: branch ref back at the pre-attempt commit, clean tracked
  # tree (untracked machinery dirs are fixture artifacts, never touched).
  assert_equal "$(git -C "${INSTALL}" rev-parse HEAD)" "${pre_sha}"
  assert_equal "$(git -C "${INSTALL}" symbolic-ref --short HEAD)" "feature"
  run git -C "${INSTALL}" status --porcelain --untracked-files=no
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
  run git -C "${INSTALL}" stash list
  [[ -z "$output" ]]
  ! _refresh_ran
}

# ── Explicit target: devbot update <tag> ─────────────────────────────────────

@test "explicit older tag from a newer position: downgrades (detach) + refresh" {
  _new_sandbox "1.0.0:1.1.0" # install detached at 1.1.0 (newest)
  _run_update 1.0.0

  [ "$UPDATE_STATUS" -eq 0 ]
  # Detached HEAD now sitting exactly on the requested tag's commit.
  assert_equal "$(git -C "${INSTALL}" rev-parse HEAD)" "$(git -C "${INSTALL}" rev-parse '1.0.0^{commit}')"
  run git -C "${INSTALL}" symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  _refresh_ran
  [[ "$UPDATE_OUTPUT" == *"1.0.0"* ]]
}

@test "explicit target already checked out: says already on and exits 0" {
  _new_sandbox "1.0.0:1.1.0" # install detached at 1.1.0
  _run_update 1.1.0

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on 1.1.0"* ]]
  ! _refresh_ran
}

@test "explicit nonexistent tag: errors, lists tags, exits 1" {
  _new_sandbox "1.0.0:1.1.0"
  _run_update 9.9.9

  [ "$UPDATE_STATUS" -eq 1 ]
  [[ "$UPDATE_OUTPUT" == *"does not exist"* ]]
  [[ "$UPDATE_OUTPUT" == *"9.9.9"* ]]
  [[ "$UPDATE_OUTPUT" == *"1.1.0"* ]] # available-tags listing shown
  ! _refresh_ran
}

@test "explicit tag on a diverged branch: rebases onto the requested tag" {
  _new_sandbox "1.0.0:1.1.0"
  git -C "${INSTALL}" checkout -q main
  git -C "${INSTALL}" checkout -qb feature
  printf 'feature work\n' > "${INSTALL}/feature.txt"
  git -C "${INSTALL}" add feature.txt
  git -C "${INSTALL}" commit -qm "feature commit"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update 1.2.0

  [ "$UPDATE_STATUS" -eq 0 ]
  # Still on the feature branch (not detached), work preserved, tag now base.
  assert_equal "$(git -C "${INSTALL}" symbolic-ref --short HEAD)" "feature"
  grep -q 'feature work' "${INSTALL}/feature.txt"
  git -C "${INSTALL}" merge-base --is-ancestor 1.2.0 HEAD
  _refresh_ran
}

# ── Shallow installs (install.sh clones with --depth 1) ──────────────────────

@test "shallow install: a branch ahead of the tag is not rebased" {
  # origin main = tag 1.1.0 + one untagged commit; INSTALL is a depth-1 clone
  # at main, so 1.1.0 is an ancestor in reality but invisible to a shallow
  # merge-base. The implicit update must skip, never rebase.
  _new_shallow_sandbox main
  local pre_sha
  pre_sha="$(git -C "${INSTALL}" rev-parse HEAD)"
  _run_update --auto

  [ "$UPDATE_STATUS" -eq 0 ]
  assert_equal "$(git -C "${INSTALL}" rev-parse HEAD)" "${pre_sha}"
  assert_equal "$(git -C "${INSTALL}" symbolic-ref --short HEAD)" "main"
  [[ "$UPDATE_OUTPUT" != *"Rebasing"* ]]
  ! _refresh_ran
}
