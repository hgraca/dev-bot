---
date: 2026-09-22
keywords: ["devbot", "codebase-index", "provider", "fail-safe", "destructive"]
trigger-on: ["devbot-destructive-predicate", "codebase-index-provider-flip", "module-reset-prune"]
---

## A predicate that authorises a destructive action must fail safe when its source is unreadable

`devbot reinit` runs every module's `reset.sh`, disabled modules included, so `src/agentic/codebase-index/reset.sh` prunes the retired `.opencode/index/` store when the module is disabled. That predicate was built on `_devbot_get_disabled_modules`, which derives the set from `_devbot_get_codebase_provider` — and that helper maps **"the provider key could not be read"** onto the same `codebase-memory` default as a real flip. Both a corrupt `.devbot.global.jsonc` and a mis-resolved `DEV_BOT_ROOT` (the script is documented for direct invocation, and `_shared/functions.sh` computes the root one level short — see the `shell/` global note on that) therefore selected the default, reported codebase-index as retired, and `rm -rf`'d a live engine's ~80 MB store. The inline comment claiming "a lookup failure reads as still enabled, so an unreadable config can never trigger the prune" was simply false.

Two rules fall out of this. First, never let a destructive branch rest on a helper that collapses an error into a legitimate value: probe the source and treat unreadable as "unknown, do nothing" — `[[ -f "${config}" ]] && ! python3 read_jsonc.py "${config}" <key> >/dev/null 2>&1` → return "not disabled" plus a `WARN:`. A genuinely *absent* config is a different case from an unreadable one; absent really is the documented default, so it may still authorise the prune. Second, a safety comment inside a destructive path is a claim that must be reproduced, not reasoned: this one was disproved by the very first probe (`env -u DEV_BOT_ROOT bash reset.sh <proj>`, store deleted). The reviewer's requested regression test — an unreadable config asserting the store survives — is the durable guard.
