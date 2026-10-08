#!/usr/bin/env bats
# =============================================================================
# src/agentic/git/tests/release_test_helper.bash
#
# Shared sandbox for the git module's release-tooling tests, loaded via `load`.
# Hermetic: "remotes" are local bare repos created inside a sandbox, and the
# GitHub CLI is a stub reached through RELEASE_GH — neither the network nor the
# developer's real `gh` is ever touched.
#
# Each .bats file calls `release_test_setup` from its own setup() and then
# points SCRIPT at the tool under test.
# =============================================================================

release_test_setup() {
  bats_require_minimum_version 1.5.0
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"

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

# Run the tool under test ($SCRIPT) inside the sandbox work tree.
release() {
  run bash -c "cd '$WORK' && bash '$SCRIPT' $*"
}
