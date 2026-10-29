---
date: 2026-10-29
keywords: ["pull-request", "gh-create-pr", "agent-communication", "output-convention"]
---

## The pull-request URL rule lives in gh-create-pr, not agent-communication

Stakeholder rule (2026-10-29): whenever dev-bot's instructions reference a pull request in output — a hand-back, a status report, a review summary, a question — they give its full URL, never a bare number, `#<n>`, or "the PR". A number means nothing outside the repository it belongs to, so the reader has to go looking for the link.

The rule is stated once, in `devbot:gh-create-pr` (`src/agentic/github/skills/gh-create-pr/SKILL.md`, "Reference the PR by its URL"). The hand-back points point at it rather than restating it: `devbot:software-development` step 7, `devbot:git-worktrees`'s Finish, `devbot:work-autonomously` step 6, and `devbot:git-fixup-commits`'s squash hand-over.

Placement was the open question a review raised. `devbot:agent-communication` is loaded at session start by every agent and already owns human-facing message calibration, so it would give the rule universal reach; `devbot:gh-create-pr` is loaded only on the PR-creation path. It stays in `gh-create-pr` because the convention is GitHub-specific and the communication skill is deliberately harness- and host-agnostic — a project that does not use GitHub should not have to carry it.

The cost, accepted deliberately: an agent that reports on an existing PR without having loaded `gh-create-pr` — teamlead routing a "PR review comments" task, a status report on someone else's PR — never sees the rule. The pointers from the workflow's hand-backs cover the path that actually reports a PR the agent opened. If bare PR numbers still show up in those other reports, move the canonical text to `devbot:agent-communication` and have `gh-create-pr` point at it instead.

Guarded by prose-contract BATS: `src/agentic/github/tests/gh-create-pr_tests.bats` holds the rule and its banned forms; `src/agentic/{dev,git,devbot}/tests/*` assert that each hand-back points at it, each with a scoped negative assertion against a bare number.
