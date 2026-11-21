---
name: devbot:find-automation-candidates
description: Mine the agent's session history for recurring command chains worth turning into a script
---

Follow the `devbot:find-automation-candidates` skill.

Sessions to examine, counting back from now: `$1`. When it is empty, use the
skill's default of 1000 and say so on the report's first line — do not guess a
count from the conversation, and do not ask.

If `$1` is present but not a positive integer, stop and say what was expected.
