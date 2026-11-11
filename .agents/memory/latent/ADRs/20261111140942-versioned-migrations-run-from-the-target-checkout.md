---
date: 2026-11-11
keywords: ["migrations", "devbot", "update", "checkout"]
---

## Versioned config migrations run from the target checkout, never the running updater

`devbot update` is a self-updating script: after `git checkout <target>` bash keeps executing the pre-update `update.sh`, and a `migrations.sh` sourced before the checkout freezes the function table at the old release — so a migration introduced by the target release is never defined. The migration phase therefore runs in a fresh `bash -c` that sources `${DEV_BOT_ROOT}/src/_shared/migrations.sh` from the target checkout, and a downgrade runs its down halves from a copy of the running release's `migrations.sh` and tools captured before the checkout (`DEV_BOT_MIGRATION_TOOLS_DIR`), because the older target predates `--down`. A release that first introduces the framework cannot be migrated by its own predecessor's script; the one-release bootstrap in `src/tools/devbot-cli/update.sh` applies the 1.15.0 migrations, leaves `storage/run/migrate-bootstrap-pending` on failure, and `bin/update.sh` retries from `0.0.0` on every subsequent run (including the already-on-target no-op) until it succeeds.
