#!/usr/bin/env bats
# =============================================================================
# src/agentic/git/tests/fixup_commits_tests.bats
# Guards the fixup contract across the files an agent lands on when a branch
# already has an open pull request: the deciding question is whether the
# target commit is reachable from the default branch, not whether it has been
# pushed. Assertions are scoped to the section that carries the rule, and the
# PR-stage commands are asserted by order, so a reworded-but-correct file
# passes and a reordered or unsafe one fails.
# =============================================================================

flatten() {
  tr '\n' ' ' < "$1" | tr -s ' '
}

# Body of a `## <heading>` section, up to the next `## `.
section() {
  awk -v h="## $2" '
    $0 == h      { on = 1; next }
    on && /^## / { exit }
    on           { print }
  ' "$1"
}

# Body of a `### <heading>` subsection, up to the next `### ` or `## `.
subsection() {
  awk -v h="### $2" '
    $0 == h                   { on = 1; next }
    on && (/^### / || /^## /) { exit }
    on                        { print }
  ' "$1"
}

# First line number in <text> matching <pattern>; empty when absent.
line_no() {
  printf '%s\n' "$1" | grep -nE "$2" | head -1 | cut -d: -f1
}

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  AGENTIC_DIR="$(cd "$MODULE_DIR/.." && pwd)"

  FIXUP="$MODULE_DIR/skills/git-fixup-commits/SKILL.md"
  COMMITS="$MODULE_DIR/skills/git-commits/SKILL.md"
  ATOMIC="$MODULE_DIR/skills/git-atomic-commits/SKILL.md"
  ADVANCED="$MODULE_DIR/skills/git-advanced-operations/SKILL.md"
  TAG="$MODULE_DIR/skills/git-tag/SKILL.md"
  WORKTREES="$MODULE_DIR/skills/git-worktrees/SKILL.md"
  COMMIT_CMD="$MODULE_DIR/commands/commit.md"
  CREATE_PR="$AGENTIC_DIR/github/skills/gh-create-pr/SKILL.md"
  CREATE_PR_CMD="$AGENTIC_DIR/github/commands/gh-create-pr.md"
  SOFTWARE_DEV="$AGENTIC_DIR/dev/skills/software-development/SKILL.md"
  DEV_AGENT="$AGENTIC_DIR/devbot/agents/devbot.md"
  REMEMBER="$AGENTIC_DIR/memory/skills/remember-session/SKILL.md"
  MEMORY_MGMT="$AGENTIC_DIR/memory/skills/memory-management/SKILL.md"

  FIXUP_FLAT="$BATS_TEST_TMPDIR/fixup-flat.md"
  COMMITS_FLAT="$BATS_TEST_TMPDIR/commits-flat.md"
  ATOMIC_FLAT="$BATS_TEST_TMPDIR/atomic-flat.md"
  ADVANCED_FLAT="$BATS_TEST_TMPDIR/advanced-flat.md"
  TAG_FLAT="$BATS_TEST_TMPDIR/tag-flat.md"
  WORKTREES_FLAT="$BATS_TEST_TMPDIR/worktrees-flat.md"
  CREATE_PR_FLAT="$BATS_TEST_TMPDIR/create-pr-flat.md"
  SOFTWARE_DEV_FLAT="$BATS_TEST_TMPDIR/software-dev-flat.md"

  flatten "$FIXUP" > "$FIXUP_FLAT"
  flatten "$COMMITS" > "$COMMITS_FLAT"
  flatten "$ATOMIC" > "$ATOMIC_FLAT"
  flatten "$ADVANCED" > "$ADVANCED_FLAT"
  flatten "$TAG" > "$TAG_FLAT"
  flatten "$WORKTREES" > "$WORKTREES_FLAT"
  flatten "$CREATE_PR" > "$CREATE_PR_FLAT"
  flatten "$SOFTWARE_DEV" > "$SOFTWARE_DEV_FLAT"
  flatten "$REMEMBER" > "$BATS_TEST_TMPDIR/remember-flat.md"
  flatten "$MEMORY_MGMT" > "$BATS_TEST_TMPDIR/memory-mgmt-flat.md"
  REMEMBER_FLAT="$BATS_TEST_TMPDIR/remember-flat.md"
  MEMORY_MGMT_FLAT="$BATS_TEST_TMPDIR/memory-mgmt-flat.md"
}

