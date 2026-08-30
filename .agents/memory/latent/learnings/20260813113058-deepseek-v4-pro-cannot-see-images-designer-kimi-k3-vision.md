---
date: 2026-08-13
keywords: ["devbot", "vision", "deepseek-v4-pro", "designer", "kimi-k3"]
---

# Primary agent model (DeepSeek v4 Pro) cannot see images — only Designer (kimi-k3) is vision-capable

DevBot's primary agent runs on `deepseek/deepseek-v4-pro`, which cannot process images through the API — even though the agent has the `chrome-devtools` MCP and the `Read` tool (which returns images as attachments). Tool availability ≠ model vision capability. A false assumption that the primary agent could compare UI inline was caught and corrected by the human.

The only subagent on a vision-capable model is Designer (`cortecs/kimi-k3`). Consequence: any visual comparison ("validate this UI against that screenshot") must be delegated to Designer with saved screenshot file paths — never done inline by the primary agent.

Verified 2026-08-13: Designer was delegated to describe `.agents/memory/thinking/sourcing-v2.png` and returned an accurate, specific description (verbatim UI text, GIATA property IDs, exact room counts) — confirming kimi-k3 vision works end-to-end via the `Read` tool.

Mechanism: subagent delegation via `task` is text-seeded, so image attachments in the primary transcript do not transfer to the subagent. Capture the screenshot to disk first (`chrome-devtools` `take_screenshot` has a `filePath` param; `playwright` saves `page-{timestamp}.png` by default), pass the path to Designer, and Designer reads the image itself. Designer's validation mode was updated (2026-08-13, commit b714f52) to accept reference screenshot paths + live UI as visual evidence.

Related prior work: local gemma3 vision via Ollama is documented as unusably slow/unreliable — see learnings/20260810150000-gemma3-vision-ollama-gotchas.md. Designer on kimi-k3 is the working vision path, not a local vision model.
