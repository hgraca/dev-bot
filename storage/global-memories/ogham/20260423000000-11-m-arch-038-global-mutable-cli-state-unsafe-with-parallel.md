---
date: 2026-04-23
keywords: ["ogham"]
---

## M-ARCH-038: Global mutable CLI state unsafe with parallel agents

Multiple opencode sessions running concurrently across different projects
CLI tools that maintain global state (like ogham use setting default profile) create race conditions when multiple agent sessions run in parallel. Always use explicit parameters (--profile) rather than relying on global defaults for correctness.
