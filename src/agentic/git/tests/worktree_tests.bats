#!/usr/bin/env bats
# =============================================================================
# src/agentic/git/tests/worktree_tests.bats
# Tests for the worktree helper (tools/worktree.sh).
#
# Hermetic: "origin" is a local bare repo created inside a sandbox, so no
# network is ever touched. All worktrees land under <devbot_dir>/worktrees/ and
# are removed with the sandbox.
# =============================================================================

setup() {
  bats_require_minimum_version 1.5.0
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  SCRIPT="$MODULE_DIR/tools/worktree.sh"

  SANDBOX="$(mktemp -d)"
  ORIGIN="$SANDBOX/origin.git"
  WORK="$SANDBOX/work"
  WORKTREES="$WORK/.agents/worktrees"

  git init --bare -q --initial-branch=main "$ORIGIN"

  git init -q --initial-branch=main "$WORK"
  # Hermetic: pin the project config (devbot_dir + worktrees) so the machine's
  # real global config is never consulted; excluded so it doesn't dirty the tree.
  printf '.devbot.project.jsonc\nvendor/\nnode_modules/\n' > "$WORK/.git/info/exclude"
  printf '{ "devbot_dir": ".agents", "worktrees": true }\n' > "$WORK/.devbot.project.jsonc"
  git -C "$WORK" config user.email "test@test.com"
  git -C "$WORK" config user.name "Test"
  # Hermetic: don't inherit the developer's global signing config.
  git -C "$WORK" config commit.gpgsign false
  git -C "$WORK" config tag.gpgsign false

  printf 'base\n' > "$WORK/file.txt"
  git -C "$WORK" add -A
  git -C "$WORK" commit -qm "base"
  git -C "$WORK" remote add origin "$ORIGIN"
  git -C "$WORK" push -q origin main
  git -C "$WORK" fetch -q origin
  git -C "$WORK" remote set-head origin --auto >/dev/null 2>&1 || true
}

teardown() {
  rm -rf "$SANDBOX" 2>/dev/null || true
}

# Run the helper from the main checkout's working tree.
worktree() {
  run bash -c "cd '$WORK' && bash '$SCRIPT' $*"
}

# ── create ───────────────────────────────────────────────────────────────────

@test "create: makes a branch worktree under <devbot_dir>/worktrees, based on origin/main" {
  worktree create feat/add-login --no-link

  assert_success
  assert_output "$WORKTREES/feat-add-login"
  assert [ -d "$WORKTREES/feat-add-login" ]
  assert_equal "$(git -C "$WORKTREES/feat-add-login" branch --show-current)" "feat/add-login"
  assert_equal "$(git -C "$WORKTREES/feat-add-login" rev-parse HEAD)" \
    "$(git -C "$WORK" rev-parse origin/main)"
}

@test "create: the new branch has no upstream (--no-track)" {
  worktree create feat/untracked

  run git -C "$WORKTREES/feat-untracked" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'

  assert_failure
}

@test "create: derives the slug from the branch name" {
  worktree create feature/deep/nested

  assert_success
  assert [ -d "$WORKTREES/feature-deep-nested" ]
}

@test "create: ignores the worktrees dir so it never pollutes status" {
  worktree create feat/clean

  assert_success
  run grep -F ".agents/worktrees/" "$WORK/.git/info/exclude"
  assert_success

  run bash -c "cd '$WORK' && git status --porcelain"
  assert_success
  refute_output --partial "worktrees"
}

@test "create: warns but proceeds when the main checkout is dirty" {
  printf 'dirty\n' >> "$WORK/file.txt"

  worktree create feat/dirty

  assert_success
  assert_output --partial "WARN:"
  assert [ -d "$WORKTREES/feat-dirty" ]
}

@test "create: refuses when the branch already exists" {
  git -C "$WORK" branch feat/existing

  worktree create feat/existing

  assert_failure
  assert_output --partial "FATAL:"
}

@test "create: refuses when the worktree path already exists" {
  worktree create feat/twice
  assert_success

  worktree create feat/twice

  assert_failure
  assert_output --partial "FATAL:"
}

