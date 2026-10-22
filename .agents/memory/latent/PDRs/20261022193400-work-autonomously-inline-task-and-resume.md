---
date: 2026-10-22
keywords: ["work-autonomously", "resume", "arguments", "copilot-review"]
aliases: ["inline task", "resumable autonomous run", "1 minute poll cadence"]
see: ["PDRs/20261020081822-copilot-review-loop-lives-in-work-autonomously.md"]
---

## `work-autonomously` takes the task inline and resumes from branch state

Three stakeholder decisions in one session (2026-10-22).

**Arguments.** The command reads `$ARGUMENTS`, not `$1`. `$1` holds only the first token, so a task
had to be handed over as a file path or a URL. Now an existing path is read, a URL is fetched, and
anything else is taken as the task in the user's own words; with no argument it asks. Positional
arguments remain correct where the argument has a fixed shape (a path, a branch, a PR URL) —
`rfp` documents why it stays positional.

**Resumption.** A second run on the same branch starts from the state it finds rather than from
zero. The command derives progress from git and gh — commits ahead of the default branch, a pull
request in **any** state (`--state all` plus `mergedAt`; an open-only query cannot tell a merged or
closed PR from none at all), the last Copilot review with its addressed threads, and
`git status --porcelain` — reports it in three lines, then continues at the first incomplete step
without waiting for confirmation. The current branch is the task's identity: never cut a new branch,
never reopen a closed pull request, never re-request Copilot while a review is pending (it would
spend a round on a review already in flight), and stop when uncommitted work is not the task's
rather than stashing or discarding it.

**Cadence.** Copilot review polling is every 1 minute, up to 60 checks (was 5 minutes × 12). The
ceiling is unchanged at ~60 minutes; the faster interval picks a review up within a minute of it
landing instead of idling up to five.
