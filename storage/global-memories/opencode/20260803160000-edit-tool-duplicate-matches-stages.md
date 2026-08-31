---
date: 2026-08-03
keywords: ['opencode', 'edit', 'jsx', 'sourcing']
trigger-on: ['edit-tool-duplicate-jsx']
---

## Edit tool fails with duplicate matches when stage panels share identical JSX

When using the edit tool on a file where multiple stage panels contain identical JSX
(e.g. SourcingProjectDetail.tsx with Shortlist and AWC panels), the `oldString`
must include enough unique surrounding context to disambiguate. Include the stage
name check (e.g. `selectedStage === 'Awaiting Client Decision'`) or other unique
lines in the `oldString`. Without this, the edit tool reports "Found multiple matches."
