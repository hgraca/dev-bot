---
date: 2026-09-28
keywords: ["git", "github", "pull-request", "copilot", "code-review"]
trigger-on: ["copilot-pr-review", "gh-pr-review-comments", "address-pr-review"]
---

## Copilot PR findings also live in the review body — read it, not just the line comments

`gh api repos/{owner}/{repo}/pulls/<n>/comments` returns only the line-anchored review comments. A Copilot review additionally carries a summary review body (`pulls/<n>/reviews`) whose per-file table names findings that were never posted as comments — in one PR, five findings existed but only three had threads, and the other two (a malformed-argument parse that silently cast to `0`, and a misleading confirmation message) appeared solely as table rows such as "Create command ... malformed owner-ID parsing finding".

Addressing only the API's comments therefore ships a partly-fixed pull request. Read both: the line comments for the anchored detail, and the review body's table for the rest. Two further checks are worth making while there — fetch each comment's `commit_id` / `original_commit_id` and compare with local `HEAD`, because a comment anchored to an older SHA may already be fixed, and `line != original_line` signals an outdated anchor.