@test "git-fixup-commits frontmatter names devbot:git-fixup-commits" {
  run sed -n '1,4p' "$FIXUP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: devbot:git-fixup-commits"* ]]
}

@test "the choose table routes a commit unique to this branch to a fixup" {
  table="$(section "$FIXUP" 'Choose the right action first')"
  row="$(printf '%s\n' "$table" | grep 'unique to this branch')"
  [ -n "$row" ]
  [[ "$row" == *'--fixup=<sha>'* ]]
  ! printf '%s\n' "$row" | grep -qi 'unpushed'
  # Reachability, not "not on the default branch", decides: a sibling branch counts too.
  grep -qi 'neither the default branch nor any other branch' "$FIXUP_FLAT"
}

@test "pushed feature-branch commits are not a reason to prefer a follow-up commit" {
  scope="$(section "$FIXUP" 'Branch scope (MUST)')"
  printf '%s\n' "$scope" | grep -qi 'open pull request'
  ! printf '%s\n' "$scope" | grep -qi 'unpushed'
  ! grep -qi 'protected or shared branch' "$COMMITS_FLAT"
  grep -qi 'reachable from the default branch' "$COMMITS_FLAT"
}

@test "the PR stage folds, verifies, then force-pushes in that order" {
  stage="$(section "$FIXUP" 'PR stage')"
  fold="$(line_no "$stage" 'autosquash')"
  verify="$(line_no "$stage" 'git log --oneline')"
  push="$(line_no "$stage" 'force-with-lease')"
  [ -n "$fold" ] && [ -n "$verify" ] && [ -n "$push" ]
  [ "$fold" -lt "$verify" ]
  [ "$verify" -lt "$push" ]
}

@test "every force-push in the flow is a leased push" {
  # Catches `git push --force`, `git push -u origin --force` and `git -C <dir> push --force`.
  ! grep -qE '(^|[ `])push[^`]*[[:space:]]--force([^-]|$)' \
    "$FIXUP" "$COMMITS" "$WORKTREES" "$CREATE_PR" "$CREATE_PR_CMD"
}

@test "the squash approval shows the push command and leaves it to the human" {
  workflow="$(section "$FIXUP" 'Workflow')"
  step5="$(printf '%s\n' "$workflow" | awk '/^### 5\./,/^### 6\./')"
  printf '%s\n' "$step5" | grep -qi 'leased push command'
  printf '%s\n' "$step5" | grep -qi "human's to run"
}

@test "the lease is captured before the rewrite and never refreshed after" {
  workflow="$(section "$FIXUP" 'Workflow')"
  step5="$(printf '%s\n' "$workflow" | awk '/^### 5\./,/^### 6\./')"
  step7="$(printf '%s\n' "$workflow" | awk '/^### 7\./,/^### 8\./')"
  # Capture and base-fetch belong to the pre-rewrite step, not the hand-off step.
  printf '%s\n' "$step5" | grep -q 'rev-parse origin/<branch>'
  printf '%s\n' "$step5" | grep -q 'fetch origin <default>'
  printf '%s\n' "$step7" | grep -q 'force-with-lease=refs/heads/<branch>:<expected-sha>'
  ! printf '%s\n' "$step7" | grep -qE 'git (fetch|rev-parse)'
  ! printf '%s\n' "$workflow" | grep -qE 'git fetch origin <branch>'
}

