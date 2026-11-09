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
  # Hermetic: pin the project config (devbot_dir + workflow) so the machine's
  # real global config is never consulted; excluded so it doesn't dirty the tree.
  printf '.devbot.project.jsonc\nvendor/\nnode_modules/\n' > "$WORK/.git/info/exclude"
  printf '{ "devbot_dir": ".agents", "workflow": "worktrees" }\n' > "$WORK/.devbot.project.jsonc"
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

@test "create --base: cuts the worktree from the given ref, not origin/main" {
  git -C "$WORK" checkout -q -b release/v1.9
  printf 'release\n' >> "$WORK/file.txt"
  git -C "$WORK" commit -qam "release work"
  git -C "$WORK" push -q origin release/v1.9
  git -C "$WORK" checkout -q main

  worktree create feat/from-release --base origin/release/v1.9 --no-link

  assert_success
  assert_equal "$(git -C "$WORKTREES/feat-from-release" rev-parse HEAD)" \
    "$(git -C "$WORK" rev-parse origin/release/v1.9)"
  assert_not_equal "$(git -C "$WORKTREES/feat-from-release" rev-parse HEAD)" \
    "$(git -C "$WORK" rev-parse origin/main)"
}

@test "create --base: refuses a ref that does not resolve" {
  worktree create feat/bad-base --base does-not-exist --no-link

  assert_failure
  assert_output --partial "does not resolve"
}

@test "create --base HEAD: resolves HEAD in the invoking worktree, not the main checkout" {
  worktree create feat/caller --no-link
  assert_success
  local caller="$WORKTREES/feat-caller"
  printf 'caller\n' >> "$caller/file.txt"
  git -C "$caller" commit -qam "caller work"
  local caller_head main_head
  caller_head="$(git -C "$caller" rev-parse HEAD)"
  main_head="$(git -C "$WORK" rev-parse HEAD)"
  assert_not_equal "$caller_head" "$main_head"

  run bash -c "cd '$caller' && bash '$SCRIPT' create feat/from-head --base HEAD --no-link"

  assert_success
  assert_equal "$(git -C "$WORKTREES/feat-from-head" rev-parse HEAD)" "$caller_head"
}

@test "create --project: creates the worktree in the named project from outside it" {
  run bash -c "cd '$SANDBOX' && bash '$SCRIPT' create feat/from-elsewhere --project '$WORK' --no-link"

  assert_success
  assert_output "$WORKTREES/feat-from-elsewhere"
  assert [ -d "$WORKTREES/feat-from-elsewhere" ]
}

@test "create: refuses a repository with no commits" {
  local empty="$SANDBOX/empty"
  git init -q --initial-branch=main "$empty"

  run bash -c "cd '$empty' && bash '$SCRIPT' create feat/nope --no-link"

  assert_failure
  assert_output --partial "FATAL:"
  assert_output --partial "has no commits"
  assert_output --partial "initial commit"
}

@test "create --project: a named project with no commits asks for an initial commit" {
  local empty="$SANDBOX/empty"
  git init -q --initial-branch=main "$empty"

  run bash -c "cd '$WORK' && bash '$SCRIPT' create feat/nope --project '$empty' --no-link"

  assert_failure
  assert_output --partial "initial commit"
  refute_output --partial "pass --project"
}

@test "enabled: refuses a monorepo project and points at --project" {
  local sup="$SANDBOX/monorepo"
  git init -q --initial-branch=main "$sup"
  printf '{ "monorepo": true, "workflow": "worktrees" }\n' > "$sup/.devbot.project.jsonc"

  run bash -c "cd '$sup' && bash '$SCRIPT' enabled"

  assert_failure
  assert_output --partial "is a monorepo project"
  assert_output --partial "--project"
}

