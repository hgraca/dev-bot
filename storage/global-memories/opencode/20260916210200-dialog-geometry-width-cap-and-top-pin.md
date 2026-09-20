---
date: 2026-09-16
keywords: ["opencode", "dialog", "layout", "setSize", "tui-plugin"]
trigger-on: ["opencode-tui-dialog", "opencode-dialog-setsize"]
---

## opencode's dialog `size` is a WIDTH, and its top edge is pinned a quarter-screen down

A plugin cannot freely shape an opencode dialog, and two facts explain most surprises. (1) `api.ui.dialog.setSize(size)` sets the dialog's **width**, not its height — `"xlarge"` is 116 columns, `"large"` 88, otherwise 60 (opencode's own plugin manager picks the tier from the terminal width: `>=128 → xlarge`, `>=96 → large`, else `medium`). Width is therefore **hard-capped at 116 columns**; a plugin has no wider option. (2) The host renders the dialog as a full-screen overlay with `alignItems: "center"` (horizontal only) and **`paddingTop = terminalHeight / 4`**, so the dialog's top edge is pinned a quarter-screen down and it grows **downward** from there. Consequence: for the dialog's midpoint to land on the screen's midpoint its total height must be exactly **half the screen** — so "tall" and "centred" are mutually exclusive, and height is the only shape lever. Also: `setSize` must be called **after** `replace`, because `replace` resets the size as part of pushing the entry, so calling it before is silently overridden. A `scrollbox` only scrolls with a **bounded `height`** plus `scrollY: true`, and `stickyScroll` + `stickyStart: "bottom"` pin it to the newest output (a `tail -f` view).
