---
date: 2026-10-30
keywords: ["github", "gh-api", "paginate", "jq", "slurp"]
aliases: ["--paginate --jq per page", "gh api slurp jq", "multi-line cursor"]
---

## `gh api --paginate --jq` evaluates the filter per page, and `--slurp` cannot combine with `--jq`

With `--paginate`, `gh api` runs the `--jq` expression **separately for every page**, so a filter that
aggregates (`max`, `sort`, `length`) yields one result per page rather than one overall. A command
substitution then captures several lines, and a caller expecting a single value (a cursor, a maximum,
a count) gets a malformed one. `--slurp` would fix it by wrapping all pages in an outer array, but
this gh version rejects the combination: `the --slurp option is not supported with --jq or --template`.

Reduce the per-page output instead of aggregating inside `--jq` — for example
`gh api repos/<owner>/<repo>/issues/<pr>/timeline --paginate --jq '[.[] | select(...) | .id] | max // 0' | sort -n | tail -1`
emits one number per page and keeps the overall maximum. Alternatives are piping the raw paginated
JSON into `jq -s` (`.[][]` flattens the pages) or emitting one id per line and reducing with
`sort -n | tail -1`.
