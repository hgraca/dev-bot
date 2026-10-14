---
name: devbot:create-todo
description: "Use when the user asks to create a TODO or capture an unplanned task for later. Triggers on 'create a TODO', 'add a TODO', 'note this for later', 'add this to the backlog'."
---

# Create TODO

Capture a TODO as a **work item** — a folder under the memory vault's `work/todo/` — so the intent survives the session. This is the capture step only: it records what to do and defers how to plan and build it.

## When to Apply

- The user asks to create, add, or capture a TODO ("create a TODO for X", "note this for later", "add this to the backlog").
- Work surfaces mid-session that is out of the current scope but worth keeping.

## Scope

A TODO work item is the same artifact `devbot:make-plan` produces and `devbot:implement-story` promotes — this skill only writes the minimal capture, it does not plan. Hand off to `devbot:make-plan` when the user wants the work planned, and let it reuse the folder this skill created rather than starting a second one.

## Procedure

1. **Resolve the target project.** Default to the project this session runs in. When the user names another project ("in project X"), target that project's vault and route per `devbot:memory-management` § "Supervisor sessions".
2. **Reuse before creating.** List `<project>/.agents/memory/work/todo/` and `.../active/`. If a work item already covers this TODO, reuse it — never create a second folder for the same thing.
3. **Create the work-item root** at `<project>/.agents/memory/work/todo/<work-item-root>/`, naming the folder per the vault's work-item convention. The pattern and its rules are defined once in `devbot:make-plan` § "Folder naming" — follow it there, do not restate it here.
4. **Write the note** to `<work-item-root>/backlog.md` — the filename `devbot:make-plan` uses. Keep it a capture: a title, `**Status**: DRAFT`, a one-paragraph **Brief** of the TODO, and any acceptance criteria or notes the user gave. Do not enumerate tasks or technical actions.
5. **Confirm** to the user what was captured and in which project.

## MUST

- Route the item to the project the TODO concerns; a named project wins over the session's own.
- Reuse the existing work-item folder for the same TODO instead of creating a duplicate.
- Keep `backlog.md` a capture — leave decomposition, technical actions and critic review to `devbot:make-plan`.

## MUST NOT

- Do not restate vault structure, the work-item lifecycle, or folder naming here — `devbot:memory-management` § 1 (structure, lifecycle, commit status) and `devbot:make-plan` (folder naming, backlog format) are the single sources of truth.
- Do not `git add`, stage or commit the work item — `work/` is gitignored local scratch.
- Do not move the item to `work/active/` — the start transition belongs to `devbot:implement-story` and `devbot:reconcile-work`.
