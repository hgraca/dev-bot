---
date: 2026-09-25
keywords: ["opencode", "tui-plugin", "dialog", "dialog-confirm"]
trigger-on: ["opencode-tui-dialog-confirm"]
---

## The TUI DialogConfirm clears the dialog stack itself — do not clear it again

`api.ui.DialogConfirm` renders opencode's confirm component: on confirm or cancel it invokes `onConfirm`/`onCancel` and then calls `dialog.clear()` itself (verified against the opencode bundle — the Enter binding and both click handlers run the callback and then clear the stack). Push it with `api.ui.dialog.replace(() => api.ui.DialogConfirm({ ... }))`; the render callback must run inside a render pass, which `replace` provides, and calling a host component outside one is the same failure mode as building an element outside a render pass. Do NOT call `api.ui.dialog.clear()` from `onConfirm` — the stack is cleared twice and any dialog the confirm's own work opened is torn down with it. Esc dismisses the component via `clear()` WITHOUT invoking `onCancel`, so `onCancel` must not be relied on to run cleanup.
