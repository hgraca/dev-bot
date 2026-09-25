---
date: 2026-09-25
keywords: ["pty-monitor", "bun-test", "solid-mock", "tui-plugin-test"]
---

# Testing a TUI plugin: the opentui mock must resolve reactive children, and a "rows non-empty" wait matches the empty-state placeholder

Three traps hit while adding removal controls to `src/harnesses/opencode/pty-monitor/` and testing them in `index.test.ts`.

## The `@opentui/solid` mock must resolve accessors in `insert`, not only attach `insertNode` children

The plugin builds rows and labels reactively (`insert(box, () => accessor())`) and elements imperatively (`insertNode(el, child)`). A mock whose `insert` is a no-op makes every reactive subtree unreachable — the sidebar's row list simply is not there to click, and the failure looks like "the feature does not render". The mock must invoke a function child and attach what it yields, including strings (as text nodes carrying `.text`, so a label the panel rendered from an accessor is assertable).

## `waitFor(() => rows.length > 0)` is satisfied by the empty-state placeholder

An empty list renders a single `text` placeholder (`"   (none)"`), so a bare non-empty-count wait passes immediately and every assertion behind it races the still-loading session list. Filter on the row element's `tag === "box"` and wait for the exact expected count. This cost a debugging detour: the panel looked like it rendered one row while the session fetch was actually still in flight.

## Prove a test has teeth by reintroducing the bug

Both review findings the new tests were meant to pin — a success toast throwing inside the `try` that reports the removal as failed, and the header label rendering even when nothing is clearable — were verified by temporarily reverting the fix, watching the new test go red, then restoring. A test that passes both before and after the fix proves nothing about the fix.
