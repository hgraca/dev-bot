---
name: devbot:thinking
description: "Use when creating temporary files, drafts, or WIP notes. Triggers on 'scratch file', 'temp file', 'draft', 'WIP'."
---

# Thinking -- Scratch Files & Drafts

All ephemeral scratch files, notes, drafts, or WIP content produced during session (not formal artifact) must be saved to `<proj>/.agents/memory/thinking/`. Do not create temporary ad-hoc files elsewhere.

## When to Apply

- Creating any temporary file, ephemeral note, draft, or WIP content
- Saving partial-progress checkpoints before context overflow
- Deciding whether a draft has lasting value, and where it belongs

## 1. Naming

| Content                     | Filename                                |
| --------------------------- | --------------------------------------- |
| General scratch / draft     | `<descriptive-name>.md`                 |
| Partial-progress checkpoint | `YYYY-MM-DD-HH:MM:SS-<task>-partial.md` |

## 2. Lifecycle

This skill creates the files; two wrap-up skills end them, one concern each:

- **Promotion is `devbot:remember-session`'s** — it moves a file's lasting value (decision, pattern, gotcha) into the appropriate `latent/` note. Never promote from here.
- **Deletion is `devbot:reconcile-work`'s** — at session end it removes the `thinking/` files this session wrote. It never deletes a file the session did not write; one it cannot attribute is reported, not removed.
- **A file older than 7 days that no live session owns** is reported for the user to decide. Promote or delete is their call, never yours.

`devbot:memory-management` section 7 carries the full rules.
