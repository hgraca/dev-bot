#!/usr/bin/env bats
# =============================================================================
# src/agentic/git/tests/release_tests.bats
# Tests for the release helper (tools/release.sh).
#
# Hermetic: "remotes" are local bare repos created inside a sandbox, and the
# GitHub CLI is a stub reached through RELEASE_GH — neither the network nor the
# developer's real `gh` is ever touched.
# =============================================================================

setup() {
  bats_require_minimum_version 1.5.0
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SCRIPT="$MODULE_DIR/tools/release.sh"

  SANDBOX="$(mktemp -d)"
  BIN="$SANDBOX/bin"
  ORIGIN="$SANDBOX/origin.git"
  SECOND="$SANDBOX/second.git"
  EMPTY="$SANDBOX/empty.git"
  WORK="$SANDBOX/work"
  NOTES="$SANDBOX/notes.md"
  GH_LOG="$SANDBOX/gh.log"

  mkdir -p "$BIN"
  git init --bare -q --initial-branch=main "$ORIGIN"
  git init --bare -q --initial-branch=main "$SECOND"
  git init --bare -q --initial-branch=main "$EMPTY"

  git init -q --initial-branch=main "$WORK"
  git -C "$WORK" config user.email "test@test.com"
  git -C "$WORK" config user.name "Test"
  # Hermetic: don't inherit the developer's global signing config.
  git -C "$WORK" config commit.gpgsign false
  git -C "$WORK" config tag.gpgsign false

  # Five commits tagged 1.0.0 .. 1.4.0 — mirrors the real repo's tag shape.
  local i
  for i in 1 2 3 4 5; do
    printf '%s\n' "$i" > "$WORK/file.txt"
    git -C "$WORK" add -A
    git -C "$WORK" commit -qm "commit $i"
    git -C "$WORK" tag "1.$((i - 1)).0"
  done

  git -C "$WORK" remote add origin "$ORIGIN"
  git -C "$WORK" remote add second "$SECOND"
  git -C "$WORK" remote add empty "$EMPTY"
  # A URL-shaped remote: exercises slug derivation and release capability
  # without ever being pushed to.
  git -C "$WORK" remote add ghost "https://github.com/acme/ghost.git"
  git -C "$WORK" push -q --tags origin main
  git -C "$WORK" push -q --tags second main
  # Deliberately NOT set-head'ing origin here: with refs/remotes/origin/HEAD
  # absent, the "plan leaves the repository exactly as it found it" test can
  # detect a read-only subcommand that refreshes it.

  # The branch a release is cut from — the work tree stays on it, as it would
  # for a developer about to release.
  git -C "$WORK" switch -qc feature/v1.5
  printf 'feature\n' > "$WORK/feature.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "feature work"

  printf '# Release v1.5.0\n\n- Removed model downloads, embedding and MCP from QMD.\n' > "$NOTES"

  cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_LOG}"
exit 0
STUB
  chmod +x "$BIN/gh"

  # A gh that is installed but not authenticated for the host: `auth status`
  # fails, any other call would succeed.
  cat > "$BIN/gh-unauthed" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  auth) exit 1 ;;
esac
printf '%s\n' "$*" >> "${GH_LOG}"
exit 0
STUB
  chmod +x "$BIN/gh-unauthed"

  : > "$GH_LOG"

  export GH_LOG
  export RELEASE_GH="$BIN/gh"
}

teardown() {
  rm -rf "$SANDBOX" 2>/dev/null || true
}

# Run the helper inside the sandbox work tree.
release() {
  run bash -c "cd '$WORK' && bash '$SCRIPT' $*"
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

@test "version: rejects a four-component argument" {
  release version --version 1.2.3.4

  assert_failure
  assert_output --partial "FATAL:"
}

@test "version: rejects a version that already exists on the remote" {
  release version --version 1.4.0

  assert_failure
  assert_output --partial "FATAL:"
}

# ── plan: the approval preview ───────────────────────────────────────────────

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
