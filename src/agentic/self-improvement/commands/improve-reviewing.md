---
name: devbot:improve-reviewing
description: Iterate on how the @reviewer reviews change sets, to improve the process
---

Follow `devbot:improve-reviewing` skill to improve the devbot @reviewer, based on
this session reviews items that were not caught by the devbot @reviewer (maybe
they were caught by the GitHub Copilot review, or similar).

- make a list of all the issues that were flagged in the session code reviews
- categorize the issues by type (generalize), and give each different type a solution
- use the list of issue types and solutions to improve the devbot reviewer agent profile
  (`reviewer.md` — behaviour, workflow, tone) and the review skill
  (`review-implementation/SKILL.md` — what to inspect and flag), so that next time
  it will catch those issues immediately
