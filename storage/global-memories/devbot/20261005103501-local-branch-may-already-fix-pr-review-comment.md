---
date: 2026-10-05
keywords: ["devbot", "address-review", "git", "rebased-branch", "code-review"]
aliases: ["review comment already fixed locally", "stale remote pr commit", "original_commit_id"]
trigger-on: ["address-review-comment", "rebase-feature-branch"]
---

## Verify the local branch before implementing a PR review comment — it may already contain the fix

A GitHub review comment is anchored to the remote PR's `original_commit_id`, which can be stale relative to the local branch. On PR #4820 the comment flagged `OtelKafkaSpan::startMessageSpan()` for reading one shared consumer-group config key, but the local `feature/kafka-consumer-trace-context` already contained the corrected version in a rebased/amended twin commit (`7c9609cb90` vs the remote `b4bbd74`) that passes each consumer's real group in — the local branch was 47 ahead / 1 behind `origin` at that point. Before writing any code, compare local `HEAD`/`git blame` against the comment's `original_commit_id` and diff the changed file local-vs-remote; if the fix is already present, the resolution is an explanation (no code change, no commit), and the PR only reflects it once the local branch is pushed.
