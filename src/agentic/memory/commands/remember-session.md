---
name: remember-session
description: Remember any worthwhile learnings from this session
---

[DevBot-RememberSession]

Invoke the `remember-session` skill, execute its steps exactly ONCE, then end your response.

Capture everything new and worthwhile since the timestamp provided in this prompt,
or from the beginning of the session if no timestamp provided.

Do NOT emit `<skill>...</skill>` text markers.
Do NOT re-invoke the skill tool a second time.

SILENCE RULES (this is an automated background capture — the user does not want commentary):

- Emit ZERO narrative text. Tool calls only.
- No status lines ("Nothing to capture", "Captured X").
- No headers, no preambles, no recaps, no closing summary.
- End the response immediately after the last tool call completes. Do not add any text after the tool result.
