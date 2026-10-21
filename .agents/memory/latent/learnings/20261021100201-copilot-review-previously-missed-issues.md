---
date: 2026-10-21
keywords: ["copilot", "review", "pull-request", "gh-cli"]
aliases: ["copilot review loop", "previously missed issues", "add-reviewer copilot"]
---

# Copilot review: "No open issues" does not mean no findings

`devbot:work-autonomously` ends the Copilot loop when the reviewer raises no further findings. Read three sections of the review body, not just the summary:

- **open issues** — findings from the current pass;
- **previously missed issues** — findings in code the last push did not touch. A review can report `**No open issues** 🎉` and still list these (observed on GET-E/dev-bot#12, rounds 3 and 5). The loop is not finished until this section is absent too.

## Requesting the reviewer

`gh pr create --reviewer @copilot` failed with `could not request reviewer: '@copilot' not found`, leaving the PR without a request. `gh pr edit <pr> --add-reviewer @copilot` and the `requested_reviewers` API both returned success, but `requested_reviewers` stayed empty while the timeline showed `copilot_work_started`. GitHub accepts `@copilot` for the review workflow without listing the bot as a requested reviewer — confirm with the timeline (`gh api repos/<owner>/<repo>/issues/<pr>/timeline --jq '.[].event'`) rather than with `requested_reviewers`.

## Watching CI

In a checkout with more than one remote, `gh pr checks <pr>` fails with "No default remote repository has been set". Pass `--repo <owner>/<repo>`.
