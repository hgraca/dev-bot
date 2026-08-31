---
date: 2026-05-14
keywords: ["opencode", "plugin"]
---

## opencode v1.14.50 — plugin file MUST export ONLY the factory

**Trap**: opencode v1.14.50's plugin loader treats every named export of a plugin file as a plugin factory. If the file has any extra named export besides the factory (e.g. a `_resetState` helper exported for tests), the plugin still loads silently, but the FIRST hook trigger crashes with:

```
TypeError: undefined is not an object (evaluating 'H[W]')
  at Plugin.trigger (chunk-pdgzgk33.js)
```

The error fires inside opencode's hook chain — no stack frame in your plugin — so the cause looks like an opencode bug.

**Symptom**: opencode starts (TUI or `run`), then crashes the moment the first hook would fire (`chat.message`, `chat.params`, etc.) with `Unexpected server error. Check server logs for details.` In `~/.local/share/opencode/log/<latest>.log`:

```
ERROR service=server error=undefined is not an object (evaluating 'H[W]')
```

Keep ONE named export per plugin file (the factory). Attach test helpers as properties on the factory itself:

```js
export const MyPlugin = async ({ directory }) => { ... };

// NOT a separate export:
MyPlugin._resetState = () => { ... };
```

Tests then call `MyPlugin._resetState()` instead of importing `_resetState` separately.

**Detection**: For any plugin file under `.opencode/plugins/` or `src/instructions/plugins/`, count `export` statements. If more than one, expect crashes.

**Related**:

- `chat.message` hook fires for user messages only (per `@opencode-ai/plugin` v1.4.8 types and confirmed empirically). Assistant responses require the `event` hook listening for `message.updated`.
- `input.messageID` is undefined when the user did not pre-assign one; fall back to `output.message.id`.
- `experimental.chat.system.transform` and `experimental.chat.messages.transform` are typed but registering them in v1.14.50 crashes startup with `TypeError: undefined is not an object (evaluating 'P.provider')` during `config.providers` / `provider.list`.
