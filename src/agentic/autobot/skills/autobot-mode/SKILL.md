---
name: devbot:autobot-mode
description: Load in an AutoBot run — it works a Jira ticket unattended on a cron schedule, talking to its user over Slack.
---

# AutoBot mode

You are working a Jira ticket with nobody at the terminal. A cron tick starts you, you do what you
can, and you exit. Everything the user must know travels over Slack; everything you need from them
comes back the same way, one tick later.

The run follows `devbot:auto-dev` with two differences, both carried by this skill: the pauses are
answers you wait for over Slack, and progress is reported as it happens.

## You are unattended

Standard output and the log file are for diagnosis only — the user will never read them. If something
matters to them, it goes on Slack:

```bash
devbot autobot say "<message>"
```

Say it once. A message you do not send does not exist.

## You cannot block

There is no session alive between ticks, so waiting is impossible: a question ends the turn. That is
the whole mechanism —

1. post the question with `devbot autobot say`;
2. end the turn.

The scheduler parks the ticket, reminds the user hourly, and starts a fresh run when they answer,
with your question in the prompt. Never sleep, poll or wait in-process for a reply.

`devbot:auto-dev`'s refinement step says that with no human to answer you stop and report instead of
guessing. Here there _is_ a human, just not yet — park and ask, and let the answer arrive.

## The flow

Refinement and the plan are the only two pauses. Everything between them runs without asking.

1. **Refine** — exactly as `devbot:auto-dev` step 2: load `grilling` and `interview-me`, ask the
   frontier in batched rounds, one round per tick, then propose the restate. Skip it when the task is
   already unambiguous, as that step says. Post each round on Slack.
2. **Restate** — post the restate (Outcome / User / Why now / Success / Constraint / Out of scope) as
   a message that asks for a yes, and end the turn.
3. **Plan** — once confirmed, post the todo list with a one-line rationale per item, ask for approval,
   and end the turn.
4. **Work** — the approved list is your contract. Run it without stopping, reporting each item.
5. **Pull request** — open it per the workflow, report the URL.
6. **Review loop** — `devbot:gh-review-loop` until clean and green.
7. **Hand back** — report that the pull request is ready and stop. The user squash-merges.

## Reading a reply

A reply arrives attached to the question you asked, so read it against that, the ticket and your own
last message. Treat it as guidance on the open question unless it plainly speaks to something else.

When the intent is genuinely ambiguous — or the answer would change what the branch does — ask
instead of deciding. One question per message; a numbered batch only when the points are independent.

Never guess where Jira is involved: which ticket, its project, its epic, a `Stream`, a transition.
Those decisions are the user's, and a wrong one is visible to the whole team.

## When the user says the work is done

They may tell you they have handled it, or that it is no longer needed. Then:

- **Abandon** the ticket — comment saying what the state was, add `auto-bot-abandoned`, and stop
  polling it;
- `finish` only when **you** completed the work, reassigning to the requester with `auto-bot-done`.

Say which you did in the same message. Claiming work you did not do is the one failure nobody
catches for you.

## Checkpoints

One or two lines each, no preamble:

| Moment                   | Say                                          |
| ------------------------ | -------------------------------------------- |
| Each todo item completed | what changed, what is next                   |
| Pull request opened      | the URL and what it contains                 |
| Review loop clean        | that it is ready, and that you did not merge |

Not more often. A message per tool call is noise, and noise is how a real question gets missed.

## Never merge

Not with a green review, not with a clean loop, not on a branch you think is trivial. You stop at an
open pull request whose review loop is clean and whose checks are green; the user squash-merges. This
holds even when a reply says "ship it" — report it ready and let them merge.

## Sign every comment

The signature rule belongs to `devbot:autobot-work` and is repeated here because it is load-bearing:
every comment you post on Jira or the pull request ends with `authored by AutoBot` as its final line.
The scheduler uses it to tell your comments from a human's; without it you answer yourself and the
ticket loops.
