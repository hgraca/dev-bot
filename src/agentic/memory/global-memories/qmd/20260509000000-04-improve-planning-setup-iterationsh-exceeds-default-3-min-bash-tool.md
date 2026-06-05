---
date: 2026-05-09
keywords: ["qmd"]
---

## `improve-planning` setup-iteration.sh exceeds default 3-min bash tool timeout

Running `bash src/skills/self-improvement/improve-planning/scripts/setup-iteration.sh "<model>"` from the orchestrator's bash tool with the default 120s/180s timeout silently kills the script mid-run. The `devbot init` step alone takes ~60s (qmd index build dominates) and the full script wall-clock is ~90-120s on a warm machine, longer on cold. When killed, the script's EXIT trap does NOT fire (SIGKILL bypasses traps) so the partial iteration folder is left behind — `metadata.json` absent, `opencode.jsonc` still a symlink, agent frontmatter unpatched. The orchestrator must then manually `rm -rf storage/self-improvement/improve-planning/iteration-N/` per the SKILL's "Setup script failure recovery" before retrying. **Fix**: invoke the script with `timeout: 600000` (10 min) on the bash tool call AND redirect stdin from `</dev/null` so any stray interactive prompt fails loudly instead of hanging forever. Confirmed iter-12 setup 2026-05-09: first attempt with default timeout was killed at 180s after creating the folder but before materialising opencode.jsonc; rolled back and retried with 600s timeout + `</dev/null`, completed in ~90s. See [[memories]] for the iteration-setup lesson and `src/skills/self-improvement/improve-planning/SKILL.md` Step 1 for the affected invocation.
