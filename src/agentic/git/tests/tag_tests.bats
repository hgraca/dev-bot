#!/usr/bin/env bats
# =============================================================================
# src/agentic/git/tests/tag_tests.bats
# Tests for the git tag helper (tools/tag.sh) — the git half of the release
# tooling. The sandbox lives in release_test_helper.bash.
# =============================================================================

load 'release_test_helper'

setup() {
  release_test_setup
  SCRIPT="$MODULE_DIR/tools/tag.sh"
}

# ── version: derived from the remote ─────────────────────────────────────────

@test "version: no argument bumps the remote's newest tag to the next minor" {
  release version

  assert_success
  assert_output "1.5.0"
}

@test "version: a patch release on the remote still yields the next minor" {
  git -C "$WORK" tag 1.4.1
  git -C "$WORK" push -q origin 1.4.1

  release version

  assert_success
  assert_output "1.5.0"
}

@test "version: an annotated tag is not misread as its peeled ^{} ref" {
  git -C "$WORK" tag -a 1.5.0 -m "annotated"
  git -C "$WORK" push -q origin 1.5.0

  release version

  assert_success
  assert_output "1.6.0"
}

@test "version: a remote with no tags refuses to guess" {
  release version --remote empty

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: a non-version tag newer than the release is ignored" {
  git -C "$WORK" tag nightly
  git -C "$WORK" push -q origin nightly

  release version

  assert_success
  assert_output "1.5.0"
}

@test "version: a remote carrying only non-version tags refuses to guess" {
  git -C "$WORK" tag nightly
  git -C "$WORK" push -q empty main nightly

  release version --remote empty

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: a four-part remote tag bumps the third component" {
  git -C "$WORK" tag 0.7.4.0
  git -C "$WORK" push -q empty main refs/tags/0.7.4.0

  release version --remote empty

  assert_success
  assert_output "0.7.5.0"
}

@test "version: the unstable major-zero prefix shifts the bump to the third component" {
  git -C "$WORK" tag 0.1.2.3
  git -C "$WORK" push -q empty main refs/tags/0.1.2.3

  release version --remote empty

  assert_success
  assert_output "0.1.3.0"
}

@test "version: a three-part major-zero tag is not a version tag" {
  git -C "$WORK" tag 0.7.5
  git -C "$WORK" push -q empty main refs/tags/0.7.5

  release version --remote empty

  assert_failure
  assert_output --partial "FATAL:"
}

# ── version: explicit argument ───────────────────────────────────────────────

@test "version: accepts a full semver argument" {
  release version --version 1.6.0

  assert_success
  assert_output "1.6.0"
}

@test "version: normalises a two-part argument to three parts" {
  release version --version 1.6

  assert_success
  assert_output "1.6.0"
}

@test "version: rejects a non-numeric argument" {
  release version --version abc

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a single-component argument" {
  release version --version 1

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a four-component argument when the major is non-zero" {
  release version --version 1.2.3.4

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: accepts a four-component argument when the major is zero" {
  release version --version 0.1.2.3

  assert_success
  assert_output "0.1.2.3"
}

@test "version: rejects a two-component argument when the major is zero" {
  release version --version 0.7

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a three-component argument when the major is zero" {
  release version --version 0.7.5

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a five-component argument" {
  release version --version 0.1.2.3.4

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a version that already exists on the remote" {
  release version --version 1.4.0

  assert_failure
  assert_output --partial "FATAL:"
}

# ── plan: the tag approval preview ───────────────────────────────────────────

@test "plan: names the version, tag and the branch it merges from and to" {
  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial '1.5.0'
  assert_output --partial 'feature/v1.5'
  assert_output --partial 'main'
}

@test "plan: reproduces the notes verbatim, heading included" {
  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial '# Release v1.5.0'
  assert_output --partial 'Removed model downloads, embedding and MCP from QMD.'
}

@test "plan: lists the remotes the tag and branch will be pushed to" {
  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial 'origin'
  assert_output --partial 'second'
}

# ── plan: mutates nothing ────────────────────────────────────────────────────

@test "plan: takes the default branch from origin/HEAD when it is set" {
  git -C "$WORK" branch develop main
  git -C "$WORK" push -q origin develop
  git -C "$WORK" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop

  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  # Resolved by reading the symref, not by re-deriving it from the remote —
  # a `set-head --auto` would answer `main` here.
  assert_output --partial 'Default branch:** `develop`'
}

@test "plan: leaves the repository exactly as it found it" {
  local head_before status_before tags_before refs_before
  head_before="$(git -C "$WORK" rev-parse HEAD)"
  status_before="$(git -C "$WORK" status --porcelain)"
  tags_before="$(git -C "$WORK" tag | sort | tr '\n' ' ')"
  # Every ref, including the remote-tracking ones: plan resolves the default
  # branch, and doing that by refreshing origin/HEAD would write this ref.
  refs_before="$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' | sort)"

  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_equal "$(git -C "$WORK" rev-parse HEAD)" "$head_before"
  assert_equal "$(git -C "$WORK" status --porcelain)" "$status_before"
  assert_equal "$(git -C "$WORK" tag | sort | tr '\n' ' ')" "$tags_before"
  assert_equal "$(git -C "$WORK" for-each-ref --format='%(refname) %(objectname)' | sort)" "$refs_before"
  assert_equal "$(git -C "$WORK" branch --show-current)" "feature/v1.5"
}

# ── merge ────────────────────────────────────────────────────────────────────

