---
date: 2026-04-16
keywords: ["qmd"]
---

## M-FLOW-002: Initialization scripts should be comprehensive — include all setup steps needed for a clean environment

QMD was missing from POST_DOCKER_APPS, and symlinks for agents/commands weren't created, requiring manual fixes after `make up`
Review initialization scripts (bin/install.sh, opencode/init.sh) to ensure they cover all dependencies and directory structures. Missing steps force users to debug and apply fixes manually. Comprehensive init scripts reduce friction and support reproducible setups.
