#!/usr/bin/env bats
# =============================================================================
# src/agentic/memory/tests/commit_memories_tests.bats
# Guards the contract of the wrap-up memory publisher: one standing pull request
# per repository, owned by the project each note belongs to, published
# unattended from the finish flow, and never merged by the agent.
# Assertions are scoped to the section that carries each rule, so a reworded
# but correct file passes and a rule deleted or weakened fails.
# =============================================================================

flat_text() {
  tr '\n' ' ' | tr -s ' '
}

flatten() {
  flat_text < "$1"
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

# One flattened line for a section/subsection body.
section_flat()    { section "$1" "$2" | flat_text; }
subsection_flat() { subsection "$1" "$2" | flat_text; }

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
  AGENTIC_DIR="$(cd "$MODULE_DIR/.." && pwd)"

  SKILL="$MODULE_DIR/skills/commit-memories/SKILL.md"
  REMEMBER="$MODULE_DIR/skills/remember-session/SKILL.md"
  MEMORY_MGMT="$MODULE_DIR/skills/memory-management/SKILL.md"
  WORKTREES="$AGENTIC_DIR/git/skills/git-worktrees/SKILL.md"
  GH_CREATE_PR="$AGENTIC_DIR/github/skills/gh-create-pr/SKILL.md"
  SOFTWARE_DEV="$AGENTIC_DIR/dev/skills/software-development/SKILL.md"
  CONFIG_DOCS="$AGENTIC_DIR/../../docs/configuration.md"

  FLAT="$BATS_TEST_TMPDIR/skill-flat.md"
  REMEMBER_FLAT="$BATS_TEST_TMPDIR/remember-flat.md"
  MEMORY_MGMT_FLAT="$BATS_TEST_TMPDIR/memory-mgmt-flat.md"
  WORKTREES_FLAT="$BATS_TEST_TMPDIR/worktrees-flat.md"
  GH_CREATE_PR_FLAT="$BATS_TEST_TMPDIR/gh-create-pr-flat.md"
  SOFTWARE_DEV_FLAT="$BATS_TEST_TMPDIR/software-dev-flat.md"

  flatten "$SKILL" > "$FLAT"
  flatten "$REMEMBER" > "$REMEMBER_FLAT"
  flatten "$MEMORY_MGMT" > "$MEMORY_MGMT_FLAT"
  flatten "$WORKTREES" > "$WORKTREES_FLAT"
  flatten "$GH_CREATE_PR" > "$GH_CREATE_PR_FLAT"
  flatten "$SOFTWARE_DEV" > "$SOFTWARE_DEV_FLAT"
}

@test "skill frontmatter names devbot:commit-memories" {
  run sed -n '1,4p' "$SKILL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name: devbot:commit-memories"* ]]
}

@test "the description carries the user triggers, not just the behaviour" {
  grep -qF "Triggers on 'commit the memories'" "$FLAT"
  grep -qF "publish the session memories" "$FLAT"
}

@test "remember-session hands the captured files to the publisher" {
  grep -qF 'devbot:commit-memories' "$REMEMBER_FLAT"
  grep -qF 'after the capture has written its notes' "$REMEMBER_FLAT"
  # The capture stays the only writer.
  grep -qF 'write no memory files after this step' "$REMEMBER_FLAT"
}

@test "each stream has its own fixed title, never composed from the notes" {
  local publish
  publish="$(subsection_flat "$SKILL" '6. Publish')"
  printf '%s\n' "$publish" | grep -qF -- "--title '<group title>'"
  printf '%s\n' "$publish" | grep -qF 'chore(agents): commit memories and lessons learned'
  printf '%s\n' "$publish" | grep -qF 'chore(global-memories): commit global memories and lessons learned'
  printf '%s\n' "$publish" | grep -qF "The group's title is fixed"
  printf '%s\n' "$publish" | grep -qF 'not a summary of the notes'
}

