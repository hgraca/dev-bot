---
date: 2026-09-11
keywords: ["external-modules", "module-list", "wiring-path", "audit-03"]
---

# External-module state is per-module; wiring path is `.agents/`

## `devbot module list` status is per-module

The status is ✔ only when the module's **source resolves AND its storage mirror exists** — never the shared vendor clone. Several modules can share one repo (mindrally-*), so clone-presence falsely marked un-mirrored modules resolved (audit-03 §9).

## Wiring path is `.agents/`, not `.opencode/`

External modules wire into the project's devbot dir: `.agents/<type>/<name>`. Docs claiming `.opencode/<type>/<name>` are drift — the harness delegates from `.agents/`.
