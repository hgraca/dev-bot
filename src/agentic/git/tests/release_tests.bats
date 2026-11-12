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
  tag_release 1.5.0
  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_success

  run cat "$GH_LOG"
  assert_output --partial 'release create 1.5.0'
  assert_output --partial '--repo acme/ghost'
  assert_output --partial '--title 1.5.0'
  assert_output --partial '--notes-file'
}

@test "release: a remote without a repository slug is skipped with a warning" {
  git -C "$WORK" tag -a 1.5.0 --cleanup=whitespace -F "$NOTES"
  release release --version 1.5.0 --notes-file "$NOTES" --remotes origin

  assert_success
  assert_output --partial 'WARN:'

  run cat "$GH_LOG"
  refute_output --partial 'release create'
}

@test "release: without gh it warns and still succeeds — the tag push counts" {
  RELEASE_GH="$SANDBOX/does-not-exist"
  tag_release 1.5.0

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_success
  assert_output --partial 'WARN:'
}

@test "release: an installed but unauthenticated gh warns and still succeeds" {
  RELEASE_GH="$BIN/gh-unauthed"
  tag_release 1.5.0

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_success
  assert_output --partial 'WARN:'

  run cat "$GH_LOG"
  refute_output --partial 'release create'
}

# ── the release gate: no release without the tag ─────────────────────────────

@test "release: refuses when the tag does not exist" {
  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_failure
  assert_output --partial 'tag 1.5.0 does not exist'
  assert_output --partial 'tag.sh tag'

  run cat "$GH_LOG"
  refute_output --partial 'release create'
}

@test "release: refuses a tag created from different notes" {
  git -C "$WORK" tag -a 1.5.0 -m "notes for another release"
  git -C "$WORK" push -q ghost refs/tags/1.5.0

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_failure
  assert_output --partial 'was not created from'
  assert_output --partial '--reuse-tag'

  run cat "$GH_LOG"
  refute_output --partial 'release create'
}

@test "release: --reuse-tag publishes a tag whose notes differ" {
  git -C "$WORK" tag -a 1.5.0 -m "notes for another release"
  git -C "$WORK" push -q ghost refs/tags/1.5.0

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost --reuse-tag

  assert_success
  run cat "$GH_LOG"
  assert_output --partial 'release create 1.5.0'
}

@test "release: refuses when the tag was not pushed to the release remote" {
  git -C "$WORK" tag -a 1.5.0 --cleanup=whitespace -F "$NOTES"

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_failure
  assert_output --partial "is not on 'ghost'"
  assert_output --partial 'tag.sh push'

  run cat "$GH_LOG"
  refute_output --partial 'release create'
}

@test "release: end to end after tag.sh creates and pushes the tag" {
  (cd "$WORK" && bash "$MODULE_DIR/tools/tag.sh" tag --tag-only --version 1.5.0 \
    --ref "$(git -C "$WORK" rev-parse HEAD)" --notes-file "$NOTES" >/dev/null)
  (cd "$WORK" && bash "$MODULE_DIR/tools/tag.sh" push --tag-only --version 1.5.0 \
    --remotes ghost >/dev/null)

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_success
  run cat "$GH_LOG"
  assert_output --partial 'release create 1.5.0'
}

@test "plan: refuses when a pushed tag does not match the notes" {
  git -C "$WORK" tag -a 1.5.0 -m "notes for another release"
  git -C "$WORK" push -q ghost refs/tags/1.5.0

  release plan --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_failure
  assert_output --partial 'was not created from'
}

@test "plan: reports readiness when the tag matches and is pushed" {
  tag_release 1.5.0

  release plan --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_success
  assert_output --partial 'Readiness'
  assert_output --partial 'matches the notes'
}

@test "release: refuses when the remote tag is a different object" {
  tag_release 1.5.0
  git -C "$WORK" tag -d 1.5.0 >/dev/null
  git -C "$WORK" tag -a 1.5.0 -m "replaced after the push"

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost --reuse-tag

  assert_failure
  assert_output --partial 'is not the tag this run validated'

  run cat "$GH_LOG"
  refute_output --partial 'release create'
}

@test "plan: requires the notes when the tag already exists" {
  tag_release 1.5.0

  release plan --version 1.5.0 --remotes ghost

  assert_failure
  assert_output --partial '--notes-file is required'
}

@test "release: refuses a remote whose push URL is another repository" {
  tag_release 1.5.0
  git -C "$WORK" config remote.ghost.pushurl "https://github.com/acme/other.git"

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_failure
  assert_output --partial 'point both at one repository'

  run cat "$GH_LOG"
  refute_output --partial 'release create'
}

@test "release: refuses a remote with more than one push URL" {
  tag_release 1.5.0
  git -C "$WORK" config --add remote.ghost.pushurl "https://github.com/acme/one.git"
  git -C "$WORK" config --add remote.ghost.pushurl "https://github.com/acme/two.git"

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_failure
  assert_output --partial 'more than one push URL'
}

@test "release: refuses a push URL on another host" {
  tag_release 1.5.0
  git -C "$WORK" config remote.ghost.pushurl "https://other.example/acme/ghost.git"

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_failure
  assert_output --partial 'point both at one repository'
}

@test "release: a differing heading is not the same notes" {
  git -C "$WORK" tag -a 1.5.0 --cleanup=whitespace \
    -m "$(printf '# Release v1.4.0\n\n- Removed model downloads, embedding and MCP from QMD.')"
  git -C "$WORK" push -q ghost refs/tags/1.5.0

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_failure
  assert_output --partial 'was not created from'
}

@test "release: a tag pushed earlier but not fetched is not a future tag" {
  tag_release 1.5.0
  git -C "$WORK" tag -d 1.5.0 >/dev/null

  release release --version 1.5.0 --notes-file "$NOTES" --remotes ghost

  assert_failure
  assert_output --partial 'git fetch --tags'
}
