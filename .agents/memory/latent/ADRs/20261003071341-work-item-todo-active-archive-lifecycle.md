---
date: 2026-10-03
keywords: ["devbot", "work item", "memory vault", "lifecycle"]
aliases: ["todo active archive", "work folder states", "work item state machine"]
---

## Work items move through todo → active → archive

Decision: a memory-vault work item — a `<timestamp>-NN-<slug>/` folder under `.agents/memory/` — has three states. `devbot:make-plan` creates it in `work/todo/` (planned, not started), `devbot:implement-story` promotes it to `work/active/` when implementation starts (the "start" transition is its Step 0.1), and completion archives it to `work/archive/YYYY/MM/<work-folder>/`. The lifecycle unit is the **work-item root** — the top-level folder directly under `work/<state>/`: on the epic path that is the epic folder (story sub-folders are nested inside it and move with it, so a per-story run must not archive them; the epic root is archived once at epic completion), on the story path the folder itself. `devbot` (pair-programmer) persists its PLAN to `todo/`, promotes on entering BUILD, and archives at the finish flow. Trivial work — which has no planning phase — creates its folder directly in `active/`, the single documented exemption from "born in todo". Moves are prose instructions to the agent (no mover tool); `work/` stays gitignored local scratch. Verified by review fixups on `release/v1.7` after a @reviewer BLOCKER over the epic-path root.
