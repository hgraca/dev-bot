---
date: 2026-09-16
keywords: ["opencode", "tui-plugin", "createelement", "solid", "render-context"]
trigger-on: ["opencode-tui-plugin-render", "opentui-createelement"]
---

## opencode TUI plugin elements must be built inside a render pass, and `fg` only works on `text`

Two silent-failure traps when rendering a TUI plugin. (1) `createElement` (from `@opentui/solid`) resolves its renderer from a **Solid context**, so constructing an element outside a render pass throws `No renderer found` — and the exception is easy to swallow. Build elements **lazily inside a render callback**, never precompute them: `api.ui.dialog.replace(() => column([...]), onClose)` works, whereas `const el = column([...]); api.ui.dialog.replace(() => el, ...)` throws. The same rule applies to signal-driven lists: pass an accessor to `insert(parent, () => accessor())` and let the reuse happen inside the effect. (2) `setProp(el, "fg", colour)` is only proven on **`text`** elements (that is how the shipped `opencode-tabs` colours its labels). Nesting a `span` inside a `text` and colouring the span renders **uncoloured with no error** — to colour part of a line, use a flex **row `box`** containing two `text` elements. Colours come from `api.theme.current` (`primary`, `success`, `error`, `text`, `textMuted`, `backgroundElement`, `border`, …).
