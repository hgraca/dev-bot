---
date: 2026-09-21
keywords: ["devbot", "format-json", "hook", "prettier", "composer.json"]
trigger-on: ["format-json-hook", "edit-json-file"]
---

## The format-json hook reformats edited JSON to prettier defaults

Editing any `.json` / `.jsonc` file through the agent's edit or write tool triggers the devbot `format-json` hook, which runs prettier with no project config — so the file is rewritten to 2-space indentation with short arrays collapsed inline. A `composer.json` that was deliberately normalised to a 4-space style (Laravel's default, and what a target branch may use) is silently reverted, and because the hook is asynchronous the rewrite lands after the edit returns — visible only as unexpected content on the next read or diff. Budget for this churn: either accept prettier's 2-space for that file, or produce the final content through a channel the hook does not wrap (for example a shell script writing the file) when a particular style must survive.
