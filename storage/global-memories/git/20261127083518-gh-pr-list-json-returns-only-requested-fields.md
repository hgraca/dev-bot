---
date: 2026-11-27
keywords: ["git", "gh", "json", "pull-request"]
aliases: ["gh pr list --json unknown field", "gh json always empty", "jq filter on unrequested field"]
trigger-on: ["gh-pr-list-json-fields"]
---

## `gh pr list --json` returns only the fields it is asked for

A `--jq` (or `-q`) filter sees only the fields named in `--json`. Filtering on a field that was not
requested does not error: the key is absent, the `select()` matches nothing, and the command exits 0
with empty output — which reads as "no such pull request". A standing-PR lookup written as
`gh pr list --json number,url --jq '.[] | select(.title == "…")'` therefore always reports none, and
a check meant to refuse a duplicate silently lets it through. Request every field the filter reads
(`--json number,title,url`), and keep a stub or fixture that fails when a filtered field is missing
from the request.
