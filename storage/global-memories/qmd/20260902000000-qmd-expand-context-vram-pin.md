---
date: 2026-09-02
keywords: ["qmd", "QMD_EXPAND_CONTEXT_SIZE", "vram", "gpu"]
trigger-on: ["qmd-gpu-expansion", "QMD_EXPAND_CONTEXT_SIZE"]
---

## qmd query expansion overflows small VRAM at the default 2048 context — pin QMD_EXPAND_CONTEXT_SIZE

qmd's structured query expansion model (a ~1.7B GGUF) defaults to
`DEFAULT_EXPAND_CONTEXT_SIZE = 2048` (dist/llm.js). On small-VRAM GPUs (RTX
4050 Laptop, 5.6 GB total, ~0.6–3.4 GB free once models load) that context
overflows VRAM and every hybrid query logs
`InsufficientMemoryError: A context size of 2048 is too large for the available VRAM`,
then silently falls back to unexpanded search (still works, but degraded and
noisy). Fix: set `QMD_EXPAND_CONTEXT_SIZE=512` in the qmd MCP `environment`
(module templates `src/agentic/qmd/mcp.opencode.json` + `mcp.claudecode.json`,
and the legacy root dist) — 512 tokens is ample for generating query variants
while fitting small VRAM. 512 is read via `process.env.QMD_EXPAND_CONTEXT_SIZE`
(parseInt, positive integer; invalid values warn and fall back to 2048).
