---
date: 2026-11-27
keywords:
  ["git", "gh-pr-checks", "required-checks", "merge-gate", "false-green"]
aliases:
  [
    "--until green lies",
    "required check not started",
    "green before CI registered",
  ]
---

## `gh pr checks --required` omits a required check that has not started yet

`gh pr checks --required` selects from the check contexts that already exist on the commit, so a required
check that has not been created yet is simply absent — not reported as pending, absent. Immediately after
a push the answer is therefore "everything I can see passes", which a gate that treats it as "all required
green" reads as a green build.

Observed on `GET-E/dev-bot#222` (2026-11-27): branch protection required `lint` and `test`; seconds after a
force-push `--required` listed only `lint` and said `pass`, while the `test` job (which waits for three
test slices) had not been created at all. A wait built on `--required` returned success in the first poll;
the same PR turned red later when `test` ran and failed.

The complete declaration lives outside the pull request: `repos/{repo}/branches/{branch}/protection`
(`contexts` plus `checks[].context`) and the repository's rulesets (`rules[type=required_status_checks]`,
paginated, filtered to active branch rules that match the base ref). Compare that set against the reported
check names and wait for every declared context to appear, not for the visible ones to pass. An unreadable
declaration must stay unknown — never green — because "cannot tell" and "nothing required" are the same
answer only to a gate that would rather be wrong.
