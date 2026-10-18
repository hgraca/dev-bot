---
date: 2026-10-18
keywords: ["devbot", "_link_skills", "skill-farm", "symlink", "skills"]
aliases: ["dangling skill link", "stale skills/devbot link"]
---

# `_link_skills` must prune a module's farm link when its skills dir disappears

## The trap

`_link_skills` (`src/tools/devbot-cli/functions.sh`) used to `return` as soon as a module had no `skills/` directory. Deleting a module's skills therefore left `.agents/skills/devbot/<module>` dangling forever: opencode scans the farm and hits a broken skill entry, and no reinit cleaned it up.

## Fix and rule

Before returning, the helper now removes `link_name` only when it is a symlink whose `readlink` equals the `skill_dir` it would have linked. A foreign-target link and a real directory at the same name are left untouched. Links created against a previous `DEV_BOT_ROOT` are deliberately not pruned — the exact-match rule is what guarantees user-created links are never deleted.

## Known limits

A module disabled in the same reinit never reaches `_link_skills`, because the caller (`_link_modules`) skips disabled modules entirely. A link pointing at the generated `storage/<module>/skills` dir also survives if the `.devbot-generated` sentinel disappears while the committed fallback is absent.

## Test placement

The prune tests live in `src/tools/devbot-cli/tests/link_skills_tests.bats`, beside the other `_link_skills` tests and on that file's sandboxed `DEV_BOT_ROOT` — not in `devbot_tests.bats`, which is the `bin/devbot` end-to-end file.