@test "vault and global notes are separate streams with their own titles" {
  grep -qF 'Group by **repository and stream**' "$FLAT"
  grep -qF 'never mix the two in one branch or pull request' "$FLAT"
  grep -qF 'chore(global-memories): commit global memories and lessons learned' "$FLAT"
}

@test "one standing pull request per group is appended to, never duplicated" {
  local lookup
  lookup="$(subsection_flat "$SKILL" '3. Find the standing pull request for each group')"
  printf '%s\n' "$lookup" | grep -qF 'append to it'
  printf '%s\n' "$lookup" | grep -qF 'open no second pull request'
  printf '%s\n' "$lookup" | grep -qF 'do not guess and do not open a third'
  printf '%s\n' "$lookup" | grep -qF 'The finish flow does not wait for an answer'
  # The race is stated, not papered over.
  printf '%s\n' "$lookup" | grep -qF 'Lookup and create are not atomic'
  printf '%s\n' "$lookup" | grep -qF 'leave both open'
}

@test "the standing lookup matches each stream's title exactly, never through search syntax" {
  local lookup
  lookup="$(subsection_flat "$SKILL" '3. Find the standing pull request for each group')"
  printf '%s\n' "$lookup" | grep -qF 'gh pr list --state open --limit 200'
  printf '%s\n' "$lookup" | grep -qF 'select(.title == "chore(agents): commit memories and lessons learned")'
  printf '%s\n' "$lookup" | grep -qF 'select(.title == "chore(global-memories): commit global memories and lessons learned")'
  printf '%s\n' "$lookup" | grep -qF 'never through `--search`'
  printf '%s\n' "$lookup" | grep -qF 'default page is 30'
}

@test "the base is fetched explicitly, so a tag-only install still resolves it" {
  local lookup prepare
  lookup="$(subsection_flat "$SKILL" '3. Find the standing pull request for each group')"
  prepare="$(subsection_flat "$SKILL" '4. Prepare the branch')"
  printf '%s\n' "$lookup" | grep -qF 'refs/heads/$default:refs/remotes/origin/$default'
  printf '%s\n' "$lookup" | grep -qF 'shallow, tag-only clone'
  printf '%s\n' "$lookup" | grep -qF 'is-shallow-repository'
  printf '%s\n' "$lookup" | grep -qF 'A plain `git fetch origin` is not enough'
  printf '%s\n' "$prepare" | grep -qF 'refs/heads/<headRefName>:refs/remotes/origin/<headRefName>'
  printf '%s\n' "$lookup" | grep -qFi 'neither `origin/<default>` nor `origin/<headRefName>` resolves'
}

@test "the finish flow publishes without a confirmation" {
  grep -qF 'Unattended.' "$FLAT"
  grep -qF 'The finish flow asks nothing' "$FLAT"
  grep -qF 'Publish unattended from the finish flow' "$FLAT"
  ! grep -qiF 'ask once' "$FLAT"
  ! grep -qiF 'get approval' "$FLAT"
}

@test "gh prerequisites are checked before publishing" {
  local pre
  pre="$(section_flat "$SKILL" 'Preconditions')"
  printf '%s\n' "$pre" | grep -qF 'gh` is installed and authenticated'
  printf '%s\n' "$pre" | grep -qF 'gh auth status'
  printf '%s\n' "$pre" | grep -qF 'reachable and pushable'
}

