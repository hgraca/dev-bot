---
date: 2026-11-26
keywords: ["npm", "omit=peer", "peer dependencies", "optional peers", "npm install"]
aliases: ["npm omit peer", "skip electron peer", "peerDependenciesMeta optional"]
---

## `.npmrc omit=peer` does not skip optional peers — it drops non-optional ones

`omit=peer` is not the way to keep a heavy peer such as electron or `@opentui/core` out of a tree: peers marked `optional` in `peerDependenciesMeta` are already skipped by default, so the flag buys nothing there, while it silently removes **non-optional** peers — installing `@effect/platform-node` normally pulls `redis` + `@redis/*`, and with `omit=peer` they vanish from the tree. The measured effect on one real manifest was 267 → 273 packages and 527 → 510 MB, i.e. a correctness risk for no meaningful size win. Measure `npm install` with and without the flag and assert the delta before committing an `.npmrc` that claims to save space; if a peer truly must not install, omit the package that requires it instead.
