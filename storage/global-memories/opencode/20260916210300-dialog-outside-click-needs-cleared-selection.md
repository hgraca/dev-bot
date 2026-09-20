---
date: 2026-09-16
keywords: ["opencode", "dialog", "clearSelection", "mouse", "tui-plugin"]
trigger-on: ["opencode-tui-dialog-dismiss", "opencode-dialog-click-outside"]
---

## An opencode dialog can need two outside clicks to close unless you clear the selection first

The host dismisses a dialog on a mouse-**up** on its overlay, but its handler reads

```js
onMouseDown: () => { w = !!renderer.getSelection() }
onMouseUp:   () => { if (w) { w = false; return } onClose() }
```

so when a text selection is active at mouse-down the release is deliberately swallowed (it lets you drag-select without the dialog vanishing) and the user must click again. A plugin can prevent it: `api.renderer.clearSelection()` before opening the dialog, so the very next click finds nothing to protect. Related trap for the *opening* gesture: firing the dialog from `onMouseDown` lets the still-pending mouse-up/click land "outside" the brand-new modal and dismiss it in the same click — open on **`onMouseUp`, deferred one tick**, so the trailing `click` event passes first. Clickable sidebar rows use `setProp(el, "onMouseDown"|"onMouseUp", handler)`.
