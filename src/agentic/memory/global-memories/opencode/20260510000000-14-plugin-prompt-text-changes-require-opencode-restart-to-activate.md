---
date: 2026-05-10
keywords: ["opencode", "plugin", "session"]
---

## Plugin prompt-text changes require opencode restart to activate

When a plugin's CAPTURE_PROMPT_TEXT (or any other inline string) is edited and committed, the change does **not** take effect on the running opencode process. The plugin module is loaded once at session start and the prompt string is captured as a closure constant. A subsequent `session.idle` event will use the old prompt text until the user restarts opencode (or reloads the plugin). **Confirmed 2026-05-10**: after committing the `remember-session.js` prompt rewrite (commit d852332), the next idle capture still received the old "Please load the skill and run it now" text, not the new explicit single-invocation directive. Only after user restart did the new prompt fire. **Implication**: when fixing agent behaviour via plugin prompt text, communicate the restart requirement to the user — don't expect the fix to be "live" mid-session. **Rule**: any commit that edits inline strings, schemas, or hooks in `src/plugins/*` should include a "restart opencode to activate" note in the commit body or post-commit message. See [[ADRs]] M-ARCH-034 plugin-lifecycle context.

---
