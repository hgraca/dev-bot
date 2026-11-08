---
name: devbot:auto-dev
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
   doing anything else. A Jira issue key or URL (`PROJ-123`,
   `https://<site>.atlassian.net/browse/PROJ-123`) is this run's ticket, not a search target —
   resolve it with `devbot:jira-workflow`.

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
   and the review loop keep their own instructions to ask. Every Jira decision that needs a human —
   resolving or creating the ticket, its project, its epic, an epic's `Stream` — is made inside this
   pause; `devbot:jira-workflow` carries the steps.

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

5. **Work the steps to the last one before the merge** — entering BUILD, run `devbot:jira-workflow`'s
   pre-implementation step: append the restate's insights to the ticket description and move the
   ticket to DOING or its equivalent. Then carry the task to the workflow's final hand-back, which is the stage just before merging to the default branch: for the worktrees
   workflow, an open pull request whose review loop is clean and whose required checks are green; for
   the trunk workflow, the reviewed commits with the push still pending. Never merge a pull request,
   never push the default branch, and never open a pull request the workflow does not call for.

6. **Hand back** — stop and report what the workflow's last step leaves for the user; a pull request
   is always reported with its URL (`devbot:gh-create-pr`).

## Review loop (when the workflow opens a pull request)

The loop is `devbot:gh-review-loop`: load that skill and run it until a review introduces no new
findings and the pull request's required checks are green and it is mergeable. It carries the
request/verify mechanics, the wait cadence, the read/fix/mark/track steps and the CI gate; an
interactive run uses the same skill, pausing at its own check-ins. Finish where it says — squash the
fixups and hand the user the force-push command. Never merge.
