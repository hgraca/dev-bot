---
date: 2026-10-12
keywords: ["devbot", "docs.md", "manifest", "skills", "tests"]
aliases: ["module manifest coverage", "skills manifest test scoped"]
---

# The docs.md skills-manifest test covers only the memory module

`src/agentic/memory/tests/memory-smoke_tests.bats` contains a test
("skill files: the on-disk skills match the module manifest") that compares a module's
`docs.md` `skills:` array against its on-disk `skills/*` directories — but its
`MODULE_DIR` is hardcoded to the **memory** module (`$TEST_DIR/..`). No equivalent test
exists for any other module.

## Consequence

Adding a skill to a module that has no `tests/` dir — e.g. `frontend`, which currently
has none — is **not** test-enforced. The `skills:` manifest entry and the on-disk skill
directory can silently drift while the whole suite stays green (the module then gets no
page and no reference site-wide, since the manifest drives the generated docs).

## What to do when adding a skill to a module

Verify the manifest by hand — the comparison is order-insensitive (both sides sorted):

```bash
sed -n 's/^skills: \[\(.*\)\]$/\1/p' <module>/docs.md | tr ',' '\n' | tr -d ' "' | sed '/^$/d' | sort
find <module>/skills -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
```
