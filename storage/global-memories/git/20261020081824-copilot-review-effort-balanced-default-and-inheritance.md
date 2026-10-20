---
date: 2026-10-20
keywords: ["git", "github", "copilot", "review-effort", "lite"]
aliases: ["review effort Lite Balanced", "Copilot effort default", "Review effort line"]
supersedes: ["git/20261001155219-copilot-review-effort-level-not-settable-from-cli.md"]
---

## Copilot review effort defaults to Balanced and is inherited, not pinned by the CLI

GitHub made **Balanced** the built-in default for Copilot code review on 2026-09-28; Lite applies
only when a lower level explicitly selects it. Neither `gh` nor the REST/GraphQL request bodies
expose an effort parameter (checked 2026-10-14 — the 2026-10-02 changelog promised one, but the
published schemas still lack it). A request resolves effort in this order: a per-request choice in
the PR's Reviewers panel, the effort previously used on that PR, the requestor's personal setting,
the repository, the organization, then the built-in Balanced default. To force Lite, set the
requestor's personal Copilot code-review effort to Lite or select Lite in the Reviewers panel, and
re-select it for every re-request. Confirm what ran from the `**Review effort:**` line in the review
body; a docs-only PR reviewed at Balanced means the Lite requirement was not in effect.
