---
date: 2026-08-18
keywords: ["opencode", "format-md", "rebase", "file.edited", "prettier"]
trigger-on: ["format-md-hook", "rebase-conflict-resolution"]
---

## format-md hook fires on edit-tool conflict resolution and can silently drop style commits

Resolving a rebase conflict with the `edit` tool triggers the `on-file_edited-format-md` hook, which runs prettier over the whole .md file inside the rebase. If the conflict is a docs hunk and the rebase includes a later `style: format markdown` commit whose changes are now already applied, that commit replays as empty and git drops it — the formatting silently merges into the earlier content commit. Net history can lose a commit the user expected to keep. Either resolve docs conflicts with bash/python instead of the edit tool, or expect the style commit to vanish and re-verify the tree hash afterwards.
