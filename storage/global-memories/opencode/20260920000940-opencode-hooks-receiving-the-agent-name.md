---
date: 2026-09-20
keywords: ["opencode", "plugin-hook", "agent-name", "shell-env"]
trigger-on: ["opencode-plugin-hook", "opencode-shell-env"]
---

## Only some opencode hook inputs carry the running agent's name

`chat.params`, `chat.headers` and `chat.message` receive `agent` in their input (`chat.params` and `chat.headers` as a required `string`, `chat.message` optional). `shell.env` receives only `{ cwd, sessionID?, callID? }`, and `tool.execute.before` / `tool.execute.after` receive no agent either. The session object from the client API has no `agent` field at all — `parentID`, `title`, `directory` and `version` only.

Consequence: an env var for the agent name cannot be set from `shell.env` directly. Cache it from `chat.params` — which fires per LLM request, so before the session's first tool call — keyed by `sessionID`, then read it back in `shell.env`. Bound the cache: a long-lived server would otherwise keep an entry for every session it has ever seen. Verified against `@opencode-ai/plugin@1.16.2` type definitions and the installed SDK (`node_modules/@opencode-ai/sdk/dist/gen/types.gen.d.ts`).