@test "a project-vault note goes to its owning project, a global lesson to dev-bot" {
  local collect
  collect="$(subsection_flat "$SKILL" '1. Collect the capture'\''s files and group them by repository and stream')"
  grep -qF 'A project-vault note goes to that' "$FLAT"
  grep -qF 'global lesson goes to the dev-bot repository' "$FLAT"
  printf '%s\n' "$collect" | grep -qF '| vault'
  printf '%s\n' "$collect" | grep -qF '| global'
  printf '%s\n' "$collect" | grep -qF 'latent/global/<tech>/...'
  printf '%s\n' "$collect" | grep -qF '$DEV_BOT_ROOT/storage/global-memories/<tech>/...'
  printf '%s\n' "$collect" | grep -qF 'never the polyrepo root'
  # The symlink is resolved to the tracked target before any check or copy.
  printf '%s\n' "$collect" | grep -qF 'Resolve it physically'
  printf '%s\n' "$collect" | grep -qF 'storage/global-memories/<tech>/note.md'
  # A global note resolving into dev-bot is expected, not "somewhere else".
  printf '%s\n' "$collect" | grep -qF "neither the note's owning"
  printf '%s\n' "$collect" | grep -qF 'nor the dev-bot checkout'
}

@test "vault notes keep the commit_memory and gitignore gates" {
  local gate
  gate="$(subsection_flat "$SKILL" '2. Apply the tracking gate')"
  printf '%s\n' "$gate" | grep -qF 'effective `commit_memory` is'
  printf '%s\n' "$gate" | grep -qF 'project-first, global-fallback'
  printf '%s\n' "$gate" | grep -qF 'git -C <root> check-ignore <path>'
  # The inverted exit convention is stated, including the error code.
  printf '%s\n' "$gate" | grep -qF 'exits 0 when the path **is** ignored'
  printf '%s\n' "$gate" | grep -qF '128 on error'
}

@test "global lessons are published regardless of a project's commit_memory" {
  local gate
  gate="$(subsection_flat "$SKILL" '2. Apply the tracking gate')"
  printf '%s\n' "$gate" | grep -qF 'Global-store notes'
  printf '%s\n' "$gate" | grep -qF 'always published'
  printf '%s\n' "$gate" | grep -qF 'whatever a project'
}

@test "the branch is built in a temporary worktree, never the main checkout" {
  local prepare cleanup
  prepare="$(subsection_flat "$SKILL" '4. Prepare the branch')"
  cleanup="$(subsection_flat "$SKILL" '7. Clean up and report')"
  printf '%s\n' "$prepare" | grep -qF 'never switch its checked-out branch'
  printf '%s\n' "$prepare" | grep -qF 'temporary linked worktree'
  printf '%s\n' "$prepare" | grep -qF 'git -C "$root" worktree add'
  printf '%s\n' "$prepare" | grep -qF 'origin/$default'
  printf '%s\n' "$cleanup" | grep -qF 'worktree remove "$wt"'
}

@test "a standing branch gets a fresh detached worktree, never another session's" {
  local prepare
  prepare="$(subsection_flat "$SKILL" '4. Prepare the branch')"
  printf '%s\n' "$prepare" | grep -qF 'fetch the branch into its remote-tracking ref'
  printf '%s\n' "$prepare" | grep -qF "Never reuse another session's worktree"
  printf '%s\n' "$prepare" | grep -qF 'dirty or staged changes'
  printf '%s\n' "$prepare" | grep -qF 'worktree add --detach'
  printf '%s\n' "$prepare" | grep -qF 'fresh detached one is safe'
  # A reaped temp path is pruned, not reused.
  printf '%s\n' "$prepare" | grep -qF 'worktree prune'
  printf '%s\n' "$prepare" | grep -qF 'never reuse a vanished path'
}

@test "the new branch is unique per stream and session" {
  local prepare
  prepare="$(subsection_flat "$SKILL" '4. Prepare the branch')"
  printf '%s\n' "$prepare" | grep -qF 'chore/commit-memories-<YYYYMMDD-HHMMSS>-<pid>'
  printf '%s\n' "$prepare" | grep -qF 'chore/global-memories-<YYYYMMDD-HHMMSS>-<pid>'
  printf '%s\n' "$prepare" | grep -qF "shell's"
  printf '%s\n' "$prepare" | grep -qF 'retry with a fresh nonce'
}

