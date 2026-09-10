---
date: 2026-09-10
keywords: ["address-review", "review-comments", "protocol", "interview-me"]
---

## Batch address-review comment decisions into a single round

The `devbot:address-review` protocol now presents every review comment together in one message — explanation, assessment, and a proposed resolution for each — and collects all decisions in a single reply, mirroring the batched-frontier style of `interview-me`/`grilling`. Previously it discussed each comment one at a time and waited for a decision before moving on, costing a round trip per comment. Implementation is still deferred until every comment is decided, and each approved change still gets its own atomic commit (one commit per comment). Callers (`devbot.md` assignment-end flow, `gh-review.md`) no longer restate the protocol; they point at the skill as the single source of truth.
