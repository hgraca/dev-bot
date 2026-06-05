---
date: 2026-05-17
keywords: ["opencode", "plugin", "export-default", "loader"]
---

## opencode plugin loader requires export default — named export alone silently fails

opencode's plugin loader looks for the **default export** of a plugin file as the factory function. If a plugin only has a named export (e.g. `export const MyPlugin = async ...`) and no `export default`, the loader logs `Plugin export is not a function` and silently skips the plugin — no crash, no further error. The plugin simply never runs. The fix is always to use `export default async function MyPlugin(...)` (or `export default MyPlugin` after a named declaration). This applies to all plugins under `.opencode/plugins/` loaded via `opencode.jsonc`. Discovered when `agent-communication.js` had `export const AgentCommunicationPlugin = async ...` without a default export, causing subagent task sessions to abort because the nudge/status-enforcer never fired (commit ce8f553).
