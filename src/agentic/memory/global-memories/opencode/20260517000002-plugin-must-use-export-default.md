---
date: 2026-05-17
keywords: ["opencode", "plugin", "export-default"]
---

## opencode plugin loader requires export default — named export alone silently fails

opencode's plugin loader looks for the **default export** of a plugin JS file as the factory function. If a plugin only has a named export (e.g. `export const MyPlugin = async ...`), the loader logs `Plugin export is not a function` and silently skips the plugin — no crash, no further error, the plugin simply never runs. The fix is always `export default async function MyPlugin(...)` or `export default MyPlugin` at the end of the file. This affected `agent-communication.js` (commit ce8f553): the `.opencode/plugins/devbot/` copy had drifted from the source at `src/instructions/plugins/` which already had the correct default export. Diagnosis: check opencode logs for `service=plugin error=Plugin export is not a function`.
