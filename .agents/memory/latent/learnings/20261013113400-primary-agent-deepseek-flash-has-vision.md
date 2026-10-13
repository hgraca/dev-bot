---
date: 2026-10-13
keywords: ["devbot", "vision", "deepseek-flash", "screenshot", "designer-delegation"]
---

# DevBot's primary agent is vision-capable (deepseek-flash / V4.1-Flash) — inspect images inline, delegate to @Designer only on failure

As of 2026-10-13 the primary agent model is `deepseek/deepseek-flash` (DeepSeek-V4.1-Flash), which natively accepts image input through the API. The `Read` tool returns images as attachments and the model sees them, so the primary agent inspects screenshots itself instead of delegating the verdict.

Verified 2026-10-13: captured `https://www.wikipedia.org` with `node_modules/.bin/playwright screenshot --viewport-size=1280,900 <url> /tmp/opencode/shot.png` and read it with the `Read` tool — the description was accurate and specific (serif wordmark, puzzle-globe logo, per-language article counts, search bar, sister-project grid). End-to-end vision confirmed.

## Supersedes

The 2026-08-13 learning `20260813113058-deepseek-v4-pro-cannot-see-images-designer-kimi-k3-vision.md` — its premise held only while the primary model was `deepseek/deepseek-v4-pro` (no image support). Changing the model invalidated it.

## Consequences

- **Visual verdicts are the primary agent's job.** Read the screenshot directly. Measuring dimensions, coordinates, or computed styles is not seeing — numbers alone never license a "looks correct" verdict.
- **Delegate a visual verdict to @Designer only if reading fails** — the image does not reach the agent, the file is unreadable, or the session falls back to a non-vision model. When delegating, pass the saved image's absolute path: `task` delegation is text-seeded, so inline attachments do not transfer; @Designer reads the file via its `Read` tool.
- **Profiles updated** to match: `src/agentic/devbot/agents/devbot.md` and `src/agentic/devteam/agents/teamlead.md`.

## Mechanism

`deepseek-flash` accepts images in Chat Completions (`image_url` as an http(s) URL, a base64 data URL, or a Files API `file_id`) and in the Responses API (`input_image`). Supported formats JPEG/PNG/GIF/WebP. Tool availability ≠ model vision capability, but here both hold: the agent has the tools **and** the model sees.