@test "merge: fast-forwards the default branch and leaves the checkout on it" {
  local feature_sha
  feature_sha="$(git -C "$WORK" rev-parse feature/v1.5)"

  release merge --source feature/v1.5

  assert_success
  assert_equal "$(git -C "$WORK" branch --show-current)" "main"
  assert_equal "$(git -C "$WORK" rev-parse main)" "$feature_sha"
  assert_equal "$(git -C "$WORK" rev-parse HEAD)" "$feature_sha"
}

@test "merge: a conflict is aborted, the branch restored, and nothing tagged" {
  git -C "$WORK" switch -q feature/v1.5
  printf 'feature side\n' > "$WORK/file.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "feature side"
  git -C "$WORK" switch -q main
  printf 'main side\n' > "$WORK/file.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "main side"
  git -C "$WORK" switch -q feature/v1.5

  release merge --source feature/v1.5

  assert_failure
  assert_output --partial 'FATAL:'
  assert_equal "$(git -C "$WORK" branch --show-current)" "feature/v1.5"
  assert_equal "$(git -C "$WORK" status --porcelain)" ""
  refute [ -e "$WORK/.git/MERGE_HEAD" ]
  assert_equal "$(git -C "$WORK" tag | sort | tr '\n' ' ')" "1.0.0 1.1.0 1.2.0 1.3.0 1.4.0 "
}

@test "merge: running on the default branch is a no-op" {
  git -C "$WORK" switch -q main
  local head_before
  head_before="$(git -C "$WORK" rev-parse HEAD)"

  release merge --source main

  assert_success
  assert_equal "$(git -C "$WORK" rev-parse HEAD)" "$head_before"
  assert_equal "$(git -C "$WORK" branch --show-current)" "main"
}

# ── merge: fixup squashing ───────────────────────────────────────────────────

@test "merge: folds fixup commits into their targets before merging" {
  git -C "$WORK" switch -q feature/v1.5
  printf 'more\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "more feature work"
  printf 'fixed\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "fixup! more feature work"

  release merge --source feature/v1.5

  assert_success
  assert_equal "$(git -C "$WORK" branch --show-current)" "main"
  run git -C "$WORK" log --format=%s main
  refute_output --partial 'fixup!'
  assert_output --partial 'more feature work'
  # The fixup's content is folded into its target, not lost.
  assert_equal "$(cat "$WORK/feature.txt")" "$(printf 'feature\nmore\nfixed')"
  # 5 tagged commits + "feature work" + "more feature work" (fixup folded in).
  assert_equal "$(git -C "$WORK" rev-list --count main)" "7"
}

@test "merge: reports the fixups it squashed" {
  git -C "$WORK" switch -q feature/v1.5
  printf 'more\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "more feature work"
  git -C "$WORK" commit -q --allow-empty -m "fixup! more feature work"

  release merge --source feature/v1.5

  assert_success
  assert_output --partial 'squashed'
}

@test "plan: reports the fixup commits that will be squashed, mutating nothing" {
  git -C "$WORK" switch -q feature/v1.5
  printf 'more\n' >> "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "more feature work"
  git -C "$WORK" commit -q --allow-empty -m "fixup! more feature work"
  local head_before
  head_before="$(git -C "$WORK" rev-parse HEAD)"

  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial '1 fixup commit'
  assert_equal "$(git -C "$WORK" rev-parse HEAD)" "$head_before"
}

@test "plan: a branch with no fixups reports none to squash" {
  release plan --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_output --partial 'Squash:** none'
}

# ── tag ──────────────────────────────────────────────────────────────────────

@test "tag: creates an annotated tag carrying the notes' markdown heading" {
  release tag --version 1.5.0 --notes-file "$NOTES"

  assert_success
  assert_equal "$(git -C "$WORK" cat-file -t 1.5.0)" "tag"

  run git -C "$WORK" cat-file tag 1.5.0
  assert_output --partial '# Release v1.5.0'
  assert_output --partial 'Removed model downloads'
}

@test "tag: refuses a version that already exists locally" {
  git -C "$WORK" tag 1.5.0

  release tag --version 1.5.0 --notes-file "$NOTES"

  assert_failure
  assert_output --partial 'FATAL:'
}

# ── push ─────────────────────────────────────────────────────────────────────

@test "push: sends the default branch and the tag to two remotes" {
  release merge --source feature/v1.5
  assert_success
  release tag --version 1.5.0 --notes-file "$NOTES"
  assert_success

  release push --version 1.5.0 --branch main --remotes origin,second

  assert_success
  assert_equal "$(git -C "$ORIGIN" rev-parse refs/tags/1.5.0)" "$(git -C "$WORK" rev-parse 1.5.0)"
  assert_equal "$(git -C "$SECOND" rev-parse refs/tags/1.5.0)" "$(git -C "$WORK" rev-parse 1.5.0)"
  assert_equal "$(git -C "$ORIGIN" rev-parse refs/heads/main)" "$(git -C "$WORK" rev-parse main)"
  assert_equal "$(git -C "$SECOND" rev-parse refs/heads/main)" "$(git -C "$WORK" rev-parse main)"
}

@test "push: an unreachable remote does not stop the others and is reported" {
  release merge --source feature/v1.5
  release tag --version 1.5.0 --notes-file "$NOTES"
  git -C "$WORK" remote add broken "$SANDBOX/nope.git"

  release push --version 1.5.0 --branch main --remotes origin,broken

  assert_failure
  assert_output --partial 'origin'
  assert_output --partial 'broken'
  assert_equal "$(git -C "$ORIGIN" rev-parse refs/tags/1.5.0)" "$(git -C "$WORK" rev-parse 1.5.0)"
}
