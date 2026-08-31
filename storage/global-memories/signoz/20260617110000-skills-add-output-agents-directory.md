---
date: 2026-06-17
keywords: ["signoz", "skills", "npx", "agents", "discovery"]
---

## skills add output directory moved from .skills/ to .agents/skills/

Newer versions of `npx skills add` install skills to `tmpdir/.agents/skills/` instead of `tmpdir/.skills/`. The individual skill directories (signoz-creating-alerts, signoz-mcp-setup, etc.) live under `.agents/skills/`. When writing discovery cascades for the output, check `.agents/skills` first, then `.agents`, then fall back to legacy `.skills`/`skills`/`node_modules`. The `skills-lock.json` file appears at tmpdir root alongside the `.agents/` directory.
