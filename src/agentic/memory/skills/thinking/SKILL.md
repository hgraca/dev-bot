---
name: thinking
description: "Scratch files, drafts, and WIP content management. Use this skill whenever creating temporary files, ephemeral notes, partial-progress checkpoints, or any non-formal artifact during a session. Triggers on 'scratch file', 'temp file', 'draft', 'WIP', 'partial progress'."
---

# Thinking -- Scratch Files & Drafts

All ephemeral scratch files, notes, drafts, or WIP content produced during session (not formal artifact) must be saved to `<proj>/.agents/memory/thinking/`. Do not create temporary ad-hoc files elsewhere.

## When to Apply

- Creating any temporary file, ephemeral note, draft, or WIP content
- Saving partial-progress checkpoints before context overflow
- Deciding whether to promote or delete existing scratch files

## 1. Naming

| Content                     | Filename                                |
| --------------------------- | --------------------------------------- |
| General scratch / draft     | `<descriptive-name>.md`                 |
| Partial-progress checkpoint | `YYYY-MM-DD-HH:MM:SS-<task>-partial.md` |

## 2. Lifecycle

After task completes or session ends:

1. **Promote**: If file contains lasting value (decision, pattern, gotcha), move content to appropriate latent/ note.
2. **Delete**: Remove files that add no lasting value.
3. **Flag**: Any `thinking/` file older than 7 days should be reviewed -- promote or delete.

See `memory-management` skill (section 7) for full lifecycle rules.
