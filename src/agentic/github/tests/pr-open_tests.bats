#!/usr/bin/env bats
# =============================================================================
# src/agentic/github/tests/pr-open_tests.bats
# Guards the one-call contract: push, create, assign, request; nothing repeats
# when the PR or the assignment already exists; a failed assignment or review is
# reported without losing the PR; and a bad body file stops before the remote.
# The --type modes guard the standing pull requests the finish flow publishes:
# a fixed title and repository per stream, no review request, and no twin.
# git and gh are stubbed, so no repository and no network are needed.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    MODULE_DIR="$(cd "$TEST_DIR/.." && pwd)"
    TOOL="$MODULE_DIR/tools/pr-open.mcp.sh"

    STUBS="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$STUBS"
    CALLS="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS"

    cat >"$STUBS/git" <<GITSTUB
#!/usr/bin/env bash
echo "git \$*" >>"$CALLS"
case "\$*" in
  "branch --show-current") [ "\${DETACHED:-}" = "1" ] || echo "feat/x" ;;
  "rev-parse HEAD") echo "\${HEAD_SHA:-aaa111}" ;;
  "rev-parse --verify --quiet "*)
      [ "\${UP_TO_DATE:-}" = "1" ] && echo "\${HEAD_SHA:-aaa111}" || exit 1 ;;
  "remote get-url "*"--push"*) echo "\${PUSH_URL:-\${REMOTE_URL:-git@github.com:GET-E/dev-bot.git}}" ;;
  "remote get-url "*) echo "\${REMOTE_URL:-git@github.com:GET-E/dev-bot.git}" ;;
  *) exit 0 ;;
esac
GITSTUB

    cat >"$STUBS/gh" <<GHSTUB
#!/usr/bin/env bash
echo "gh \$*" >>"$CALLS"
case "\$*" in
  "pr list"*"select(.title"*)
      # gh lists only the fields --json names, so the field set is pinned here.
      joined="\$*"; fields="\${joined#*--json }"; fields="\${fields%% *}"
      case ",\$fields," in
        *,title,*) ;;
        *) echo "unknown JSON field: title" >&2; exit 1 ;;
      esac
      [ -n "\${STANDING:-}" ] && printf '%s\n' "\$STANDING"
      [ -f "@CREATED@" ] && [ -n "\${TWIN:-}" ] && printf '%s\n' "\$TWIN"
      exit 0
      ;;
  "pr list"*)
      if [ "\${PR_OPEN:-0}" = "1" ]; then
          printf '%s\t%s\t%s\n' "\${PR_NUMBER:-42}" "\${PR_TITLE:-feat(x): a thing}" "\${PR_URL:-https://example/pr/42}"
      fi
      [ -n "\${PR_EXTRA:-}" ] && printf '%s\n' "\$PR_EXTRA"
      exit 0
      ;;
  "pr create"*)
      touch "@CREATED@"
      echo "https://example/pr/42"
      ;;
  "pr view"*"--json number"*) echo "42" ;;
  "pr view"*"--json commits"*) echo "2025-12-31T00:00:00Z" ;;
  "pr view"*"--json id"*) echo "PR_NODE_ID" ;;
  "pr view"*"--json assignees"*) [ -n "\${ASSIGNED:-}" ] && echo "\${ASSIGNED}" ;;
  "pr edit"*)
      [ -n "\${ASSIGN_FAIL:-}" ] && { echo "boom" >&2; exit 1; }
      exit 0
      ;;
  "repo view"*"--json nameWithOwner"*)
      if [ -f ./.stub-slug ]; then cat ./.stub-slug; else echo "\${REPO_SLUG:-GET-E/dev-bot}"; fi
      ;;
  "repo view"*"--json url"*)
      slug=""
      for arg in "\$@"; do
          case "\$arg" in repo|view|-*|.*) continue ;; esac
          [ -z "\$slug" ] && slug="\$arg"
      done
      echo "https://github.com/\${slug:-\${REPO_SLUG:-GET-E/dev-bot}}"
      ;;
  "repo view"*"--json defaultBranchRef"*) echo "\${DEFAULT_BRANCH:-main}" ;;
  "repo view"*) echo "GET-E/dev-bot" ;;
  "api user --jq .login") echo "octocat" ;;
  "api users/"*) echo "BOT_NODE_ID" ;;
  "api --paginate"*"timeline"*)
      [ -n "\${REVIEW_NEVER:-}" ] && exit 0
      [ -f "@MARKER@" ] && echo "2026-01-01T00:00:00Z" ;;
  "api graphql"*)
      touch "@MARKER@"
      echo '{"data":{"requestReviews":{"clientMutationId":null}}}'
      ;;
  *) exit 0 ;;
