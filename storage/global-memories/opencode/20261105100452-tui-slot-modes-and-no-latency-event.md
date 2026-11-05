---
date: 2026-11-05
keywords: ["opencode", "tui", "slot", "sidebar_content", "single_winner"]
aliases: ["tui plugin slots", "app_bottom"]
---

## opencode TUI slots: additive content, one-winner footers, and no latency event

`sidebar_content` panels are additive and ordered (built-ins at 100/200/300/400/500), so a plugin can add a row but can never append to or edit another plugin's row — extending the built-in context line means disabling `internal:sidebar-context` and rendering the row yourself. `single_winner` slots (`sidebar_footer`, `sidebar_title`, `home_footer`) render exactly one registered plugin — the first entry in the slot registry — so registering there replaces the built-in (`internal:sidebar-footer` owns the `dir • branch` line at order 100) rather than composing with it; the host's fallback children render only when the winner returns nothing. `app_bottom` is host-rendered in a full-width `flexShrink:0` box below the route (which-key registers it) but is absent from `@opencode-ai/plugin@1.4.8`'s `tui.d.ts`, so code against the runtime or a newer types package. Finally, opencode publishes **no provider-latency event or duration**: request timing must be derived from `message.updated` (`time.created`/`time.completed`, `providerID`), the first `message.part.delta` (which carries no timestamp — stamp `Date.now()` yourself), and `session.status` retry states.
