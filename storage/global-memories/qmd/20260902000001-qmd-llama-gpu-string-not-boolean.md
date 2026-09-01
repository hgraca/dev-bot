---
date: 2026-09-02
keywords: ["qmd", "QMD_LLAMA_GPU", "gpu", "env"]
trigger-on: ["qmd-gpu-env", "QMD_LLAMA_GPU"]
---

## qmd rejects the boolean QMD_LLAMA_GPU=true — must be a string or absent

qmd 2.8.3's `resolveLlamaGpuMode` (dist/llm.js) accepts only
`metal|cuda|vulkan|false|off|none|disable|disabled|0` (lowercased) or empty
(→ `auto`). A bare JSON boolean `true` prints
`QMD Warning: invalid QMD_LLAMA_GPU="true", using auto GPU selection` and
falls back to auto. In devbot's opencode.jsonc templates the value must be
written as the `__GPU_ENABLED__` placeholder string, which harness/init
substitution replaces with the qmd-valid string from `_qmd_gpu_value()`
(metal on Darwin, cuda/vulkan on Linux, "false" when disabled). The claudecode
harness does NOT substitute `__GPU_ENABLED__`, so its template should omit the
GPU var entirely (qmd auto-detects) rather than ship a literal placeholder.