@test "a stale checkout is reconciled before the lease is captured" {
  workflow="$(section "$FIXUP" 'Workflow')"
  step1="$(printf '%s\n' "$workflow" | awk '/^### 1\./,/^### 2\./')"
  printf '%s\n' "$step1" | grep -q 'rev-list --count HEAD..origin/<branch>'
  # A never-pushed branch has no such ref; the comparison must be guarded.
  printf '%s\n' "$step1" | grep -q 'rev-parse --verify --quiet origin/<branch>'
  grep -qi 'stop and reconcile' "$FIXUP_FLAT"
}

@test "an unpushed branch takes an ordinary push instead of a lease" {
  workflow="$(section "$FIXUP" 'Workflow')"
  step5="$(printf '%s\n' "$workflow" | awk '/^### 5\./,/^### 6\./')"
  step7="$(printf '%s\n' "$workflow" | awk '/^### 7\./,/^### 8\./')"
  printf '%s\n' "$step5" | grep -q 'rev-parse --verify --quiet origin/<branch>'
  printf '%s\n' "$step7" | grep -qi 'never been pushed'
  printf '%s\n' "$step7" | grep -q 'git push -u origin <branch>'
}

@test "the worktree finish squashes non-interactively, then prepares the push" {
  block="$(subsection "$WORKTREES" 'Squash fixups before merge')"
  printf '%s\n' "$block" | grep -q 'GIT_SEQUENCE_EDITOR=:'
  printf '%s\n' "$block" | grep -q 'origin/<default>'
  printf '%s\n' "$block" | grep -q 'force-with-lease=refs/heads/<branch>:<expected-sha>'
  printf '%s\n' "$block" | grep -qi 'hand this to the human'
  # Refresh, then capture the lease, then rebase — in that order.
  fetch="$(line_no "$block" 'git -C <worktree> fetch --all --prune')"
  lease="$(line_no "$block" 'expected_sha=')"
  rebase="$(line_no "$block" 'rebase -i --autosquash')"
  [ -n "$fetch" ] && [ -n "$lease" ] && [ -n "$rebase" ]
  [ "$fetch" -lt "$lease" ]
  [ "$lease" -lt "$rebase" ]
  # A checkout behind, or a force-reset/deleted ref, must reconcile first.
  printf '%s\n' "$block" | grep -q 'before="$(git -C <worktree> rev-parse origin/<branch>)"'
  printf '%s\n' "$block" | grep -q 'rev-list --count HEAD..origin/<branch>'
  printf '%s\n' "$block" | grep -q 'reconcile before squashing'
  # The lease is only meaningful if the branch ref was not refreshed after capture.
  ! printf '%s\n' "$block" | grep -qE 'git -C [^ ]+ fetch origin <branch>'
}

@test "the target is proved unique with an all-refs containment check" {
  grep -q 'for-each-ref --contains' "$FIXUP_FLAT"
  grep -q 'grep -vxF' "$FIXUP_FLAT"
  grep -qi 'anything left is a sibling' "$FIXUP_FLAT"
}

@test "every remote is refreshed before the containment classification" {
  workflow="$(section "$FIXUP" 'Workflow')"
  step1="$(printf '%s\n' "$workflow" | awk '/^### 1\./,/^### 2\./')"
  fetch="$(line_no "$step1" 'git fetch --all --prune')"
  check="$(line_no "$step1" 'for-each-ref --contains')"
  [ -n "$fetch" ] && [ -n "$check" ]
  [ "$fetch" -lt "$check" ]
  # A fetch can hide a deletion or a force-reset; the head is compared around it
  # and a mismatch stops the workflow before any lease is captured.
  printf '%s\n' "$step1" | grep -q 'before="$(git rev-parse origin/<branch>)"'
  printf '%s\n' "$step1" | grep -q 'stop and reconcile'
  printf '%s\n' "$step1" | grep -q 'exit 1'
}