esac
GHSTUB

    chmod +x "$STUBS/git" "$STUBS/gh"
    sed -i "s|@MARKER@|$BATS_TEST_TMPDIR/requested|g" "$STUBS/gh"
    sed -i "s|@CREATED@|$BATS_TEST_TMPDIR/created|g" "$STUBS/gh"
    export PATH="$STUBS:$PATH"

    BODY="$BATS_TEST_TMPDIR/body.md"
    printf 'A body.\n' >"$BODY"
}

# A dev-bot checkout whose repository slug the stub reports for that directory.
make_dev_bot_root() {
    export DEV_BOT_ROOT="$BATS_TEST_TMPDIR/devbot"
    mkdir -p "$DEV_BOT_ROOT/.git"
    printf '%s\n' "${1:-GET-E/dev-bot}" >"$DEV_BOT_ROOT/.stub-slug"
}

@test "mcp-meta describes the tool" {
    run bash "$TOOL" mcp-meta
    assert_success
    assert_output --partial '"name":"pr-open"'
    assert_output --partial 'request the Copilot review'
    assert_output --partial '--assignee <login>'
    assert_output --partial '--type <review-improvement|global-memories|proj-memories>'
}

@test "it pushes, opens and requests the review" {
    run bash "$TOOL" --title "feat(x): a thing" --body-file "$BODY"
    assert_success
    assert_output --partial '"pr": "opened"'
    assert_output --partial 'https://example/pr/42'
    assert_output --partial '"review": "requested"'
    run cat "$CALLS"
    assert_output --partial "git push -u origin feat/x"
    assert_output --partial "gh pr create"
}

@test "an already open PR is reused, not recreated" {
    export PR_OPEN=1
    run bash "$TOOL" --title "feat(x): a thing" --body-file "$BODY"
    assert_success
    assert_output --partial '"pr": "already open"'
    run cat "$CALLS"
    refute_output --partial "gh pr create"
}

@test "--no-review skips the request" {
    run bash "$TOOL" --title "t" --body-file "$BODY" --no-review
    assert_success
    assert_output --partial '"review": "skipped"'
    run cat "$CALLS"
    refute_output --partial "requested_reviewers"
}

@test "no --assignee leaves the PR unassigned" {
    run bash "$TOOL" --title "t" --body-file "$BODY" --no-review
    assert_success
    assert_output --partial '"assignee": "skipped"'
    run cat "$CALLS"
    refute_output --partial "pr edit"
}

@test "it assigns after creating and before requesting the review" {
    run bash "$TOOL" --title "t" --body-file "$BODY" --assignee @me
    assert_success
    assert_output --partial '"assignee": "assigned"'
    run cat "$CALLS"
    assert_output --partial "gh pr edit https://example/pr/42 --add-assignee @me"
    create_line="$(grep -n 'gh pr create' "$CALLS" | head -1 | cut -d: -f1)"
    assign_line="$(grep -n 'gh pr edit' "$CALLS" | head -1 | cut -d: -f1)"
    review_line="$(grep -n 'api graphql' "$CALLS" | head -1 | cut -d: -f1)"
    [ "$create_line" -lt "$assign_line" ]
    [ "$assign_line" -lt "$review_line" ]
}

@test "an assignee already on the PR is not added twice" {
    export ASSIGNED=octocat
    run bash "$TOOL" --title "t" --body-file "$BODY" --assignee @me --no-review
    assert_success
    assert_output --partial '"assignee": "already assigned"'
    run cat "$CALLS"
    refute_output --partial "pr edit"
}

