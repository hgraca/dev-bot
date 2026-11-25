---
name: devbot:gh-review-loop
description: "Use when looping a GitHub Copilot review on a pull request. Triggers on 'Copilot review loop', 'address Copilot's comments', 'iterate until Copilot is happy'."
---

# GH Review Loop

The Copilot adapter for `devbot:review-loop`: the same request → await → read → fix → answer cycle,
with GitHub Copilot as the remote reviewer. This skill carries what is Copilot's and GitHub's; the
loop itself — convergence, the fixup discipline, the answer rule and the finish — is
`devbot:review-loop`'s and is not restated here.

`devbot:auto-dev` and the `devbot:gh-review-loop` command both drive this skill; an interactive
session uses it too, pausing at its own check-ins. `devbot:address-review` defers to it for the
posting/reply mechanics, which are the deliberate exception to its local-only rule.

## When to Apply

- Working a pull request's Copilot review to a clean state.
- `devbot:auto-dev`, `devbot:gh-create-pr` or `devbot:full-loop` reaches the remote review step.
- The user asks to run the Copilot review loop, address Copilot's comments, or "iterate until
  Copilot is happy".

## MUST

- **Request after the PR exists.** A rejected reviewer on `gh pr create` aborts the whole creation, leaving no PR to repair.
- **Verify, never trust an exit code.** `gh pr edit` and `gh api graphql` both exit 0 with no review queued.
- **Wait with one `pr-watch` call per review cycle**, not a hand-rolled loop; its exit code is the answer, and the codes are listed in [Wait](#wait).
- **Reply and resolve** every thread, including a false positive — with the same succinct format.
- **Gate on CI, not just the review.** Green required checks and a mergeable pull request come before
  the history is touched.

## The cycle

Run these steps in order for each round; the loop's control — when to re-enter and when it is
done — is `devbot:review-loop`'s, and so are `Fix` and its push. The push matters here: Copilot
re-reviews only a new tip, so a round's fixes are pushed before [Request](#request) is run again.

### Request

Record a timeline cursor **before** requesting:

```bash
since="$(gh api repos/<owner>/<repo>/issues/<pr>/timeline --paginate \
  --jq '[.[] | select(.event == "review_requested" or .event == "copilot_work_started") | .id] | max // 0' \
  | sort -n | tail -1)"
```

Then request Copilot **through the GraphQL mutation — it is the only path that registers a bot
reviewer**. `gh pr edit --add-reviewer @copilot` exits 0 while requesting nobody, and `--reviewer`
must never go on `gh pr create`:

```bash
bot_id="$(gh api 'users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id)"
pr_id="$(gh pr view <pr> --json id --jq .id)"
gh api graphql -f query='mutation($pr: ID!, $bot: ID!) { requestReviews(input: {pullRequestId: $pr, botIds: [$bot]}) { clientMutationId } }' \
  -f pr="$pr_id" -f bot="$bot_id"
sleep 1
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

When that test fails, the request was dropped — not declined. Re-record `since` in the cursor step,
run the same mutation again, and check the timeline again. Never report a re-request on a zero exit
code alone.

### Lite effort

Neither the CLI nor the API sets the review effort. A request inherits the PR's previous effort,
then your personal Copilot setting, then the repository and organization defaults, then the built-in
default (Balanced). Select Lite before requesting and re-select it for every request. Copilot records
the level in its review body (`**Review effort:**`); if it reports anything else, ask the user to set
Lite and re-request before addressing the findings.

### Wait

Drive the wait with `pr-watch` — the `devbot-tools` MCP server exposes it, and
`devbot tool pr-watch <pr>` runs the same script when a harness has not reloaded its tools since the
tool was installed. It takes whatever the loop was given — a number, `#number`, `owner/repo#number` or
a PR URL — polls the reviews and the required checks, prints one digest, and answers with its exit
code:

| Exit | Meaning                                    | What the loop does                    |
| ---- | ------------------------------------------ | ------------------------------------- |
| `0`  | a review arrived, or the decision is final | [Read](#read) it                      |
| `3`  | a **required** check failed                | a failing check: see [Gate](#gate)    |
| `4`  | the timeout expired with no review         | re-run once longer, then ask the user |
| `1`  | a runtime failure from `gh`                | report it — never read as a timeout   |
| `2`  | the arguments were wrong                   | fix the call; the wait never started  |

```bash
devbot tool pr-watch <pr> --no-request --timeout 900 --interval 60
```

`--no-request` because [Request](#request) already queued it; drop the flag to have the tool request
and wait in one call. Never hand-roll a `sleep` loop for this: the tool exists so the answer is an
exit code rather than a digest someone has to read.

`0` covers every shape a landed review takes — a body, an inline-only `COMMENTED` review, or a final
decision — and `3` comes only from the required set, so an optional red check never stops a loop the
merge gate would allow. [Read](#read) still reads both the body and the threads: that is where the
findings live, not how their arrival is detected.

### Read

Fetch all pages (`gh api --paginate`). Select the new review by `submitted_at`, then its bot-authored
comments by `pull_request_review_id` — `/comments` has `created_at`, not `submitted_at`.

A review carries findings in **two** places, and a clean thread list is not a clean review. Read both:

1. **Threads** — `/pulls/<pr>/comments` filtered to this review. Each is one finding, with a place to
   reply and resolve.
2. **The review body** — `/pulls/<pr>/reviews`. Beyond the summary prose it enumerates findings in
   collapsible `<details>` blocks headed `N open issues`, `N previously missed issues` (defects it
   found later, in code it had already read) and `N resolved since last review`. Extract every
   `<summary>` title with its file path and description: each is a finding with **no thread**, so it
   is verified, fixed and answered exactly like one — its resolution goes on the pull request.

Trust the body's own counts over the thread list. A round whose threads are all resolved but whose
body still reports open issues has not converged; the reviewer will simply raise them again on the
next push. Only `0 open issues` with no unaddressed `previously missed` entry closes the round.

### Checkout

Confirm the checkout is the PR's head branch before editing: an explicit `--head` may differ from the
checked-out branch. Work in a clean checkout or worktree of that branch and push explicitly to it.

### Mark

Reply with a succinct resolution comment, then resolve the thread. The reply is one to three bullet
points only, each line at most 72 characters (the whole line, including its `- ` marker), with no
prose around them. A false positive gets the same format, explaining why no change was made. A
finding that exists only as a review-body row has no thread: post its resolution as a PR comment in
the same format. This posting is the deliberate exception to `devbot:address-review`'s local-only
rule.

### Gate

A review that introduces no new findings is not a mergeable pull request. Before touching the history,
verify the remote gates; in a multi-remote checkout both commands need `--repo <owner>/<repo>`:

```bash
# Every required check must have finished green (pass, or skipped by design) —
# except a fixup guard, which rejects the very commits Finish is about to squash.
gh pr checks <pr> --repo <owner>/<repo> --required --json name,bucket \
  --jq '[.[] | select(.name != "no-fixup")
         | select(.bucket != "pass" and .bucket != "skipping")] | length == 0'

# The pull request's own merge state — green checks alone do not make it mergeable.
gh pr view <pr> --repo <owner>/<repo> --json mergeable,mergeStateStatus
```

- **Pending** — a `pending` bucket, or `mergeable: UNKNOWN` while GitHub computes it, is not a pass.
  Wait on the [Wait](#wait) cadence and check again; never block on a polling loop.
- **Failing** — fix every failing check as its own `fixup!` (`devbot:git-fixup-commits`), push, then
  return to [Request](#request). Green checks against a stale review are not the finish line: the push
  needs a fresh Copilot review, so repeat until a review introduces no new findings **and** every
  required check passes.
- **`BEHIND`** — on a ruleset that requires the branch to be current, update it (`gh pr update-branch`)
  and re-enter the wait; the update re-runs the checks.
- **`CONFLICTING` / `DIRTY`** — stop and ask the user. A conflict is resolved by rewriting the branch,
  not by a fixup.
- **A no-fixup guard is not a failure** — a required check that rejects `fixup!`/`squash!` subjects
  stays red until the squash, by design, and is excluded from the gate above. It must be green on the
  squashed branch before the merge: the push that publishes the squash re-runs it.

### Finish

Once [Gate](#gate) is green, `devbot:review-loop`'s Finish applies: squash the fixups into their
targets (`devbot:git-fixup-commits`, step 7 owns the lease and the exact command) and hand the user
the force-push. GitHub-specific: the squash rewrites commits without changing the tree, so the push
re-runs the checks green. Never merge.