@test "the vault scan walks commit path history, not the net diff" {
  grep -q 'git log --format= --name-only' "$TAG_FLAT"
  grep -q -- '--merges' "$TAG_FLAT"
  grep -q 'origin/<default>..<source-branch>' "$TAG_FLAT"
  grep -qF '"${base}..${source}"' "$MODULE_DIR/tools/git.sh"
}

@test "a pushed feature branch is not classified as shared" {
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  git config --global user.email test@example.com
  git config --global user.name Test
  git config --global commit.gpgsign false
  git init -q --bare "$BATS_TEST_TMPDIR/origin.git"
  git clone -q "$BATS_TEST_TMPDIR/origin.git" "$BATS_TEST_TMPDIR/work"
  cd "$BATS_TEST_TMPDIR/work" || return 1
  echo a > a.txt
  git add a.txt
  git commit -qm "chore: initial"
  git push -q -u origin HEAD:main
  git checkout -q -b 'feature/foo+bar'
  echo b > b.txt
  git add b.txt
  git commit -qm "feat: b"
  git push -q -u origin 'feature/foo+bar'

  sha="$(git rev-parse HEAD)"
  current="$(git branch --show-current)"
  # The documented check: the branch and its own remote-tracking ref are expected.
  others="$(git for-each-ref --contains="$sha" --format='%(refname)' refs/heads refs/remotes \
    | grep -vxF -e "refs/heads/${current}" -e "refs/remotes/origin/${current}" || true)"
  [ -z "$others" ]
}

@test "the PR stage checks the range for memory-vault files, path-scoped" {
  stage="$(section "$FIXUP" 'PR stage')"
  printf '%s\n' "$stage" | grep -q -- '--name-only'
  printf '%s\n' "$stage" | grep -q '<devbot_dir>/memory'
  printf '%s\n' "$stage" | grep -qi 'confirm the human wants that'
}

@test "the release recipe re-checks immediately before merging" {
  # Once before publishing, once after the human publishes the rewrite.
  [ "$(grep -c 'check_release_guards || exit 1' "$TAG")" -eq 2 ]
  # The rewrite must be published before `gh pr merge`, which reads the remote,
  # and only from a checkout that already matches the remote head.
  grep -qF 'force-with-lease=refs/heads/<source-branch>:$expected' "$TAG"
  grep -q 'does not match origin — reconcile before rewriting' "$TAG"
}

@test "the containment check treats no sibling as the normal case" {
  grep -q 'siblings="$(git for-each-ref --contains' "$FIXUP_FLAT"
  grep -q 'target is shared' "$FIXUP_FLAT"
}

@test "the release recipe keeps the protected path off the local merge" {
  grep -qi 'the PR merge replaces the local merge' "$TAG_FLAT"
  grep -qi 'do not run `tag.sh merge`' "$TAG_FLAT"
}

@test "the release merge path guards against publishing vault commits" {
  grep -qi 'memory-vault commits would be published' "$TAG_FLAT"
  grep -q -- '--name-only' "$TAG_FLAT"
  # Fail closed when the base is unresolvable — an empty range proves nothing.
  grep -qi 'cannot verify vault commits' "$TAG_FLAT"
  # A trailing separator in the setting must not become `<dir>//memory/`.
  grep -qF 'while [ "${vault%/}" != "$vault" ]' "$TAG_FLAT"
}

@test "every squash base is origin/<default>, never the local default" {
  stage="$(section "$FIXUP" 'PR stage')"
  printf '%s\n' "$stage" | grep -q 'origin/<default>'
  printf '%s\n' "$stage" | grep -qi 'never the local'
  bases="$(section "$FIXUP" 'Choosing the rebase base')"
  printf '%s\n' "$bases" | grep -q 'origin/<default>'
  # A rebase onto the bare local default would carry stranded memory commits into the PR.
  ! printf '%s\n' "$bases" | grep -qE 'autosquash (main|master|<default>)( |$)'
}

