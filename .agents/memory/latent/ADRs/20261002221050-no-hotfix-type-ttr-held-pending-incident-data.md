---
date: 2026-10-02
keywords: ["conventional-commits", "hotfix", "mttr", "time-to-recovery", "forensics"]
see: ["ADRs/20260923120500-git-commits-shared-craft-skill.md"]
---

## No `hotfix` commit type; git-only time-to-recovery is held until incident data exists

A proposal to add a `hotfix(<regression-sha>)` Conventional Commit type — the scope holding the short hash of the commit that introduced the regression, so `src/agentic/forensics` could compute a git-only **time to recovery** — was implemented on the branch and then dropped before release. The metric `regression-commit → hotfix` measures _defect introduction → fix_, not outage duration: a regression shipped Monday that only breaks on Thursday would report days, though the outage lasted minutes. True MTTR measures incident start → service restored and needs incident/deploy data the git-only forensics path does not have, which is why three forensics docs already declared it out of scope. So `git-conventional-commits` keeps its original taxonomy with `fix` = "bug fix for the user", and forensics keeps SZZ `time-to-fix` (defect origin → fix) as its only commit-to-commit duration. Revisit the hotfix type only when incident data can anchor the recovery start.