@test "an assignee that fails still leaves the PR, reported at the end" {
    export ASSIGN_FAIL=1
    run bash "$TOOL" --title "t" --body-file "$BODY" --assignee @me
    assert_equal "$status" 1
    assert_output --partial 'https://example/pr/42'
    assert_output --partial '"assignee": "failed (boom)"'
    assert_output --partial "the assignee was not added"
    run cat "$CALLS"
    assert_output --partial "api graphql"
}

@test "a failed assignee and a failed review are both reported" {
    export ASSIGN_FAIL=1 REVIEW_NEVER=1
    run bash "$TOOL" --title "t" --body-file "$BODY" --assignee @me
    assert_equal "$status" 1
    assert_output --partial 'https://example/pr/42'
    assert_output --partial '"assignee": "failed (boom)"'
    assert_output --partial '"review": "not queued"'
    assert_output --partial "the assignee was not added"
    assert_output --partial "the Copilot review did not register"
    [ "$(printf '%s\n' "$output" | grep -c '^ERROR:')" -eq 2 ]
}

@test "an empty body file is refused before anything is pushed" {
    : >"$BATS_TEST_TMPDIR/empty.md"
    run bash "$TOOL" --title "t" --body-file "$BATS_TEST_TMPDIR/empty.md"
    assert_equal "$status" 2
    assert_output --partial "body file is empty"
    [ ! -s "$CALLS" ]
}

@test "a review request that does not register exits 1 but still prints the URL" {
    export REVIEW_NEVER=1
    run bash "$TOOL" --title "t" --body-file "$BODY"
    assert_equal "$status" 1
    assert_output --partial 'https://example/pr/42'
    assert_output --partial "did not register"
}

# ── --type: the finish flow's standing pull requests ─────────────────────────

@test "--type proj-memories opens the vault PR against the project with its fixed title" {
    make_dev_bot_root
    export REPO_SLUG="GET-E/consumer"
    export REMOTE_URL="git@github.com:GET-E/consumer.git"

    run bash "$TOOL" --type proj-memories --cwd "$BATS_TEST_TMPDIR"
    assert_success
    assert_output --partial '"type": "proj-memories"'
    assert_output --partial '"repo": "GET-E/consumer"'
    assert_output --partial '"pr": "opened"'
    assert_output --partial '"review": "skipped"'
    run cat "$CALLS"
    assert_output --partial "git push -u origin feat/x"
    assert_output --partial "gh pr create"
    assert_output --partial "--title chore(agents): commit memories and lessons learned"
    assert_output --partial "--repo GET-E/consumer"
    assert_output --partial "--head feat/x"
    assert_output --partial "session memories stay on a local branch no one reviews"
    refute_output --partial "api graphql"
}

@test "--type global-memories opens against the dev-bot repository" {
    make_dev_bot_root GET-E/dev-bot
    export REMOTE_URL="git@github.com:GET-E/dev-bot.git"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_success
    assert_output --partial '"repo": "GET-E/dev-bot"'
    run cat "$CALLS"
    assert_output --partial "--title chore(global-memories): commit global memories and lessons learned"
    assert_output --partial "global lessons accumulate untracked in the toolkit"
}

@test "--type accepts a body file over its standing body" {
    make_dev_bot_root
    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR" --body-file "$BODY"
    assert_success
    run cat "$CALLS"
    assert_output --partial "--body-file $BODY"
    refute_output --partial "global lessons accumulate"
}

@test "--type review-improvement demands a body file and never requests a review" {
    make_dev_bot_root
    run bash "$TOOL" --type review-improvement --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 2
    assert_output --partial "needs --body-file"
    [ ! -s "$CALLS" ]

    run bash "$TOOL" --type review-improvement --cwd "$BATS_TEST_TMPDIR" --body-file "$BODY"
    assert_success
    run cat "$CALLS"
    assert_output --partial "--title chore(improve-reviews): improve review skill"
    refute_output --partial "api graphql"
}

@test "--type refuses a push remote that is not the pull request's repository" {
    make_dev_bot_root GET-E/dev-bot
    export REMOTE_URL="git@github.com:GET-E/consumer.git"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 1
    assert_output --partial "get-e/consumer"
    assert_output --partial "get-e/dev-bot"
    run cat "$CALLS"
    refute_output --partial "git push"
    refute_output --partial "gh pr create"
}

