---
date: 2026-09-16
keywords: ["git", "pull-request", "review-comments", "generated-files"]
trigger-on: ["pr-review-comments", "generated-file-review"]
---

## Verify a review comment's premise before complying: check the reviewed SHA and file ownership

Two cheap checks prevent wasted or harmful "fixes" when addressing PR review comments. First, **compare the reviewed commit with local HEAD**: GitHub anchors review comments to a specific SHA, so if local commits are unpushed the comment may already be resolved — on PR GET-E/positioning-activities#340 the bot reviewed `d11a823` while local HEAD was 14 commits ahead, and one of its two comments was already fixed by work that simply had not been pushed. Second, **check whether the file is hand-authored or generated**: a comment asking to revert a line in a plugin-generated file is usually wrong to comply with, because the generator will overwrite the edit and the change may be a deliberate upstream fix. Resolve it by reading the generator's template and its git history (`git log -p` on the template path) — dev-tools' `52cb54e` showed the contested `COMPOSER_AUTH` change was intentional, so the right response was to raise it upstream rather than hand-edit a managed file.
