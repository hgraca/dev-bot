---
name: devbot:improve-reviewing
description: Iterate on how the @reviewer reviews change sets, to improve the process
---

Follow the `devbot:improve-reviewing` skill to improve the devbot @reviewer from the issues this
session's code review loop found — the ones the devbot @reviewer did not catch (Copilot's, or any
other reviewer's).

- collect the issues the session's review loop flagged, and keep the ones our reviewer should have
  caught but does not already cover
- generalize each into an issue type with the check that would have caught it
- land the change in the dev-bot repository — `reviewer.md` for behaviour,
  `review-implementation/SKILL.md` for what the reviewer inspects — in a linked worktree of its own
- open a pull request describing each gap, so the next changeset is caught before its pull request
