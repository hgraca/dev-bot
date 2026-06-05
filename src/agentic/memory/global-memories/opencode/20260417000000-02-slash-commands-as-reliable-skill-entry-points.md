---
date: 2026-04-17
keywords: ["opencode"]
---

## Slash commands as reliable skill entry points

For any opencode skill that users should be able to invoke explicitly, create a matching `src/commands/<name>.md` file. The command file tells the agent to load the skill and passes through any arguments. This is more reliable than depending on the LLM to recognize trigger phrases from the skill's description.