@test "create --help: prints usage" {
  worktree create --help

  assert_success
  assert_output --partial "Usage: worktree.sh"
}

# ── create: dependency linking ───────────────────────────────────────────────

@test "create: hard-links vendor and node_modules from the main checkout by default" {
  mkdir -p "$WORK/vendor" "$WORK/node_modules"
  printf 'v\n' > "$WORK/vendor/a.txt"
  printf 'n\n' > "$WORK/node_modules/b.txt"

  worktree create feat/links

  assert_success
  local wt="$WORKTREES/feat-links"
  assert [ -d "$wt/vendor" ]
  assert [ -d "$wt/node_modules" ]
  # -ef is true only for the same inode — i.e. a genuine hard link, not a copy.
  assert [ "$WORK/vendor/a.txt" -ef "$wt/vendor/a.txt" ]
  assert [ "$WORK/node_modules/b.txt" -ef "$wt/node_modules/b.txt" ]
}

@test "create: --link replaces the default dependency dirs" {
  mkdir -p "$WORK/vendor" "$WORK/lib"
  printf 'v\n' > "$WORK/vendor/a.txt"
  printf 'l\n' > "$WORK/lib/a.txt"

  worktree create feat/lib --link lib

  assert_success
  local wt="$WORKTREES/feat-lib"
  assert [ -d "$wt/lib" ]
  assert [ "$WORK/lib/a.txt" -ef "$wt/lib/a.txt" ]
  assert [ ! -e "$wt/vendor" ]
  assert [ ! -e "$wt/node_modules" ]
}

@test "create: --no-link skips all dependency linking" {
  mkdir -p "$WORK/vendor"
  printf 'v\n' > "$WORK/vendor/a.txt"

  worktree create feat/nolink --no-link

  assert_success
  assert [ ! -e "$WORKTREES/feat-nolink/vendor" ]
}

@test "create: warns and proceeds when a dependency dir is absent in the main checkout" {
  worktree create feat/nodeps

  assert_success
  assert_output --partial "WARN:"
  assert [ -d "$WORKTREES/feat-nodeps" ]
}

@test "create: warns and leaves an existing dependency dir untouched" {
  # A tracked dir of the same name arrives with the checkout — linking must not
  # clobber it.
  mkdir -p "$WORK/vendor"
  printf 'tracked\n' > "$WORK/vendor/tracked.txt"
  git -C "$WORK" add -f vendor/tracked.txt
  git -C "$WORK" commit -qm "track vendor"
  git -C "$WORK" push -q origin main
  git -C "$WORK" fetch -q origin

  worktree create feat/dest-exists

  assert_success
  assert_output --partial "WARN:"
  assert_equal "$(cat "$WORKTREES/feat-dest-exists/vendor/tracked.txt")" "tracked"
}

@test "create: ignores a linked dir in the worktree so remove still works" {
  mkdir -p "$WORK/lib"
  printf 'l\n' > "$WORK/lib/a.txt"

  worktree create feat/ignored --link lib
  assert_success

  local wt="$WORKTREES/feat-ignored"
  assert [ "$WORK/lib/a.txt" -ef "$wt/lib/a.txt" ]
  run bash -c "cd '$wt' && git status --porcelain"
  assert_success
  refute_output --partial "lib"

  worktree remove feat/ignored
  assert_success
}

@test "create: refuses an absolute --link dir" {
  worktree create feat/abs --link /etc

  assert_failure
  assert_output --partial "FATAL:"
}

@test "create: refuses a --link dir containing .." {
  worktree create feat/dotdot --link ../evil

  assert_failure
  assert_output --partial "FATAL:"
}