@test "the capture's files are checked, copied and committed explicitly" {
  local commit
  commit="$(subsection_flat "$SKILL" '5. Commit the notes')"
  printf '%s\n' "$commit" | grep -qF 'check-ignore'
  printf '%s\n' "$commit" | grep -qF 'Before copying anything'
  printf '%s\n' "$commit" | grep -qF 'global-store** path that is ignored is a defect'
  printf '%s\n' "$commit" | grep -qF 'never force-add it'
  printf '%s\n' "$commit" | grep -qF 'global note uses its `storage/global-memories/...` target'
  printf '%s\n' "$commit" | grep -qF 'stage the exact paths'
  printf '%s\n' "$commit" | grep -qF 'never a blanket add'
  printf '%s\n' "$commit" | grep -qF 'Nothing staged means nothing to publish'
  printf '%s\n' "$commit" | grep -qF 'never fixups'
}

@test "the agent pushes a branch and never the default branch" {
  local publish
  publish="$(subsection_flat "$SKILL" '6. Publish')"
  printf '%s\n' "$publish" | grep -qF 'push -u origin "$branch"'
  printf '%s\n' "$publish" | grep -qF 'never push the default branch'
  printf '%s\n' "$publish" | grep -qF 'never force-push'
  printf '%s\n' "$publish" | grep -qF 'Never merge'
  local forbidden
  forbidden="$(section_flat "$SKILL" 'MUST NOT')"
  printf '%s\n' "$forbidden" | grep -qF 'push the default branch'
}

@test "a failed push keeps the commit and is reported, never hidden" {
  local publish
  publish="$(subsection_flat "$SKILL" '6. Publish')"
  printf '%s\n' "$publish" | grep -qF 'A push that fails leaves the commit in the worktree'
  printf '%s\n' "$publish" | grep -qF 'chore/commit-memories-recovered'
  printf '%s\n' "$publish" | grep -qF 'open no pull request'
  grep -qF 'Report every pull request URL' "$FLAT"
}

@test "publishing writes no memory notes" {
  local forbidden
  forbidden="$(section_flat "$SKILL" 'MUST NOT')"
  printf '%s\n' "$forbidden" | grep -qF 'Write memory notes'
  printf '%s\n' "$forbidden" | grep -qF 'the capture is the only writer'
}

@test "the finish-flow PR gate names the memory publisher as an exception" {
  grep -qF 'Finish-flow publishers' "$GH_CREATE_PR_FLAT"
  grep -qF 'devbot:commit-memories' "$GH_CREATE_PR_FLAT"
  grep -qF 'devbot:improve-reviewing' "$GH_CREATE_PR_FLAT"
  grep -qF 'the approval and local-review gates below do not apply' "$GH_CREATE_PR_FLAT"
}

@test "the workflow owner exempts the finish-flow publishers from the trunk rule" {
  grep -qF 'The finish flow publishes' "$SOFTWARE_DEV_FLAT"
  grep -qF 'devbot:commit-memories' "$SOFTWARE_DEV_FLAT"
  grep -qF 'whatever the workflow' "$SOFTWARE_DEV_FLAT"
  grep -qF "trunk workflow's" "$SOFTWARE_DEV_FLAT"
}

@test "the configuration docs say the vault is published, not committed silently" {
  grep -qF 'published on the project' "$CONFIG_DOCS"
  grep -qF 'chore(agents): commit memories and lessons learned' "$CONFIG_DOCS"
}

@test "the worktree policy states that memory has its own branch and pull request" {
  grep -qF 'temporary linked worktree' "$WORKTREES_FLAT"
  grep -qF 'memory branch' "$WORKTREES_FLAT"
  grep -qF "carries only its work commits" "$WORKTREES_FLAT"
  grep -qF 'Never put vault commits on a task branch' "$WORKTREES_FLAT"
}

@test "memory-management points tracked notes at the memory pull request" {
  grep -qF 'standing memory pull request' "$MEMORY_MGMT_FLAT"
  grep -qF 'never fixups and never on the default branch' "$MEMORY_MGMT_FLAT"
}
