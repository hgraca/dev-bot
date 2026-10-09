---
date: 2026-10-09
keywords: ["finish-flow", "reconcile-work", "work-item", "work-folder", "archive"]
see: ["ADRs/20261003071341-work-item-todo-active-archive-lifecycle.md", "ADRs/20260822054558-remember-session-finish-flow-trigger.md"]
---

## The finish flow reconciles work folders via devbot:reconcile-work

The primary-agent finish flow is now three steps — `devbot:remember-session`, `devbot:grade-tools`, `devbot:reconcile-work` — before `[FINISHED]`. `reconcile-work` moves only the work items the session touched: a started-but-unfinished item goes to `work/active/`, a finished item to `work/archive/YYYY/MM/`, an item created or planned but never started stays in `work/todo/`, and untouched items are left alone. It emits no narrative (like the two steps before it), moves the work-item root (an epic's story sub-folders travel with it), and never stages `work/` (gitignored scratch). It exists because the `make-plan`/`implement-story` work-folder move is prose an agent can skip, stranding a started item in `todo/`; reconciling at wrap-up is the backstop. `todo/` means not-yet-started, not unfinished — so a merely planned item is not promoted to `active/`.
