---
date: 2026-09-28
keywords: ["devbot", "memory-vault", "prune", "cross-references"]
---

# Pruning the memory vault: stale-check against live code, then repair refs

## Verify staleness against the tree before deleting

A latent note is only safely deletable once the system it describes is confirmed gone from the code, not merely old. The vault accumulates notes about subsystems later removed — the remember-session watermark/trigger plugins, the `devbot agentic-tools` CLI, the namespaced external-modules model, the session-idle nudge plugins, `docs/module.md`. Grep for the named file/function and `ls` the named directory rather than trusting the note's own wording. A prior session's explicit `SUPERSEDED (date) by …` banner is the strongest signal, but still spot-check it. Also look for orphaned tests of removed code: `src/agentic/memory/tests/remember-session_plugin_tests.bats` exercised functions defining watermark behaviour for a plugin that no longer existed.

## Deleting a superseded note leaves dangling refs in its survivors

Removing a file breaks any remaining note whose frontmatter still points at it — `see:`, `supersedes:`, `superseded_by:` arrays keep the old path. Re-run a reference audit after every deletion pass: enumerate each latent file's ref keys, resolve targets against the latent root (`latent/global/…` against `storage/global-memories/`), and fix the dangling ones by dropping the entry or repointing to the superseding file. A prune that ignores this trades stale content for broken links.

## The retired `project/` prefix

Older learnings used `see: ["project/<file>.md"]` where the target now lives under `learnings/` — the routing folder was renamed and the prefix was never updated. Any audit should treat `project/` as a legacy alias and rewrite it to `learnings/`.
