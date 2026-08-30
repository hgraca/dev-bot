---
date: 2026-08-22
keywords: ["devbot", "hooks", "harness", "architecture"]
---

## Hook logic lives once in harness-agnostic tools/; harness hooks are thin adapters

Each agentic module's hook business logic now lives once in a harness-agnostic `tools/` entry — importable by the opencode TypeScript plugin and runnable as a CLI by the claudecode bash hook. The harness hooks themselves are thin adapters that only extract their event payload and invoke the tool. This removes the per-harness duplication where every module shipped both a `.ts` opencode plugin and a `.sh` claudecode hook implementing the same logic. Converted modules: `guards`, `auto-recover`, `graphify` (commit-trigger), and `k8s`. Next phase (Option A) adds a declarative hook manifest plus one generic adapter per harness and relocates the thin hooks into the harness modules for self-containment.
