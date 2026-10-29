---
name: devbot:work-autonomously
description: Work a task autonomously to the last step before the merge — from a task given inline, a file path or a URL, resuming work already in progress.
---

Work the task below autonomously, end to end: refine it once up front when it needs it, then run
without stopping for input until the final hand-back.

Task: $ARGUMENTS

## Steps

1. **Resolve the task** — the argument is the task itself. An existing file path is read, a URL is
   fetched, and anything else is taken as the task in the user's own words. With no argument at all,
   the task is the assignment already in progress in this session — its todo list and the step it
   last reported — so continue it from where it stopped under this command's rules, without asking.
   Uncommitted changes corroborate that the assignment is the same one, never define it: changes you
   cannot attribute to this session's assignment mean stop and ask, and never adopt or discard them.
   Only when there is neither an argument nor an assignment in progress, ask for the task before
   doing anything else.

2. **Refine once, before any work** — this step is the run's DEFINE and fulfils the agent
   bootstrap's session-start interview; a run that skips it skips that interview with it. Refine
   when the task leaves the outcome open: more than one plausible reading of what to build, or no
   acceptance criteria derivable from the task and the files it concerns. A change to a public
   contract, the architecture or a data migration confirms the restate even when a spec exists,
   unless that spec already settles it. Skip it when any of these holds: the run is resuming work
   already in progress — an assignment in this session, or a task whose branch already carries
   commits or a pull request, which you check before asking; the task is already a written spec; or
   it is one unambiguous, well-scoped change. It is the run's only planned pause. Load the
   `grilling` and `interview-me` context skills, ask the frontier one batched round at a time until
   it is empty, then propose the restate — Outcome / User / Why now / Success / Constraint / Out
   of scope — and end the turn awaiting an explicit yes; silence is not confirmation, and with no
   human to answer, stop and report the blocker instead of guessing. The round takes `grilling`'s
   batched cadence over `interview-me`'s one-at-a-time one, and `interview-me`'s rule against
   non-interactive runs covers the autonomous phase that follows, not this round. The confirmed
   restate is the acceptance criteria the plan and the self-review are checked against, carried into
   the todo list when that list is created. Everything after it runs without asking; steps 1 and 3
   and the review loop keep their own instructions to ask.

3. **Load the workflow in use** — read the Workflows section of `devbot:software-development` and
   follow the workflow it selects for this run: an explicit instruction in this command wins, then
   the project's `workflow` configuration, then the default. In a `supervisor: true` session the
   configuration is the **owning project's**, never the supervisor's: derive the owner from the files
   the task concerns (`devbot tool project-for-path <path>`), and when the task names no file, take
   the owner from the task statement or ask before starting. Follow the selected workflow's steps as
   written; when the configuration names a workflow that does not exist, stop and ask. State the
   workflow and its owning project in one line before starting.

4. **Skip the check-ins** — the workflow mandates a check-in after every step. This run does not:
   after each step, continue straight into the next one. Stop only where step 2 or the workflow
   itself says to stop (no task, a closed pull request, uncommitted changes that are not this
   task's, a checkout off the default branch under the trunk workflow) or where a step's own
   instructions say to ask.

5. **Work the steps to the last one before the merge** — carry the task to the workflow's final
   hand-back, which is the stage just before merging to the default branch: for the worktrees
   workflow, an open pull request whose review loop is clean; for the trunk workflow, the reviewed
   commits with the push still pending. Never merge a pull request, never push the default branch,
   and never open a pull request the workflow does not call for.

6. **Hand back** — stop and report what the workflow's last step leaves for the user; a pull request
   is always reported with its URL (`devbot:gh-create-pr`).

## Review loop (when the workflow opens a pull request)

The Worktrees workflow's review loop is this one; an interactive run uses it too, pausing at the
check-ins. Run it until a review introduces no new findings.

- **Request** Copilot with the CLI's special reviewer value `@copilot` at creation, or
  `gh pr edit <pr> --add-reviewer @copilot`. A bare `copilot` is not a reviewer. If the CLI
  rejects it, request the bot directly: resolve
  `gh api '/users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id` and the PR node id,
  then call the GraphQL `requestReviews` mutation with `botIds`. Re-request explicitly after
  each push — Copilot does not re-review on its own — but skip the request while a review is
  still pending, and do not ask for one you have already read.
- **Lite effort** — neither the CLI nor the API sets it. A request inherits the PR's previous
  effort, then your personal Copilot setting, then the repository and organization defaults,
  then the built-in default (Balanced). Select Lite before requesting and re-select it for every
  request. Copilot records the level in its review body (`**Review effort:**`); if it reports
  anything else, ask the user to set Lite and re-request before addressing the findings.
- **Wait** — 1 minute after each request before the first check. If the review has not landed,
  re-check every 1 minute, for a maximum of 60 checks per request (the first check counts).
  Then stop and ask the user for instructions.
- **Read** — fetch all pages (`gh api --paginate`). Select the new review by `submitted_at`,
  then its bot-authored comments by `pull_request_review_id` — `/comments` has `created_at`, not
  `submitted_at`. Read **both** the line comments (`.../pulls/<pr>/comments`) and the review
  body (`.../pulls/<pr>/reviews`); findings live in each.
- **Checkout** — confirm the checkout is the PR's head branch before editing: an explicit
  `--head` may differ from the checked-out branch. Work in a clean checkout or worktree of that
  branch and push explicitly to it.
- **Fix** — address every finding as per your own recommendation, commit each as a `fixup!`
  (`devbot:git-fixup-commits`), and push.
- **Mark** — reply with what changed, then resolve the thread. A false positive gets a reply
  explaining why. A finding that exists only as a review-body row has no thread: record its
  resolution in a PR comment. This posting is the deliberate exception to
  `devbot:address-review`'s local-only rule.
- **Track** — follow the underlying issue and affected code across both sources, keeping comment
  IDs for the replies and resolutions. A re-raised finding already addressed or judged a false
  positive does not restart the loop.
