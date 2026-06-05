---
date: 2026-05-03
keywords: ["opencode", "tool"]
---

## PR patches targeting `dev` branch conflict with version tags

Upstream PRs (e.g. #14772) target the `dev` branch which has structural differences from release tags (e.g. `v1.14.33`). Applying these patches to a tag checkout produces conflicts. Fix: use `origin/dev` as the checkout base for patch application (not the version tag). The VERSION variable is still used for state tracking but not for checkout.
