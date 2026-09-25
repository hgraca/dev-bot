---
date: 2026-09-25
keywords: ["opencode", "tui-plugin", "mouse-event", "stopPropagation"]
trigger-on: ["opencode-tui-plugin-sidebar-row"]
---

## A control nested in a TUI row or header must stopPropagation on every event the parent handles

opencode's TUI (`@opentui/core`) dispatches a mouse event to the deepest renderable under the cursor and then bubbles it to each ancestor, stopping only once `event.propagationStopped` is set (`Renderable.processMouseEvent`: `if (this.parent && !event.propagationStopped) this.parent.processMouseEvent(event)`). So a child control placed inside a clickable row or header inherits the parent's handler: a `✕` inside a row that opens a dialog on mouse-up will also open that dialog, and a clear-action in a header that toggles collapse on mouse-down will also collapse the panel. Call `evt.stopPropagation()` in the child's handler for EVERY event type the parent reacts to — not only the one the child acts on. Stopping mousedown alone still lets the parent's mouse-up fire, and stopping mouse-up alone still lets its mousedown fire.
