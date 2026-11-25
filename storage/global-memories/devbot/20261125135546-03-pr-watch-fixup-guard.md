---
date: 2026-11-25
keywords: ["devbot", "pr-watch", "no-fixup", "review-loop"]
aliases: ["No fixup! commits check", "pr-watch exits 3", "gh-review-loop gate"]
trigger-on: ["gh-review-loop-wait", "pr-watch-guard"]
---

## `pr-watch` stops on a repository's `No fixup! commits` guard

`devbot:gh-review-loop`'s gate excludes a required check named `no-fixup`, but hotels-api's guard is named `No fixup! commits`; `pr-watch` therefore exits 3 while the branch still carries fixups, before a review lands. The guard is expected red until the squash — do not read it as a failure. Either poll the reviews directly with a bounded wait, or extend the gate and `pr-watch` to recognise the check's name. The fixups still must be squashed before the push that publishes the branch.
