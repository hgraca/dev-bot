---
name: devbot:gh-review-loop
description: Loop Copilot pull-request reviews — request, wait, fix each finding as a fixup, push, re-request — until a review introduces no new findings. Use when running the review loop for a PR.
---

# GH Review Loop

The Copilot pull-request review loop, end to end: request a review, wait for it to land, read every
finding, fix each as a fixup, push, re-request, and repeat until a review introduces no new findings.
Finish by squashing the fixups and handing the user the force-push command — never merge.

`devbot:auto-dev` and the `devbot:gh-review-loop` command both drive this skill; an interactive
session uses it too, pausing at its own check-ins. `devbot:address-review` defers to it for the
posting/reply mechanics, which are the deliberate exception to its local-only rule.

## When to Apply

- Working a pull request's Copilot review to a clean state.
- `devbot:auto-dev` reaches the review step.
- The user asks to run the review loop, address Copilot's comments, or "iterate until Copilot is
  happy".

## MUST

- **Request after the PR exists.** A rejected reviewer on `gh pr create` aborts the whole creation,
  leaving no PR to repair.
- **Verify, never trust an exit code.** `gh pr edit` and `gh api graphql` both exit 0 with no review
  queued.
- **Poll at the documented cadence** — 1 minute, then every minute, at most 60 checks per request.
- **Fix every finding as a `fixup!`** (`devbot:git-fixup-commits`), one commit per finding.
- **Reply and resolve** every thread, including a false positive — with the same succinct format.
- **Stop one step before the merge**: squash the fixups, hand the user the force-push command.

## The loop

Run the steps in order until a review introduces no new findings.

### Request

Record a timeline cursor **before** requesting:

```bash
since="$(gh api repos/<owner>/<repo>/issues/<pr>/timeline --paginate \
  --jq '[.[] | select(.event == "review_requested" or .event == "copilot_work_started") | .id] | max // 0' \
  | sort -n | tail -1)"
```

Then request Copilot — a bare `copilot` is not a reviewer, and `--reviewer` must never go on
`gh pr create`:

```bash
gh pr edit <pr> --add-reviewer @copilot
```

The request is dropped silently often enough that verification is part of the request, not a
separate concern — see [Verify](#verify). Re-request explicitly after each push; Copilot does not
re-review on its own. Skip the request while a review is still pending, and do not ask for one you
have already read.

### Verify

Fetch the timeline again and require a `review_requested` whose `requested_reviewer.login` is
`Copilot`, or a `copilot_work_started`, with an `id` greater than `$since` — anything at or below it
belongs to an earlier round, and a human's request is not Copilot's. `--paginate` runs `--jq` per
page, so the per-page maxima are reduced here with `sort -n` and `tail -1`:

```bash
check="$(gh api --paginate repos/<owner>/<repo>/issues/<pr>/timeline \
  --jq '.[]
    | select((.event == "review_requested" and .requested_reviewer.login == "Copilot")
             or .event == "copilot_work_started")
    | [.id, .event] | @tsv' \
  | sort -n | tail -1)"
id="${check%%$'\t'*}"

# Registered only when the newest Copilot event is newer than the cursor.
[ "${id:-0}" -gt "${since:-0}" ]
```

When that test fails, re-record `since` before retrying, then fall back to the GraphQL request.
Resolve both ids — a new PR has no prior Copilot review to read the bot id from:

```bash
BOT="$(gh api '/users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id)"
PR="$(gh pr view <pr> --json id --jq .id)"
gh api graphql -f query='mutation($pr:ID!,$bot:ID!){ requestReviews(input:{pullRequestId:$pr,botIds:[$bot]}) { pullRequest { id } } }' \
  -f pr="$PR" -f bot="$BOT"
```

Then check the timeline again. Never report a re-request on a zero exit code alone.

### Lite effort

Neither the CLI nor the API sets the review effort. A request inherits the PR's previous effort,
then your personal Copilot setting, then the repository and organization defaults, then the built-in
default (Balanced). Select Lite before requesting and re-select it for every request. Copilot records
the level in its review body (`**Review effort:**`); if it reports anything else, ask the user to set
Lite and re-request before addressing the findings.

### Wait

1 minute after each request before the first check. If the review has not landed, re-check every
1 minute, for a maximum of 60 checks per request (the first check counts). Then stop and ask the user
for instructions. Use a `sleep` PTY with `notifyOnExit` rather than blocking on polling.

### Read

Fetch all pages (`gh api --paginate`). Select the new review by `submitted_at`, then its bot-authored
comments by `pull_request_review_id` — `/comments` has `created_at`, not `submitted_at`. Read **both**
the line comments (`.../pulls/<pr>/comments`) and the review body (`.../pulls/<pr>/reviews`);
findings live in each.

### Checkout

Confirm the checkout is the PR's head branch before editing: an explicit `--head` may differ from the
checked-out branch. Work in a clean checkout or worktree of that branch and push explicitly to it.

### Fix

Address every finding as per your own recommendation, commit each as a `fixup!`
(`devbot:git-fixup-commits`), and push.

### Mark

Reply with a succinct resolution comment, then resolve the thread. The reply is one to three bullet
points only, each line at most 72 characters (the whole line, including its `- ` marker), with no
prose around them. A false positive gets the same format, explaining why no change was made. A
finding that exists only as a review-body row has no thread: post its resolution as a PR comment in
the same format. This posting is the deliberate exception to `devbot:address-review`'s local-only
rule.

### Track

Follow the underlying issue and affected code across both sources, keeping comment IDs for the
replies and resolutions. A re-raised finding already addressed or judged a false positive does not
restart the loop.

### Finish

When a review introduces no new findings, squash the fixups into their target commits
(`devbot:git-worktrees`, "Squash fixups before merge") and hand the user the exact
`git push --force-with-lease=<ref>:<expected-sha>` command. The guards module blocks the agent's
force-push; the human publishes it. Never merge.
