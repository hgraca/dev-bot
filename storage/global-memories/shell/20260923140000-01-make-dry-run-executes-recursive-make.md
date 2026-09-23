---
date: 2026-09-23
keywords: ["shell", "make", "dry-run", "recursive-make"]
trigger-on: ["makefile-dry-run", "recursive-make"]
---

## `make -n` executes recipe lines containing `$(MAKE)`

A dry run is not inert. GNU make executes any recipe line whose text contains `$(MAKE)` **even under `-n`**, because it must support recursive dry-runs. In this repo `up-signoz`'s recipe is a shell `if/elif/else` block whose branches call `$(MAKE) _signoz-helm-install` / `_up-signoz-fresh`, so `make -n test` — whose `test` target depends on `up-signoz` — **actually provisioned a k3d cluster** from what looked like a harmless "does this target resolve?" check. It was only noticed when its output surfaced inside a later `git commit` command, because the shell tool keeps one persistent shell: a still-running background process writes into the next command's captured output, which reads as the later command having triggered it. Concretely observed: no git hook, no harness hook, and no `make` reference in any devbot config — the invocation came from the author's own earlier `make -n`, and the search for a hook was chasing a ghost for a long time. To inspect a target without running it, read the Makefile fragments, or use `make -n <target>` only where no prerequisite's recipe mentions `$(MAKE)`. For a target that does, there is no safe dry run — assume it will execute.
