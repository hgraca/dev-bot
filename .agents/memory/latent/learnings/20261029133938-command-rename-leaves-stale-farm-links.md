---
date: 2026-10-29
keywords: ["devbot", "command", "symlink", "reinit", "farm"]
aliases: ["rename command leaves dangling link", "stale command farm", "prune command symlinks"]
---

# Renaming or removing a module command leaves a dangling farm link

`_link_commands` (`src/tools/devbot-cli/functions.sh`) iterates each module's source `commands/*.md` and creates or relinks `.agents/commands/devbot/<bare>.md` from the frontmatter `name:`. It never enumerates the target directory, so a command that is renamed or deleted leaves its old link behind, pointing at a file that no longer exists. Both harnesses then keep listing the old slash command.

`devbot init` alone does not fix it — it runs the same add/relink-only function. `devbot reinit` does: its reset scripts delete every symlink under `devbot_dir/{agents,commands,skills,tools}` (`src/tools/devbot-cli/reset.sh`) and prune dev-bot and broken links under `.opencode/` (`src/harnesses/opencode/reset.sh`) before init rebuilds them. Auto-reinit will not fire either: it is keyed on the config hash, and a command rename does not change `.devbot.project.jsonc`.

## What to do after a command rename or removal

Run `devbot reinit` from the main checkout after the change merges, in the same session where you would otherwise stop. Verify the old bare name is gone from `<devbot_dir>/commands/devbot/` and that the new one resolves.

## Coverage gap

`src/tools/devbot-cli/tests/devbot_tests.bats` asserts that every source command has a correctly-targeted link, but never that no extra or dangling links exist. So a rename or removal leaves the farm broken while the suite stays green. Closing it means asserting every link resolves (`[ -e ]`) and that the link set equals the source set — or having `_link_commands` sweep links whose targets are gone.
