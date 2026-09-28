---
date: 2026-09-29
keywords: ["git", "since-until", "committer-date", "approxidate"]
trigger-on: ["git-log-date-window"]
---

## `git log --since/--until` filters on committer date, and a date-only bound uses the current time of day

`--since`/`--until` compare against the commit's **committer** date, so a rebased or cherry-picked commit authored long ago but committed now lands inside a recent window — while `%aI` still reports the old author date, so code that filters one way and buckets the other silently mixes the two bases. Separately, a **date-only** value is resolved by approxidate using the *current* time of day rather than midnight: with the clock at ~22:45, `git log --since=2026-09-28` excluded a commit made the same day at 22:42, whereas `--since=2026-09-28T00:00:00+00:00` included it; in one measured case a date-only `--since=<Monday>` silently dropped all 14 of that Monday's commits. Always pass a full ISO-8601 timestamp with an explicit offset and build day boundaries yourself (`…T00:00:00+00:00` to `…T23:59:59+00:00`) whenever day-bounded semantics matter.
