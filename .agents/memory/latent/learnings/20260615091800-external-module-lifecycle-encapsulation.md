---
date: 2026-06-15
keywords: ["devbot", "external-modules", "install", "lifecycle", "encapsulation"]
see: ["project/20260614150000-two-phase-install-gap.md"]
---

# External module lifecycle encapsulated in external-modules/install.sh

> **SUPERSEDED (2026-09-27)** by
> [ADRs/20260927172101-external-modules-enablement-independent.md](../ADRs/20260927172101-external-modules-enablement-independent.md):
> the rebuild now lives in `_shared/functions.sh` as `_devbot_rebuild_external_module_config`, and
> `bin/up.sh` no longer keeps its own copy — it delegates like `install.sh` does.

The config rebuild logic (`_rebuild_external_module_config`) was moved from `bin/install.sh` into `src/agentic/external-modules/install.sh` so all external module lifecycle — config population from `external-modules.json` declarations plus git clone/pull into `vendor/` — lives in a single self-contained script. The module's `install.sh` now runs config rebuild first, then the existing cloning loop, in one pass. This means `bin/install.sh` delegates to the module without needing inline config logic, and if another lifecycle script needs external modules handled, it calls `external-modules/install.sh` directly. `bin/up.sh` retains its own copy of the config rebuild logic as a safety net for modules added after initial install.
