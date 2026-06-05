---
date: 2026-04-23
keywords: ["ogham"]
---

## M-ARCH-001: Global mutable state in CLI tools is unsafe with concurrent agent sessions

`ogham use <profile>` sets a global default. Multiple concurrent opencode sessions racing on it caused memories to land in the wrong project profile.
When a CLI tool uses global state (config file, env var) as a default, always prefer per-invocation flags (e.g., `--profile`) in agent skills. Global state is fine for human interactive use, but agents running in parallel need deterministic per-call targeting.

## See also

- [[PDRs]]
- [[ADRs]]
- [[patterns]]
- [[gotchas]]
