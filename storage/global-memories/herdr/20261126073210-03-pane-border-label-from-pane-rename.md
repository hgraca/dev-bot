---
date: 2026-11-26
keywords: ["herdr", "pane", "label", "rename", "session-title"]
aliases: ["pane border shows the session title", "herdr pane rename", "pane name from agent"]
---

## herdr pane borders take their label from `pane rename`, never from config

A herdr pane border shows a **manual pane label**, or the agent kind when none is set. `ui.show_agent_labels_on_pane_borders` only adds that agent kind (the word "opencode"), and only while no manual label exists — it does not render the terminal title. No config key puts a pane's `terminal_title` in the border, so a pane that says which session it hosts needs `herdr pane rename <pane_id> <label>`, driven from outside: an agent-side plugin that renames the pane it runs in, since the OSC title the agent emits stops at herdr's pane boundary.

`herdr pane rename <pane> --clear` drops the label again — the right teardown when whatever claimed it goes away. Note the outer title template's two different tokens: `{pane}` renders this manual label, `{terminal_title}` renders the pane's own OSC title. They are easy to confuse, and only the second follows the agent automatically.
