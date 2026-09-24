---
date: 2026-09-25
keywords: ["opencode", "tui", "tool-details", "defaults", "devbot-harness"]
---

## dev-bot's opencode TUI defaults "tool details" to hidden, opt-out via the TUI toggle

"Hide tool details" is not a config key — it is TUI runtime state (`tool_details_visibility` in opencode's kv store) — so no dist template can set it and a fresh install opens with details shown. dev-bot ships the opinion as the `tui-defaults` TUI plugin (`src/harnesses/opencode/tui-defaults/`), which seeds the kv value at startup for both install and update, since updates funnel through reinit and the same farm/reconcile steps. The rule is deliberately narrow: **set `false` only while the kv key is absent, and never override a value already present** — that makes any existing value (the user's toggle, or opencode's own default having leaked to disk) the single source of truth, and it means toggling the setting in the TUI is the opt-out. The rejected alternative was to treat the persisted opencode default `true` as "unconfigured" and force it hidden; that would also flip a user who had deliberately re-enabled details, which the absent-key rule never does. Scope is `tool_details_visibility` alone — the sibling toggles (generic tool output, timestamps, thinking) are untouched, and no dev-bot config knob was added. Consequence to remember: because the seed fires only on an absent key it is a no-op on every later start, so an already-persisted `true` is left alone even on an update.
