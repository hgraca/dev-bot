---
name: devbot:reconcile-work
description: "Use when wrapping up to reconcile the work folders a session touched — started-but-unfinished work moves to work/active/, finished work to work/archive/YYYY/MM/. Runs as the primary finish flow's third step, after devbot:grade-tools."
---

# Reconcile Work

Align the `work/` vault with reality at the end of a session: every work item the session **started** ends up in `work/active/` (unfinished) or `work/archive/YYYY/MM/` (finished), so a skipped `make-plan` / `implement-story` move never leaves a started item stranded in `work/todo/`.

## When to Apply

- **Primary trigger**: the primary finish flow (see `devbot:agent-communication`), immediately after `devbot:remember-session` and `devbot:grade-tools`, before `[FINISHED]`.
- The user says "tidy the work folders", "reconcile the work items", or "archive the finished work".

## Scope

Reconcile only the work items **this session touched** — created via `devbot:make-plan`, promoted or edited via `devbot:implement-story`, or otherwise read or edited. Leave every untouched item in `work/todo/` and `work/active/` exactly where it is.

A **work-item root** is a top-level folder directly under `work/<state>/` (`YYYYMMDD-HHMMSS-NN-<slug>/`). An epic root carries its story sub-folders; moving the root moves them with it.

## Procedure

1. **List the touched work items.** From the session's own activity, collect the top-level `work/todo/` and `work/active/` folders this session created, started, or edited. If there are none, stop — there is nothing to reconcile.
2. **Classify each item** by its state this session:

   | Item state this session           | Action                                               |
   | --------------------------------- | ---------------------------------------------------- |
   | started, and now finished         | move to `work/archive/YYYY/MM/`                      |
   | started, still unfinished         | move to `work/active/` (from `todo/` if still there) |
   | created or planned, never started | leave in `work/todo/`                                |
   | already in `active/`, unfinished  | leave in `work/active/`                              |

3. **Decide "finished".** An item is finished when every acceptance criterion in its `backlog.md` is met and its work is committed and proven. When the state is genuinely ambiguous, ask the user which way it goes — do not guess.
4. **Move each item** with `mkdir -p <dest>` then `mv <src> <dest>`, preserving the folder name:
   - unfinished → `work/active/`
   - finished → `work/archive/YYYY/MM/`, using the **completion** year and month (`date +%Y/%m`).
5. **Stop.** On the finish flow emit no narrative — the flow is silent, exactly like `devbot:remember-session` and `devbot:grade-tools` (the sole exception is a question when an item's state is genuinely ambiguous).

## MUST

- Reconcile only work items this session touched; leave all others alone.
- Move the work-item **root**; never split a folder's files across states.
- Use plain `mkdir -p` + `mv` — `work/` is gitignored local scratch, never `git add` or commit it.
- Place new archives at `work/archive/YYYY/MM/`; never restructure existing archive layouts.
- Ask the user only when an item's finished / unfinished state is genuinely ambiguous.

## MUST NOT

- Do not reconcile or audit `work/` items the session never touched.
- Do not commit, stage, or push anything under `work/` (gitignored local scratch).
- Do not re-home existing `archive/` folders to the `YYYY/MM` shape.
