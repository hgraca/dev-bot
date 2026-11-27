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
- `devbot:auto-dev`, `devbot:gh-create-pr` or `devbot:full-review-loop` reaches the remote review step.
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

Drive the wait with `pr-watch` — `devbot tool pr-watch <pr>` runs the CLI the `devbot-tools` MCP
server exposes under the same name. It takes whatever the loop was given — a number, `#number`,
`owner/repo#number` or a PR URL — polls the reviews and the required checks, prints one digest, and
answers with its exit code:

| Exit | Meaning                                  | What the loop does                    |
| ---- | ---------------------------------------- | ------------------------------------- |
| `5`  | a review arrived **with findings**       | [Read](#read) it, then fix and answer |
| `0`  | a review arrived with nothing to address | [Gate](#gate) — the round is clean    |
| `3`  | a **required** check failed              | a failing check: see [Gate](#gate)    |
| `4`  | the timeout expired with no review       | re-run once longer, then ask the user |
| `1`  | a runtime failure from `gh`              | report it — never read as a timeout   |
| `2`  | the arguments were wrong                 | fix the call; the wait never started  |

```bash
devbot tool pr-watch <pr> --no-request --timeout 900 --interval 60
```

`--no-request` because [Request](#request) already queued it; drop the flag to have the tool request
and wait in one call. Never hand-roll a `sleep` loop, a `gh run watch` or a `gh pr checks` poll for
this: the tool exists so the answer is an exit code rather than a digest someone has to read. It
fails fast on a required check — reported on the poll that sees it, within one `--interval`, with the
check named.

Run it as a background job (`background: true`, or a `notifyOnExit` PTY on opencode v1) when the wait
should outlive the turn: end that turn on `[WAITING_FOR_PTY]`, and the job's exit notification wakes
you to read the digest and take the branch it reports.

`0` still covers every shape a clean round takes — an approval, a review that reports no open issues, or a bare acknowledgement — and `3` comes only from the required set, so an optional red check never stops a loop the merge gate would allow. `5` is a change request, line comments on the review, or a body that does not claim "no open issues": Copilot writes a body every time, approvals included, so the body alone is not a finding. [Read](#read) still reads both the body and the threads — that is where the findings live, and the exit code is only how their arrival is detected.

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

A review that introduces no new findings is not a mergeable pull request. Ask the tool for the merge
gate in one call — it already ignores the fixup guard and needs no `jq`:

```bash
devbot tool pr-watch <pr> --repo <owner>/<repo> --until green --timeout 900
```

| Exit | Meaning                                                              | What to do                            |
| ---- | -------------------------------------------------------------------- | ------------------------------------- |
| `6`  | every required check is green **and** the pull request is mergeable  | [Finish](#finish)                     |
| `3`  | a required check failed — the digest names it                        | fix it as its own fixup! commit, push |
| `4`  | a check is still pending, or GitHub has not computed the merge state | re-run once longer, then ask the user |
| `1`  | `gh` failed                                                          | report it, never read as a timeout    |

`--until green` requests no review and reads none: it is the second leg of the loop, not a substitute
for [Wait](#wait). A failed check returns `3` on the poll that sees it, so a red run does not wait out
the timeout. Its digest names the `merge state`, so a timeout says which leg was short.

`6` is the checks and the branch's readiness, not the approval: a missing required approval, an
unresolved thread or a change request leaves the merge state `BLOCKED`, which is the human's gate and
does not hold this wait back. A draft, a conflict, a stale base (`BEHIND`) or an uncomputed merge
state does.

`6` is also a claim about the **declared** gate, not about what happens to be running:
`gh pr checks --required` lists only contexts that already exist, so a required check still queued
would read as green. The tool reads the branch protection and the repository rulesets instead and waits for every
declared context to report. An **organisation** ruleset is not read — listing one needs an `admin:org`
token, which the session does not carry — so a check required only there is invisible until it reports;
that is the edge of what this gate can prove, and the reason to read [Gate](#gate) yourself on a repo
whose rules live at the organisation. A pull request with no declared check, or one whose declaration
cannot be read, never reports `6` — a vacuous gate is not evidence — so that wait runs out and the
merge state is the thing to read.

When the gate is not the whole story — the tool is not the place to diagnose a conflict or a stale
base — inspect it once, never in a polling loop:

```bash
# Every required check, with the fixup guard's name left in — a one-shot read.
gh pr checks <pr> --repo <owner>/<repo> --required --json name,bucket \
  --jq '[.[] | select(.name | test("fixup"; "i") | not)
         | select(.bucket != "pass" and .bucket != "skipping")] | length == 0'

# The pull request's own merge state — green checks alone do not make it mergeable.
gh pr view <pr> --repo <owner>/<repo> --json mergeable,mergeStateStatus
```

- **Pending** — a `pending` bucket, or `mergeable: UNKNOWN` while GitHub computes it, is not a pass;
  `--until green` keeps waiting on it and answers `4` when its timeout expires.
- **Failing** — fix every failing check as its own fixup! commit (`devbot:git-fixup-commits`), push, then
  return to [Request](#request). Green checks against a stale review are not the finish line: the push
  needs a fresh Copilot review, so repeat until a review introduces no new findings **and** every
  required check passes.
- **`BEHIND`** — on a ruleset that requires the branch to be current, update it (`gh pr update-branch`)
  and re-enter the wait; the update re-runs the checks.
- **`CONFLICTING` / `DIRTY`** — stop and ask the user. A conflict is resolved by rewriting the branch,
  not by a fixup.
- **A fixup guard is not a failure** — any required check whose name contains `fixup` (in any
  case) stays red until the squash, by design, and is excluded from the gate. It must be green on the
  squashed branch before the merge: the push that publishes the squash re-runs it. A required job that
  merely _runs_ the guard — `test` on this repository — is red for the same reason and is not excluded by
  name, so that gate is read once on the squashed branch, after the push.

### Finish

Once [Gate](#gate) is green, `devbot:review-loop`'s Finish applies: squash the fixups into their
targets (`devbot:git-fixup-commits`, step 7 owns the lease and the exact command) and hand the user
the force-push. GitHub-specific: the squash rewrites commits without changing the tree, so the push
re-runs the checks green. Never merge.