@test "create: refuses a monorepo project even when it has commits" {
  local sup="$SANDBOX/monorepo"
  git init -q --initial-branch=main "$sup"
  git -C "$sup" config user.email "test@test.com"
  git -C "$sup" config user.name "Test"
  git -C "$sup" config commit.gpgsign false
  printf 'base\n' > "$sup/file.txt"
  git -C "$sup" add -A
  git -C "$sup" commit -qm "base"
  printf '{ "monorepo": true, "workflow": "worktrees" }\n' > "$sup/.devbot.project.jsonc"

  run bash -c "cd '$sup' && bash '$SCRIPT' create feat/nope --no-link"
  assert_failure
  assert_output --partial "is a monorepo project"
  assert_output --partial "--project"

  run bash -c "cd '$WORK' && bash '$SCRIPT' create feat/nope --project '$sup' --no-link"
  assert_failure
  assert_output --partial "is a monorepo project"
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

@test "create: the new worktree is usable the moment create returns" {
  worktree create feat/usable --no-link

  assert_success

  local path="$WORKTREES/feat-usable" physical
  physical="$(cd "$path" && pwd -P)"
  run git -C "$path" status --porcelain
  assert_success
  run git -C "$path" rev-parse --show-toplevel
  assert_success
  assert_output "$physical"
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

# ── enabled / workflow ───────────────────────────────────────────────────────

@test "enabled: reports true by default" {
  worktree enabled

  assert_success
  assert_output "true"
}

@test "enabled: defaults to the worktrees workflow when the key is unset" {
  printf '{ "devbot_dir": ".agents" }\n' > "$WORK/.devbot.project.jsonc"

  worktree enabled

  assert_success
  assert_output "true"
}

@test "enabled: reports an unknown workflow with a distinct status" {
  printf '{ "devbot_dir": ".agents", "workflow": "banana" }\n' > "$WORK/.devbot.project.jsonc"

  worktree enabled

  # 2, not 1: callers must stop and ask instead of falling back to trunk.
  assert_failure 2
  assert_output --partial "unknown workflow 'banana'"
  refute_output --partial "false"
}

@test "enabled: maps the retired worktrees false key to trunk" {
  printf '{ "devbot_dir": ".agents", "worktrees": false }\n' > "$WORK/.devbot.project.jsonc"

  worktree enabled

  assert_failure
  assert_output "false"
}

@test "enabled: maps the retired worktrees true key to worktrees" {
  printf '{ "devbot_dir": ".agents", "worktrees": true }\n' > "$WORK/.devbot.project.jsonc"

  worktree enabled

  assert_success
  assert_output "true"
}

@test "enabled: a project's retired key wins over a migrated global workflow" {
  printf '{ "devbot_dir": ".agents", "worktrees": false }\n' > "$WORK/.devbot.project.jsonc"
  printf '{ "workflow": "worktrees" }\n' > "$SANDBOX/global.jsonc"
  export DEV_BOT_GLOBAL_CONFIG="$SANDBOX/global.jsonc"

  worktree enabled

  assert_failure
  assert_output "false"
}

@test "enabled: falls back to the global config's retired key" {
  printf '{ "devbot_dir": ".agents" }\n' > "$WORK/.devbot.project.jsonc"
  printf '{ "worktrees": false }\n' > "$SANDBOX/global.jsonc"
  export DEV_BOT_GLOBAL_CONFIG="$SANDBOX/global.jsonc"

  worktree enabled

  assert_failure
  assert_output "false"
}

@test "enabled --project: reads the named project's setting from outside it" {
  run bash -c "cd '$SANDBOX' && bash '$SCRIPT' enabled --project '$WORK'"

  assert_success
  assert_output "true"
}

@test "enabled: reports false when the project follows the trunk workflow" {
  printf '{ "devbot_dir": ".agents", "workflow": "trunk" }\n' > "$WORK/.devbot.project.jsonc"

  worktree enabled

  assert_failure
  assert_output "false"
}

@test "create: refuses when the project follows the trunk workflow" {
  printf '{ "devbot_dir": ".agents", "workflow": "trunk" }\n' > "$WORK/.devbot.project.jsonc"

  worktree create feat/nope

  assert_failure
  assert_output --partial "FATAL:"
  assert_output --partial "trunk"
  assert [ ! -d "$WORKTREES/feat-nope" ]
}

@test "create: proceeds when the project selects the worktrees workflow" {
  printf '{ "devbot_dir": ".agents", "workflow": "worktrees" }\n' > "$WORK/.devbot.project.jsonc"

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

@test "list --project: lists the named project's worktrees from outside it" {
  worktree create feat/listed
  assert_success

  run bash -c "cd '$SANDBOX' && bash '$SCRIPT' list --project '$WORK'"

  assert_success
  assert_output --partial "$WORKTREES/feat-listed feat/listed"
}

@test "list: rejects an unknown option instead of ignoring it" {
  worktree list --verbose

  assert_failure
  assert_output --partial "unknown option '--verbose'"
}

# ── path ─────────────────────────────────────────────────────────────────────

@test "path: prints the registered worktree for a branch" {
  worktree create feat/known
  assert_success

  worktree path feat/known

  assert_success
  assert_output "$WORKTREES/feat-known"
}

@test "path: the directory is the branch slug, not the branch path" {
  worktree create feat/deep/nested
  assert_success

  worktree path feat/deep/nested

  assert_success
  assert_output "$WORKTREES/feat-deep-nested"
  assert [ ! -e "$WORKTREES/feat/deep/nested" ]
}

@test "path: reads the registration, so a worktree placed elsewhere is found" {
  git -C "$WORK" worktree add --quiet --no-track -b feat/elsewhere "$SANDBOX/elsewhere" origin/main

  worktree path feat/elsewhere

  assert_success
  assert_output "$SANDBOX/elsewhere"
}

@test "path --project: reads the named project's registration from outside it" {
  worktree create feat/from-outside --no-link
  assert_success

  run bash -c "cd '$SANDBOX' && bash '$SCRIPT' path feat/from-outside --project '$WORK'"

  assert_success
  assert_output "$WORKTREES/feat-from-outside"
}

@test "path: fails when no worktree is registered for the branch" {
  worktree path feat/missing

  assert_failure
  assert_output --partial "FATAL:"
  assert_output --partial "no worktree is registered"
}

@test "path: accepts a full ref and rejects a registration whose directory is gone" {
  worktree create feat/stale --no-link
  assert_success

  worktree path refs/heads/feat/stale
  assert_success
  assert_output "$WORKTREES/feat-stale"

  rm -rf "$WORKTREES/feat-stale"
  worktree path feat/stale

  assert_failure
  assert_output --partial "is registered but gone"
}

@test "path: returns the match among many registrations" {
  local i
  for i in $(seq 1 30); do
    git -C "$WORK" worktree add --quiet --no-track -b "feat/many-$i" "$WORKTREES/feat-many-$i" origin/main
  done

  worktree path feat/many-17

  assert_success
  assert_output "$WORKTREES/feat-many-17"
}

@test "path: refuses the main checkout's own branch" {
  worktree path main

  assert_failure
  assert_output --partial "no worktree is registered"
}

@test "path: rejects a registration whose directory is now another repository" {
  worktree create feat/replaced --no-link
  assert_success

  rm -rf "$WORKTREES/feat-replaced"
  git init -q "$WORKTREES/feat-replaced"

  worktree path feat/replaced

  assert_failure
  assert_output --partial "not a live worktree of"
  assert_output --partial "move it aside"
}

@test "path: rejects a path that now holds another branch's worktree" {
  worktree create feat/one --no-link
  worktree create feat/two --no-link
  assert_success
  mv "$WORKTREES/feat-one" "$SANDBOX/one-moved"
  mv "$WORKTREES/feat-two" "$WORKTREES/feat-one"

  worktree path feat/one

  assert_failure
  assert_output --partial "not a live worktree of"
}

@test "path: the recovery command stays executable for a root with spaces" {
  local spaced="$SANDBOX/space dir"
  git clone -q "$WORK" "$spaced"
  printf '{ "devbot_dir": ".agents", "workflow": "worktrees" }\n' > "$spaced/.devbot.project.jsonc"
  run bash -c "cd '$spaced' && bash '$SCRIPT' create feat/spaced --no-link"
  assert_success
  mv "$spaced/.agents/worktrees/feat-spaced" "$SANDBOX/moved"

  run bash -c "cd '$spaced' && bash '$SCRIPT' path feat/spaced"

  assert_failure
  assert_output --partial "space\\ dir worktree prune"
}

@test "path: two positional args is fatal" {
  worktree path feat/one feat/two

  assert_failure
  assert_output --partial "FATAL:"
}

# ── push ─────────────────────────────────────────────────────────────────────

@test "push: pushes the worktree branch and sets its upstream" {
  worktree create feat/pushed
  assert_success

  local path="$WORKTREES/feat-pushed"
  printf 'work\n' > "$path/feature.txt"
  git -C "$path" add -A
  git -C "$path" commit -qm "feature work"
  local sha
  sha="$(git -C "$path" rev-parse HEAD)"

  worktree push feat/pushed

  assert_success
  assert_output --partial "pushed feat/pushed to origin/feat/pushed"
  assert_output --partial "next: open the pull request against main"
  assert_equal "$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')" "origin/feat/pushed"
  assert_equal "$(git --git-dir="$ORIGIN" rev-parse refs/heads/feat/pushed)" "$sha"
}

@test "push: leaves the main checkout's branch untouched" {
  git -C "$WORK" switch -qc other

  worktree create feat/pushed-from-other
  assert_success

  local path="$WORKTREES/feat-pushed-from-other"
  printf 'work\n' > "$path/feature.txt"
  git -C "$path" add -A
  git -C "$path" commit -qm "feature work"

  worktree push feat/pushed-from-other

  assert_success
  assert_equal "$(git -C "$WORK" branch --show-current)" "other"
}

@test "push: pushes a worktree git registered outside <devbot_dir>" {
  git -C "$WORK" worktree add --quiet --no-track -b feat/elsewhere "$SANDBOX/elsewhere" origin/main
  local path="$SANDBOX/elsewhere"
  printf 'work\n' > "$path/feature.txt"
  git -C "$path" add -A
  git -C "$path" commit -qm "feature work"

  worktree push feat/elsewhere

  assert_success
  assert_equal "$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')" "origin/feat/elsewhere"
}

@test "push: reports a stale registration instead of a bare push failure" {
  worktree create feat/stale-push --no-link
  assert_success
  rm -rf "$WORKTREES/feat-stale-push"

  worktree push feat/stale-push

  assert_failure
  assert_output --partial "is registered but gone"
  assert_output --partial "git -C $WORK worktree prune"
}

@test "push: refuses the main checkout's own branch" {
  worktree push main

  assert_failure
  assert_output --partial "no worktree is registered"
}

@test "push: fails when there is no worktree for the branch" {
  worktree push feat/missing

  assert_failure
  assert_output --partial "FATAL:"
}

@test "push --project: pushes the named project's worktree from outside it" {
  worktree create feat/away-push
  assert_success

  local path="$WORKTREES/feat-away-push"
  printf 'work\n' > "$path/feature.txt"
  git -C "$path" add -A
  git -C "$path" commit -qm "feature work"
  local sha
  sha="$(git -C "$path" rev-parse HEAD)"

  run bash -c "cd '$SANDBOX' && bash '$SCRIPT' push feat/away-push --project '$WORK'"

  assert_success
  assert_output --partial "pushed feat/away-push to origin/feat/away-push"
  assert_equal "$(git --git-dir="$ORIGIN" rev-parse refs/heads/feat/away-push)" "$sha"
}

@test "push: rejects an unknown option instead of treating it as a branch" {
  worktree push --force

  assert_failure
  assert_output --partial "unknown option '--force'"
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

@test "remove: removes a worktree git registered outside <devbot_dir>" {
  git -C "$WORK" worktree add --quiet --no-track -b feat/elsewhere "$SANDBOX/elsewhere" origin/main

  worktree remove feat/elsewhere

  assert_success
  assert [ ! -d "$SANDBOX/elsewhere" ]
  run git -C "$WORK" show-ref --verify --quiet refs/heads/feat/elsewhere
  assert_success
}

@test "remove: reports a stale registration instead of a bare removal failure" {
  worktree create feat/stale-remove --no-link
  assert_success
  rm -rf "$WORKTREES/feat-stale-remove"

  worktree remove feat/stale-remove

  assert_failure
  assert_output --partial "is registered but gone"
  assert_output --partial "git -C $WORK worktree prune"
}

@test "remove: fails when there is no such worktree" {
  worktree remove feat/missing

  assert_failure
  assert_output --partial "FATAL:"
}

@test "remove --project: removes the named project's worktree from outside it" {
  worktree create feat/away-remove
  assert_success

  run bash -c "cd '$SANDBOX' && bash '$SCRIPT' remove feat/away-remove --project '$WORK'"

  assert_success
  assert [ ! -d "$WORKTREES/feat-away-remove" ]
  run git -C "$WORK" show-ref --verify --quiet refs/heads/feat/away-remove
  assert_success
}

@test "remove: rejects an unknown option instead of treating it as a branch" {
  worktree remove --force

  assert_failure
  assert_output --partial "unknown option '--force'"
}
