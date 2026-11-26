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
  REVIEW_LOOP="$AGENTIC_DIR/dev/skills/review-loop/SKILL.md"
  FULL_LOOP_CMD="$AGENTIC_DIR/dev/commands/full-review-loop.md"
  DEV_AGENT="$AGENTIC_DIR/devbot/agents/devbot.md"
  REMEMBER="$AGENTIC_DIR/memory/skills/remember-session/SKILL.md"
  MEMORY_MGMT="$AGENTIC_DIR/memory/skills/memory-management/SKILL.md"
  COMMIT_MEMORIES="$AGENTIC_DIR/memory/skills/commit-memories/SKILL.md"

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
  flatten "$COMMIT_MEMORIES" > "$BATS_TEST_TMPDIR/commit-memories-flat.md"
  REMEMBER_FLAT="$BATS_TEST_TMPDIR/remember-flat.md"
  MEMORY_MGMT_FLAT="$BATS_TEST_TMPDIR/memory-mgmt-flat.md"
  COMMIT_MEMORIES_FLAT="$BATS_TEST_TMPDIR/commit-memories-flat.md"
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

@test "the squash plan shows the push command, asks nothing, and leaves the push to the human" {
  workflow="$(section "$FIXUP" 'Workflow')"
  step5="$(printf '%s\n' "$workflow" | awk '/^### 5\./,/^### 6\./')"
  printf '%s\n' "$step5" | grep -qi 'leased push command'
  printf '%s\n' "$step5" | grep -qi "human's to run"
  # The plan is a record, not a gate: nothing may wait on a yes.
  ! printf '%s\n' "$step5" | grep -qiE 'wait for a yes|ask for approval|getting approval'
}

# The sentences these files carried while the squash was gated. A regression is
# one of them coming back, so match the forms actually in use and nothing
# looser — `git-commits` legitimately still requires approval for shared history.
# Flattened first: the old wording wrapped across lines, and a per-line grep
# misses `... showing the plan and` / `getting approval ...` entirely. On a hit
# the file and the matched fragment are printed, so a false fail on another
# action's approval sentence (an implementation plan, a check-in) names its cause.
gate_sentence() { # exits 0 when a gating sentence is present, wrapped or not
  local f hit
  for f in "$@"; do
    hit="$(flatten "$f" | grep -oiE 'show(ing)? the plan and get(ting)? approval|wait for a yes|ask before _?squash|get explicit approval|approved[^.]{0,40}squash' | head -1)"
    [ -n "$hit" ] || continue
    echo "gate sentence in $f: $hit"
    return 0
  done
  return 1
}

# Plant <sentence> in a copy of <file> and require the sweep to see it. Used
# with the verbatim old wording, line breaks included.
plant_and_catch() { # <file> <sentence>
  [ -f "$1" ] || return 1
  local planted="$BATS_TEST_TMPDIR/planted-$(basename "$(dirname "$1")").md"
  { cat "$1"; printf '\n%s\n' "$2"; } > "$planted"
  gate_sentence "$planted" || {
    echo "unmatched gate sentence: $2"
    return 1
  }
}

@test "no de-gated instruction asks permission before squashing fixups" {
  # Every file whose squash wording this change corrected: the six with a gate
  # sentence, plus `git-advanced-operations`, whose "approved pre-merge squash"
  # was the same claim in one word. The `gh-create-pr` pair is out on purpose:
  # its approval governs the PR plan, not this squash. `git-commits` is out
  # because its approval rule for shared history is legitimate — it is covered
  # by the positive assertion below. `gh-review-loop`, `auto-dev`,
  # `address-review` and `full-audit-and-fix-loop` carry no gate.
  local f
  for f in "$FIXUP" "$ADVANCED" "$WORKTREES" "$SOFTWARE_DEV" "$REVIEW_LOOP" "$FULL_LOOP_CMD" "$DEV_AGENT"; do
    [ -f "$f" ] || {
      echo "missing guard target: $f"
      return 1
    }
  done
  ! gate_sentence "$FIXUP" "$ADVANCED" "$WORKTREES" "$SOFTWARE_DEV" "$REVIEW_LOOP" "$FULL_LOOP_CMD" "$DEV_AGENT"
  # The rule is stated positively where the flow is defined, and `git-commits`
  # names the squash as the standing exception to its approval rule.
  grep -qi 'squashing needs no permission' "$FIXUP"
  grep -qi 'standing exception is the pre-merge squash' "$COMMITS"
}

