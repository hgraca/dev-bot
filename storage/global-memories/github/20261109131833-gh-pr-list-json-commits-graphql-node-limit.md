---
date: 2026-11-09
keywords: ["github", "gh pr list", "commits", "graphql", "node limit"]
---

## `gh pr list --json commits` dies on the GraphQL node limit

Asking for `commits` (or any nested connection) with a large `--limit` fails with `GraphQL: By the time this query traverses to the authors connection, it is requesting up to 1,000,000 possible nodes which exceeds the maximum limit of 500,000`. The multiplier is the nested `authors` connection times the number of PRs, not the PR count — 40 PRs at `--limit 1000` is enough. It fails for every repo, so it is not data-dependent. Drop `commits` from the list call and fetch per PR over REST instead: `gh api repos/<owner>/<repo>/pulls/<n>/commits --jq '[.[] | {sha: .sha[0:7], s: (.commit.message|split("\n")[0])}]'`. One cheap call per PR, parallelisable with a small thread pool, no node limit — 423 PRs took ~30s at 8 workers.
