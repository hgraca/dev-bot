---
date: 2026-09-18
keywords: ["opencode", "shell.env", "session-id", "plugin"]
trigger-on: ["opencode-plugin-session-id", "opencode-shell-env-injection"]
---

## opencode exports the session id to the AI's shell only via a plugin's shell.env hook

opencode does not put the session id into the Bash tool's environment by default (a real session's
`env` shows only `OPENCODE=1` and `OPENCODE_PID`). A plugin's `"shell.env"` hook receives
`input.sessionID` and may mutate `output.env`, and opencode merges those variables into every shell
it runs — the AI's Bash tool, shell-mode `!command`, and PTY terminals (plugin docs: "inject
environment variables into all shell execution (AI tools and user terminals)"; introduced by
opencode PR #12012, "LLM tool calls (bash tool)"). So the supported way to make a per-session value
usable by a script an agent runs over bash is a `shell.env` handler, e.g.
`Object.assign(output.env, sessionEnvVars(input?.sessionID))`; a custom tool returning
`context.sessionID` also works but forces the agent to know and pass the id. The variable is only
present after the harness restarts, because opencode loads config and plugins once at startup.