@test "the agent hands the force-push to the human because the guard blocks it" {
  workflow="$(section "$FIXUP" 'Workflow')"
  step7="$(printf '%s\n' "$workflow" | awk '/^### 7\./,/^### 8\./')"
  printf '%s\n' "$step7" | grep -qi 'do not force-push'
  printf '%s\n' "$step7" | grep -qi 'human'
  grep -qi 'guards module blocks' "$SOFTWARE_DEV_FLAT"
}

@test "the release PR merge path refuses to rebase-merge outstanding fixups" {
  grep -qi 'fold the fixups before merging' "$TAG_FLAT"
  # --oneline prefixes the SHA, so an anchored subject match must use --format=%s.
  grep -q 'git log --format=%s' "$TAG_FLAT"
  grep -qi 'rebase' "$TAG_FLAT"
  grep -qi 'squash' "$TAG_FLAT"
}

@test "the commit protocol hands the pre-merge push to the human" {
  grep -qi 'never push' "$SOFTWARE_DEV_FLAT"
  grep -qi 'guards module blocks' "$SOFTWARE_DEV_FLAT"
  grep -qi 'pre-merge squash' "$SOFTWARE_DEV_FLAT"
  grep -qi 'pre-merge squash' "$DEV_AGENT"
  grep -qi 'force-with-lease' "$DEV_AGENT"
}

@test "git-atomic-commits routes a correction on this branch to a fixup" {
  grep -qi 'fixup' "$ATOMIC_FLAT"
  grep -qi 'default branch' "$ATOMIC_FLAT"
  grep -qi 'devbot:git-fixup-commits' "$ATOMIC_FLAT"
}

@test "the commit command uses the unique-to-this-branch criterion" {
  grep -qi 'unique to the current branch' "$COMMIT_CMD"
  ! grep -qi 'not yet in another branch' "$COMMIT_CMD"
}

@test "opening a PR forbids the push and points at the human-run squash" {
  grep -qi 'guards module blocks' "$CREATE_PR_FLAT"
  grep -qi 'force-push' "$CREATE_PR_CMD"
  grep -qi 'human' "$CREATE_PR_CMD"
}

@test "advanced operations points at the sanctioned pre-merge squash" {
  grep -qi 'exception' "$ADVANCED_FLAT"
  grep -qi 'devbot:git-fixup-commits' "$ADVANCED_FLAT"
}

@test "memory vault commits are normal commits, never fixups" {
  grep -qi 'normal commits' "$REMEMBER_FLAT"
  grep -qi 'memory files only' "$REMEMBER_FLAT"
  ! grep -qi 'fixup commits only' "$REMEMBER_FLAT"
  ! grep -qi 'git commit --fixup' "$REMEMBER_FLAT"
  grep -qi 'never as fixups' "$MEMORY_MGMT_FLAT"
}

@test "memory commits are surfaced to the human, not carried by the agent" {
  grep -qi 'human decides how they reach origin' "$REMEMBER_FLAT"
  grep -qi 'do not reset, rebase, or push' "$REMEMBER_FLAT"
  grep -qi "do not change a new branch's base" "$REMEMBER_FLAT"
}

@test "memory commits are skipped when the main checkout is on another branch" {
  grep -qi 'if that checkout is on any other branch' "$REMEMBER_FLAT"
  grep -qi 'leave the memory files uncommitted' "$REMEMBER_FLAT"
  grep -qi 'do not commit' "$WORKTREES_FLAT"
}

@test "the worktree policy keeps memory commits off the PR and surfaces them" {
  grep -qi 'normal commits' "$WORKTREES_FLAT"
  grep -qi 'do not ride along automatically' "$WORKTREES_FLAT"
  grep -qi 'let the user decide' "$WORKTREES_FLAT"
}

@test "the fixup rule names a memory-vault commit as a normal commit" {
  grep -qi 'memory' "$FIXUP_FLAT"
  grep -qi 'normal commit' "$FIXUP_FLAT"
  grep -qi 'remember-session' "$FIXUP_FLAT"
}
