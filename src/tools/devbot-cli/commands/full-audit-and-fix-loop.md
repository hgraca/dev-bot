---
name: devbot:full-audit-and-fix-loop
description: Audit, fix and locally review in a worktree, then open a PR and work the Copilot loop.
---

Fully autonomous: no check-ins, no questions. Run the steps in order and stop only on a stop
condition below.

1. **Gate — Claude must be able to authenticate unattended.** Run `claude auth status` and read its
   JSON. Stop before anything else, loudly, when `loggedIn` is false **or** when `authMethod` is not
   `oauth_token`: an interactive login expires mid-run and cannot be renewed headlessly, which is how
   an overnight audit dies hours in. The fix is `claude setup-token`, then export
   `CLAUDE_CODE_OAUTH_TOKEN` in the shell that runs the loop. Never substitute another credential or
   another identity to get past this gate.

2. **Create the worktree from local `main`.**

   ```bash
   bash "$DEV_BOT_ROOT/src/agentic/git/tools/worktree.sh" create \
     "full-audit-$(date +%Y%m%d-%H%M%S)" --base main
   ```

   It prints the worktree path. Every later step runs there: edits use its absolute paths, git
   commands use `git -C <worktree>`.

3. **Loop — audit both harnesses in parallel, fix, review.** Repeat until the pair is clean. Do not
   start a new round once the session is above 70% — finish the round in hand, then go to step 4:

   1. `make audit` — `tests/test-project/full-audit.sh [<branch>]` — runs the cc and oc
      headless audits **in parallel** against this checkout (`DEV_BOT_TEST_LOCAL_SRC` defaults to
      the repo root, so the worktree under review is the tree audited) and gates on the reports. It exits `0` only when both
      reports landed with no `FAIL` row, `1` while printing the FAIL rows, and `2` when a
      report is missing or a launcher failed. Sonnet is the audit default
      (`DEVBOT_TEST_CLAUDE_MODEL` overrides it): haiku fabricated findings in two
      consecutive rounds — FAILs its own logs contradicted, then a fabricated PASS.
   2. **Both reports must land before anything is fixed.** A harness-specific defect shows
      up in one report and not the other, so a single report cannot tell "clean" from "not
      audited". Exit `2` is a stop for the human, never a retry until it turns green.
   3. `/devbot:audit-fix` once per report in the pair — it reads the latest report, so name the
      file — and address the union. It owns what "address" means.
   4. Local review loop: `devbot:review-implementation`, then delegate the changeset to
      `@reviewer` and address each finding with `devbot:address-review` — fixing in place,
      then re-reviewing — until a review introduces no new findings.

4. **Open the pull request** with `devbot:gh-create-pr` once the loop is clean — in its automatic
   form: take yes at its local-review gate, state the plan instead of waiting for approval, and let
   it request the Copilot review and start the loop. This command may not ask, and that is the one
   place the loop starts. Never push the default branch, never merge.

5. **Carry the loop that step 4 started to its gate.** Do not start a second one:
   `devbot:gh-review-loop` owns the request/wait/read/fix cycle, the resolve protocol and the
   required-check gate, and the automatic run in step 4 entered it. See it through until a review
   introduces no new findings and the required checks are green, then stop one step before the merge:
   squash the fixups and hand the human the exact `git push --force-with-lease` command.

**The hand-off names what is still open.** Alongside the pull request and the push command, report
what the last reports still named that would have warranted another round — the `FAIL` rows verified
as design intent, the NOTEs left standing, the stop condition that ended the loop (budget, unlanded
report, a decision only the human can make). A hand-off that says "clean" without that list reads as
"nothing left to do", and the next session re-derives it from reports nobody wrote down.

**Stop conditions** — report the condition, the evidence and the branch, then stop:

- the auth gate in step 1 fails;
- the audit pair cannot land (exit `2`) — a missing report or a failed launcher is a stop, not a
  retry until it turns green;
- session context goes above 70% (`make audit` exits `3` on it; an unmeasurable session prints
  `usage unknown` and continues, so the rule is a gate only where the number exists) **before a new
  round starts**: this
  is not the end of the work — open the pull request, work the review loop, squash the fixups, and
  hand off (steps 4–5). A round that runs out of context mid-fix leaves the branch half-addressed
  with nobody to finish it, which is what the budget prevents;
- a round's `FAIL` rows are verified as design intent or false findings: record "verified, no
  change" for each and finish the round rather than looping on a report the code already satisfies;
- the pull request is `CONFLICTING` or `DIRTY`, or a required check fails for a cause the loop cannot
  fix;
- a step needs a decision only the human can make (a product question, a credential, a destructive
  operation).
