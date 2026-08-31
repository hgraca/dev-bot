---
date: 2026-05-06
keywords: ["opencode", "plugin", "session"]
---

## opencode session.messages returns `{ info, parts }[]` — role is at `item.info.role` not `item.role`

`client.session.messages({ path: { id } })` returns `Array<{ info: Message; parts: Part[] }>`. The `role` field is on `item.info.role`, NOT `item.role`. Code that does `messages.find(m => m.role === "user")` silently returns `undefined` every time — the find always fails. Use `messages.find(m => m.info.role === "user")`. Similarly, message parts from the response are at `item.parts` (top-level), not `item.content?.parts`. Confirmed by opencode binary source (`stats` command: `for (let I of z) { if (I.info.role === "assistant") ... }`). Note: `remember-session.js` lines 75–78 had this latent bug — loop-prevention Option C was dead code; only the lock file (Option B) actually guarded re-entrancy. Fixed in commit `b4774f2` (2026-05-06).