@test "--type creates against an explicit --repo the remote matches" {
    make_dev_bot_root
    export REMOTE_URL="git@github.com:GET-E/other.git"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR" --repo GET-E/other
    assert_success
    run cat "$CALLS"
    assert_output --partial "--repo GET-E/other"
}

@test "--type appends to the standing pull request already on this branch" {
    make_dev_bot_root
    export PR_OPEN=1
    export PR_TITLE="chore(global-memories): commit global memories and lessons learned"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_success
    assert_output --partial '"pr": "appended"'
    run cat "$CALLS"
    assert_output --partial "git push -u origin feat/x"
    refute_output --partial "gh pr create"
}

@test "--type refuses a standing pull request that sits on another branch" {
    make_dev_bot_root
    export STANDING="$(printf '7\tchore/global-memories-1\thttps://example/pr/7')"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 1
    assert_output --partial "chore/global-memories-1"
    assert_output --partial "https://example/pr/7"
    run cat "$CALLS"
    refute_output --partial "gh pr create"
}

@test "--type refuses two standing pull requests rather than picking one" {
    make_dev_bot_root
    export STANDING="$(printf '7\tchore/a\thttps://example/pr/7\n8\tchore/b\thttps://example/pr/8')"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 1
    assert_output --partial "https://example/pr/7"
    assert_output --partial "https://example/pr/8"
    run cat "$CALLS"
    refute_output --partial "gh pr create"
}

@test "--type refuses a branch that already heads a different pull request" {
    make_dev_bot_root
    export PR_OPEN=1 PR_TITLE="feat(x): something else"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 1
    assert_output --partial "another purpose"
    run cat "$CALLS"
    refute_output --partial "git push"
    refute_output --partial "gh pr create"
}

@test "--type rejects a --title, an assignee and an unknown stream" {
    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR" --title "t"
    assert_equal "$status" 2
    assert_output --partial "carries its own title"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR" --assignee @me
    assert_equal "$status" 2
    assert_output --partial "assigned by hand"

    run bash "$TOOL" --type nonsense
    assert_equal "$status" 2
}

@test "--remote pushes to the named remote and is checked against the repo" {
    make_dev_bot_root GET-E/dev-bot
    export REMOTE_URL="git@github.com:GET-E/dev-bot.git"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR" --remote upstream
    assert_success
    assert_output --partial '"remote": "upstream"'
    run cat "$CALLS"
    assert_output --partial "git remote get-url --all --push upstream"
    assert_output --partial "git push -u upstream feat/x"
}

@test "--branch names the branch when the worktree is detached" {
    make_dev_bot_root
    export DETACHED=1

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR" --branch chore/global-memories-1
    assert_success
    assert_output --partial '"branch": "chore/global-memories-1"'
    run cat "$CALLS"
    assert_output --partial "git push origin HEAD:chore/global-memories-1"
    assert_output --partial "--head chore/global-memories-1"
}

@test "a detached head without --branch is a usage error" {
    export DETACHED=1
    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 2
    assert_output --partial "pass --branch"
    run cat "$CALLS"
    refute_output --partial "git push"
    refute_output --partial "gh pr create"
}

@test "--type needs the checkout it publishes from" {
    make_dev_bot_root
    run bash "$TOOL" --type global-memories
    assert_equal "$status" 2
    assert_output --partial "needs --cwd"
    run cat "$CALLS"
    refute_output --partial "git push"
}

@test "--type never publishes the default branch" {
    make_dev_bot_root
    export DEFAULT_BRANCH=feat/x

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 1
    assert_output --partial "default branch"
    run cat "$CALLS"
    refute_output --partial "git push"
    refute_output --partial "gh pr create"
}

@test "--type reports a twin another session created at the same moment" {
    make_dev_bot_root
    export TWIN="$(printf '9\tchore/global-memories-2\thttps://example/pr/9')"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_success
    assert_output --partial '"pr": "opened"'
    assert_output --partial "https://example/pr/9"
    assert_output --partial "a second standing pull request appeared"
}

@test "--type leaves the standing body alone when it appends" {
    make_dev_bot_root
    export PR_OPEN=1
    export PR_TITLE="chore(improve-reviews): improve review skill"

    run bash "$TOOL" --type review-improvement --body-file "$BODY" --cwd "$BATS_TEST_TMPDIR"
    assert_success
    assert_output --partial '"pr": "appended"'
    assert_output --partial '"body": "unchanged"'
    assert_output --partial "keeps its own body"
    run cat "$CALLS"
    refute_output --partial "pr edit"
}