@test "create: warns, rolls back, and proceeds when hard-linking fails" {
  mkdir -p "$WORK/vendor" "$SANDBOX/bin"
  printf 'v\n' > "$WORK/vendor/a.txt"
  # Stub cp to fail, forcing the rollback branch deterministically.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$SANDBOX/bin/cp"
  chmod +x "$SANDBOX/bin/cp"

  run env PATH="$SANDBOX/bin:$PATH" bash -c "cd '$WORK' && bash '$SCRIPT' create feat/cpfail"

  assert_success
  assert_output --partial "WARN:"
  assert [ -d "$WORKTREES/feat-cpfail" ]
  assert [ ! -e "$WORKTREES/feat-cpfail/vendor" ]
  assert [ -f "$WORK/vendor/a.txt" ]
}

@test "create: --link without a value is fatal" {
  worktree create feat/x --link

  assert_failure
  assert_output --partial "FATAL:"
}

@test "create: an unknown option is fatal" {
  worktree create feat/x --bogus

  assert_failure
  assert_output --partial "FATAL:"
}

@test "create: two positional args is fatal" {
  worktree create feat/x extra

  assert_failure
  assert_output --partial "FATAL:"
}

# ── enabled / opt-out ────────────────────────────────────────────────────────

@test "enabled: reports true by default" {
  worktree enabled

  assert_success
  assert_output "true"
}

@test "enabled: reports false when the project opts out" {
  printf '{ "devbot_dir": ".agents", "worktrees": false }\n' > "$WORK/.devbot.project.jsonc"

  worktree enabled

  assert_failure
  assert_output "false"
}

@test "create: refuses when the project opted out" {
  printf '{ "devbot_dir": ".agents", "worktrees": false }\n' > "$WORK/.devbot.project.jsonc"

  worktree create feat/nope

  assert_failure
  assert_output --partial "FATAL:"
  assert [ ! -d "$WORKTREES/feat-nope" ]
}

@test "create: proceeds when the project explicitly enables worktrees" {
  printf '{ "devbot_dir": ".agents", "worktrees": true }\n' > "$WORK/.devbot.project.jsonc"

  worktree create feat/yes

  assert_success
  assert [ -d "$WORKTREES/feat-yes" ]
}

# ── list ─────────────────────────────────────────────────────────────────────

@test "list: lists the module worktrees and excludes the main checkout" {
  worktree create feat/one
  worktree create feat/two

  worktree list

  assert_success
  assert_output --partial "$WORKTREES/feat-one feat/one"
  assert_output --partial "$WORKTREES/feat-two feat/two"
  refute_output --partial "$WORK main"
}

# ── merge ────────────────────────────────────────────────────────────────────

@test "merge: merges the worktree branch into the default branch" {
  worktree create feat/merged
  assert_success

  local path="$WORKTREES/feat-merged"
  printf 'work\n' > "$path/feature.txt"
  git -C "$path" add -A
  git -C "$path" commit -qm "feature work"
  local sha
  sha="$(git -C "$path" rev-parse HEAD)"

  worktree merge feat/merged

  assert_success
  assert_equal "$(git -C "$WORK" branch --show-current)" "main"
  run git -C "$WORK" merge-base --is-ancestor "$sha" HEAD
  assert_success
}

@test "merge: refuses when the main checkout is not on the default branch" {
  git -C "$WORK" switch -qc other

  worktree merge feat/anything

  assert_failure
  assert_output --partial "FATAL:"
  assert_equal "$(git -C "$WORK" branch --show-current)" "other"
}

@test "merge: refuses when the working tree is dirty" {
  worktree create feat/merge-dirty
  assert_success
  printf 'dirty\n' >> "$WORK/file.txt"

  worktree merge feat/merge-dirty

  assert_failure
  assert_output --partial "FATAL:"
  assert_output --partial "not clean"
}

# ── remove ───────────────────────────────────────────────────────────────────

@test "remove: removes the worktree directory but keeps the branch" {
  worktree create feat/bye
  assert_success

  worktree remove feat/bye

  assert_success
  assert [ ! -d "$WORKTREES/feat-bye" ]
  run git -C "$WORK" show-ref --verify --quiet refs/heads/feat/bye
  assert_success
}

@test "remove: fails when there is no such worktree" {
  worktree remove feat/missing

  assert_failure
  assert_output --partial "FATAL:"
}
