---
date: 2026-09-20
keywords: ["devbot", "skills-farm", "storage", "signoz", "sentinel"]
---

# `storage/<module>/skills` is not an opt-in — the `.devbot-generated` sentinel is

`_link_skills` (`src/tools/devbot-cli/functions.sh`) links a module's farm entry to `<DEV_BOT_ROOT>/storage/<module>/skills` **only when that dir carries a `.devbot-generated` sentinel**. Preferring it on mere directory existence is a trap: `signoz` already writes 13 skills to `storage/signoz/skills` and wires them opencode-only via `.opencode/skills/signoz` (`src/agentic/signoz/init.sh`), so an existence-keyed preference farms them a second time on `.agents/skills/devbot/signoz` — and opencode then logs `duplicate skill name` for each one. The claudecode flatten (`src/harnesses/claudecode/init.sh`, `_has_generated_skill_override`) follows the same sentinel rule so both harnesses agree. Rule: any future machine-local skill store must write the sentinel to be farmed; never key the preference on the directory alone.