@test "--type refuses when the dev-bot checkout cannot be resolved" {
    export DEV_BOT_ROOT="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$DEV_BOT_ROOT"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 1
    assert_output --partial "is not the dev-bot checkout"
    run cat "$CALLS"
    refute_output --partial "git push"
}

@test "--type resolves the dev-bot checkout from the tool when DEV_BOT_ROOT is unset" {
    unset DEV_BOT_ROOT
    local toolkit="$BATS_TEST_TMPDIR/toolkit"
    mkdir -p "$toolkit/src/agentic/github/tools" "$toolkit/.git"
    printf 'GET-E/dev-bot\n' >"$toolkit/.stub-slug"
    cp "$MODULE_DIR/tools/pr-open.py" "$toolkit/src/agentic/github/tools/"
    # A caller repo that is not dev-bot: the fallback would refuse this call.
    export REPO_SLUG="GET-E/consumer"
    export REMOTE_URL="git@github.com:GET-E/dev-bot.git"

    run python3 "$toolkit/src/agentic/github/tools/pr-open.py" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_success
    assert_output --partial '"repo": "GET-E/dev-bot"'
}

@test "--type refuses a draft standing pull request" {
    make_dev_bot_root
    run bash "$TOOL" --type global-memories --draft --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 2
    assert_output --partial "never a draft"
}

@test "the three standing titles match the skills that publish them" {
    local agentic
    agentic="$(cd "$MODULE_DIR/.." && pwd)"
    local title
    for title in \
        "chore(improve-reviews): improve review skill" \
        "chore(global-memories): commit global memories and lessons learned" \
        "chore(agents): commit memories and lessons learned"; do
        grep -qF -- "$title" "$MODULE_DIR/tools/pr-open.py"
        grep -qF -- "$title" "$agentic/github/skills/gh-create-pr/SKILL.md"
    done
    grep -qF -- "chore(improve-reviews): improve review skill" \
        "$agentic/self-improvement/skills/improve-reviewing/SKILL.md"
    grep -qF -- "chore(agents): commit memories and lessons learned" \
        "$agentic/memory/skills/commit-memories/SKILL.md"
    grep -qF -- "chore(global-memories): commit global memories and lessons learned" \
        "$agentic/memory/skills/commit-memories/SKILL.md"
}

@test "--type compares the remote's host, not just its owner and name" {
    make_dev_bot_root GET-E/dev-bot
    export REMOTE_URL="git@gitlab.com:GET-E/dev-bot.git"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 1
    assert_output --partial "gitlab.com"
    run cat "$CALLS"
    refute_output --partial "git push"
}

@test "--type validates the push URL, not the fetch URL" {
    make_dev_bot_root GET-E/dev-bot
    export REMOTE_URL="git@github.com:GET-E/dev-bot.git"
    export PUSH_URL="git@github.com:GET-E/elsewhere.git"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 1
    assert_output --partial "get-e/elsewhere"
    run cat "$CALLS"
    refute_output --partial "git push"
}

@test "--type refuses when the branch heads more than one open pull request" {
    make_dev_bot_root
    export PR_OPEN=1
    export PR_TITLE="chore(global-memories): commit global memories and lessons learned"
    export PR_EXTRA="$(printf '9\tchore(global-memories): commit global memories and lessons learned\thttps://example/pr/9')"

    run bash "$TOOL" --type global-memories --cwd "$BATS_TEST_TMPDIR"
    assert_equal "$status" 1
    assert_output --partial "open pull requests head"
    run cat "$CALLS"
    refute_output --partial "git push"
}

@test "--type resolves a relative body file against --cwd" {
    make_dev_bot_root
    cp "$BODY" "$BATS_TEST_TMPDIR/relative-body.md"

    run bash "$TOOL" --type global-memories --body-file relative-body.md --cwd "$BATS_TEST_TMPDIR"
    assert_success
    run cat "$CALLS"
    assert_output --partial "--body-file $BATS_TEST_TMPDIR/relative-body.md"
}
