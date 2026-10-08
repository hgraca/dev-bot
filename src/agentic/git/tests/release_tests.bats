#!/usr/bin/env bats
# =============================================================================
# src/agentic/git/tests/release_tests.bats
# Tests for the GitHub release helper (tools/release.sh) — the GitHub half of
# the release tooling. The sandbox lives in release_test_helper.bash.
# =============================================================================

load 'release_test_helper'

setup() {
  release_test_setup
  SCRIPT="$MODULE_DIR/tools/release.sh"
}

# ── plan: the release preview ────────────────────────────────────────────────

@test "plan: lists every remote with its slug and release capability" {
  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial 'origin'
  assert_output --partial 'second'
  assert_output --partial 'acme/ghost'
}

@test "plan: a remote with no resolvable slug is reported as not release-capable" {
  release plan --version 1.5.0 --notes-file "$NOTES" --remotes origin

  assert_success
  assert_output --partial 'origin'
  refute_output --partial 'acme/ghost'
}

@test "plan: a file:// remote has no repository slug" {
  git -C "$WORK" remote add fileurl "file:///srv/git/repo.git"

  release plan --version 1.5.0 --notes-file "$NOTES" --remotes fileurl

  assert_success
  assert_output --partial 'fileurl'
  refute_output --partial 'srv/git/repo'
}

@test "plan: without gh it degrades to a warning, never a failure" {
  RELEASE_GH="$SANDBOX/does-not-exist"

  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial 'WARN:'
}

@test "plan: leaves the repository exactly as it found it" {
  local head_before status_before refs_before
  head_before="$(git -C "$WORK" rev-parse HEAD)"
  status_before="$(git -C "$WORK" status --porcelain)"
  # Every ref, including the remote-tracking ones.
  refs_before="$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' | sort)"

  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_equal "$(git -C "$WORK" rev-parse HEAD)" "$head_before"
  assert_equal "$(git -C "$WORK" status --porcelain)" "$status_before"
  assert_equal "$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' | sort)" "$refs_before"
}

# ── release ──────────────────────────────────────────────────────────────────

@test "release: creates a GitHub release per capable remote, titled with the version" {
  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_success

  run cat "$GH_LOG"
  assert_output --partial 'release create 1.5.0'
  assert_output --partial '--repo acme/ghost'
  assert_output --partial '--title 1.5.0'
  assert_output --partial '--notes-file'
}

@test "release: a remote without a repository slug is skipped with a warning" {
  release release --version 1.5.0 --notes-file "$NOTES" --remotes origin

  assert_success
  assert_output --partial 'WARN:'

  run cat "$GH_LOG"
  refute_output --partial 'release create'
}

@test "release: without gh it warns and still succeeds — the tag push counts" {
  RELEASE_GH="$SANDBOX/does-not-exist"

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_success
  assert_output --partial 'WARN:'
}

@test "release: an installed but unauthenticated gh warns and still succeeds" {
  RELEASE_GH="$BIN/gh-unauthed"

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_success
  assert_output --partial 'WARN:'

  run cat "$GH_LOG"
  refute_output --partial 'release create'
}
