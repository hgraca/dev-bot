---
date: 2026-11-03
keywords: ["slack", "mention", "lookupByEmail", "github-actions"]
aliases: ["author not tagged", "slack mention not working", "users.list fallback"]
trigger-on: ["slack-author-mention"]
---

## Resolving a commit author to a Slack mention needs a login fallback

Resolving a GitHub actor to a Slack mention by calling `users.lookupByEmail` with `head_commit.author.email` only works when the git email matches the Slack account. Commits authored with a personal address (a developer's gmail alias, a `users.noreply.github.com` address) silently fall back to the plain name, so the alert notifies nobody — the mention degrades exactly where it matters. Add a fallback before the plain name: match the GitHub login against `users.list` (`name` or `profile.display_name`, case-insensitive, paginated) and emit `<@ID>`; a config map of login to Slack id is the deterministic variant when the handle does not match. Scheduled workflows carry no `head_commit` at all, so fetch the commit through the API using `github.sha` first, and note that on a schedule the author is whoever last touched the default branch rather than the person whose change broke the build.