@test "the guard catches each gate sentence these files used to carry" {
  # Mutation test: plant the real pre-change sentence in a copy of each file and
  # require the sweep to see it, so a matcher that only recognises paraphrases
  # fails here instead of letting a later regression through. Three of the old
  # sentences wrapped across lines — those are planted verbatim, wrap included.
  plant_and_catch "$FIXUP" 'The fixup is still right; ask before _squashing_, not before committing'
  plant_and_catch "$ADVANCED" 'The approved pre-merge squash of a pull-request branch is the sanctioned exception'
  plant_and_catch "$WORKTREES" $'squash them just before merge — after showing the plan and\ngetting approval:'
  plant_and_catch "$SOFTWARE_DEV" $'showing the plan and getting approval\nfirst as `devbot:git-fixup-commits` requires'
  plant_and_catch "$REVIEW_LOOP" $'showing the plan and getting\napproval first.'
  plant_and_catch "$FULL_LOOP_CMD" $'showing\nthe plan and getting approval.'
  plant_and_catch "$DEV_AGENT" 'showing the plan and getting approval first as `devbot:git-fixup-commits` requires'
}

@test "the lease is captured before the rewrite and never refreshed after" {
  workflow="$(section "$FIXUP" 'Workflow')"
  step5="$(printf '%s\n' "$workflow" | awk '/^### 5\./,/^### 6\./')"
  step7="$(printf '%s\n' "$workflow" | awk '/^### 7\./,/^### 8\./')"
  # Capture and base-fetch belong to the pre-rewrite step, not the hand-off step.
  printf '%s\n' "$step5" | grep -q 'rev-parse origin/<branch>'
  printf '%s\n' "$step5" | grep -q 'fetch origin <default>'
  printf '%s\n' "$step7" | grep -q 'force-with-lease=<branch>:<expected-sha>'
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
  printf '%s\n' "$block" | grep -q 'force-with-lease=<branch>:<expected-sha>'
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

@test "the rewrite range is proved unique by every commit, not only the target" {
  workflow="$(section "$FIXUP" 'Workflow')"
  step1="$(printf '%s\n' "$workflow" | awk '/^### 1\./,/^### 2\./')"
  printf '%s\n' "$step1" | grep -q 'rev-list origin/<default>\.\.HEAD'
  printf '%s\n' "$step1" | grep -qF 'for-each-ref --contains="$sha"'
  printf '%s\n' "$step1" | grep -q 'shared commits in the rewrite range'
  # The worktree recipe must carry the same proof, not just the remote-head check.
  block="$(subsection "$WORKTREES" 'Squash fixups before merge')"
  printf '%s\n' "$block" | grep -q 'shared commits in the rewrite range'
}

@test "the worktree squash prints the plan before it applies it" {
  block="$(subsection "$WORKTREES" 'Squash fixups before merge')"
  plan="$(printf '%s\n' "$block" | grep -nF 'grep -v "^#" "$1"; false' | head -1 | cut -d: -f1)"
  apply="$(printf '%s\n' "$block" | grep -nF 'GIT_SEQUENCE_EDITOR=: git -C' | head -1 | cut -d: -f1)"
  [ -n "$plan" ] && [ -n "$apply" ] && [ "$plan" -lt "$apply" ]
}

@test "the proofs and the plan preview fail closed" {
  # grep's status 1 (no sibling) is the only status tolerated, and only around
  # the grep; an enumeration failure or a rebase that ran stops the flow.
  grep -qF 'cannot enumerate refs for' "$FIXUP_FLAT"
  grep -qF 'cannot enumerate refs for' "$WORKTREES_FLAT"
  grep -qF 'siblings="$(printf' "$FIXUP_FLAT"
  grep -qF 'siblings="$(printf' "$WORKTREES_FLAT"
  grep -qF 'preview printed no plan' "$FIXUP_FLAT"
  grep -qF 'preview printed no plan' "$WORKTREES_FLAT"
  grep -qF 'preview applied a rebase' "$FIXUP_FLAT"
  grep -qF 'preview applied a rebase' "$WORKTREES_FLAT"
  grep -qF 'preview moved HEAD' "$FIXUP_FLAT"
  grep -qF 'preview moved HEAD' "$WORKTREES_FLAT"
  # The PR stage re-proves the range, which fixups since step 1 have extended.
  stage="$(section "$FIXUP" 'PR stage')"
  printf '%s\n' "$stage" | grep -qi 're-run step 1'
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
  grep -qF 'force-with-lease=<source-branch>:$expected' "$TAG"
  grep -q 'does not match origin — reconcile before rewriting' "$TAG"
}

@test "the containment check treats no sibling as the normal case" {
  # Captured into a variable, never trusted to grep's exit status: no sibling is
  # the normal case, and grep exits 1 there.
  grep -qF 'range="$(git rev-list origin/<default>..HEAD)"' "$FIXUP_FLAT"
  grep -qF 'shared commits in the rewrite range' "$FIXUP_FLAT"
  grep -qF 'grep -vxF' "$FIXUP_FLAT"
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

@test "the worktree finish reports the pull request by its URL" {
  local finish
  finish="$(section "$WORKTREES" 'Finish' | tr '\n' ' ' | tr -s ' ')"
  [ -n "$finish" ]
  printf '%s\n' "$finish" | grep -qF 'and report its URL'
  # The bare forms are banned: a number, `#<n>`, and "the PR".
  ! printf '%s\n' "$finish" | grep -qE '(PR|pull request) ?#[0-9]+'
}

@test "the squash hand-over names the pull request by its URL" {
  local step
  step="$(subsection "$FIXUP" '7. Hand the publish to the human' | tr '\n' ' ' | tr -s ' ')"
  [ -n "$step" ]
  printf '%s\n' "$step" | grep -qF "the pull request's URL"
  ! printf '%s\n' "$step" | grep -qF "the PR's"
}

@test "advanced operations points at the sanctioned pre-merge squash" {
  grep -qi 'exception' "$ADVANCED_FLAT"
  grep -qi 'devbot:git-fixup-commits' "$ADVANCED_FLAT"
}

@test "memory vault commits are ordinary commits, never fixups" {
  grep -qi 'ordinary commits' "$COMMIT_MEMORIES_FLAT"
  grep -qi 'never fixups' "$COMMIT_MEMORIES_FLAT"
  ! grep -qi 'git commit --fixup' "$COMMIT_MEMORIES_FLAT"
  grep -qi 'never fixups and never on the default branch' "$MEMORY_MGMT_FLAT"
}

@test "the commit policy sends memory to commit-memories, not the main checkout" {
  grep -qi 'commit-memories' "$COMMITS_FLAT"
  grep -qi 'temporary linked worktree and memory branch' "$COMMITS_FLAT"
  # The retired exception is what this change removes; it must not come back.
  ! grep -qi 'except the finish flow' "$COMMITS_FLAT"
}

@test "memory notes are published on their own branch, not left on the local default" {
  grep -qi 'published through a pull request' "$REMEMBER_FLAT"
  grep -qi 'never committed to the local default branch' "$REMEMBER_FLAT"
  grep -qi "opens or appends each group's standing pull request" "$REMEMBER_FLAT"
  grep -qi 'Report every pull request URL' "$COMMIT_MEMORIES_FLAT"
}

@test "memory publishing never switches the main checkout's branch" {
  grep -qi 'never switch its checked-out branch' "$COMMIT_MEMORIES_FLAT"
  grep -qi 'temporary linked worktree' "$COMMIT_MEMORIES_FLAT"
  grep -qi 'branch is never switched' "$WORKTREES_FLAT"
}

@test "the worktree policy keeps memory off the task PR and gives it its own" {
  grep -qi 'carries only its work commits' "$WORKTREES_FLAT"
  grep -qi 'Never put vault commits on a task branch' "$WORKTREES_FLAT"
  grep -qi 'stranded local commit' "$WORKTREES_FLAT"
  grep -qi 'let the user decide' "$WORKTREES_FLAT"
}

@test "the fixup rule names a memory-vault commit as an ordinary commit" {
  grep -qi 'memory-vault commit' "$FIXUP_FLAT"
  grep -qi 'ordinary commit' "$FIXUP_FLAT"
  grep -qi 'commit-memories' "$FIXUP_FLAT"
}

@test "the hand-off keys the lease on the short branch, not a qualified ref" {
  block="$(subsection "$WORKTREES" 'Squash fixups before merge')"
  step7="$(section "$FIXUP" 'Workflow')"
  # A fully-qualified key can leave the push unforced (non-fast-forward).
  ! printf '%s\n' "$block" | grep -q 'force-with-lease=refs/heads/'
  ! printf '%s\n' "$step7" | grep -q 'force-with-lease=refs/heads/'
  printf '%s\n' "$block" | grep -q 'origin "$head_sha:<branch>"'
  grep -qF 'force-with-lease=<branch>:<expected-sha>' "$FIXUP"
}
