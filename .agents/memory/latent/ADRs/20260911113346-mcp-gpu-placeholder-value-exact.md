---
date: 2026-09-11
keywords: ["mcp", "__GPU_ENABLED__", "mcp_key_is_current", "qmd"]
see: ["ADRs/20260907140000-mdctx-memory-search-engine-swap.md"]
---

## __GPU_ENABLED__ compared value-exactly when --gpu is supplied

`mcp_key_is_current.py` compares `__GPU_ENABLED__` value-exactly when the caller passes `--gpu` (both harness resets do, using `_qmd_gpu_value()`), so a stale or wrong resolved GPU value — e.g. `"false"` frozen from an older devbot on a GPU host — is reported stale and refreshed on reinit. Without `--gpu` the previous any-value behavior stands, so a caller with no expected value never churns. This revises the placeholder treatment recorded in `20260907140000-mdctx-memory-search-engine-swap.md` (audit-03 §4).
