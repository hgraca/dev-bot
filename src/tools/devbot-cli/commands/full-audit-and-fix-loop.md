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

3. **Loop — audit, fix, review.** Repeat, at most three rounds:

   1. `/devbot:audit` in the worktree, then read the report it writes. The
      claudecode fixture already runs the audit on `haiku` by default; set
      `DEVBOT_TEST_CLAUDE_MODEL` to audit on another model.
   2. No `FAIL` row in that report → leave the loop.
   3. `/devbot:audit-fix` against that report. It owns what "address" means.
   4. Local review loop: `devbot:review-implementation`, then delegate the changeset to `@reviewer`
      and address each finding with `devbot:address-review` — fixing in place, then re-reviewing —
      until a review introduces no new findings.

4. **Open the pull request** with `devbot:gh-create-pr` once the loop is clean. Never push the
   default branch, never merge.

5. **Work the Copilot loop** with `devbot:gh-review-loop`. It owns the request/wait/read/fix cycle,
   the resolve protocol and the required-check gate. Stop one step before the merge: squash the
   fixups and hand the human the exact `git push --force-with-lease` command.

**Stop conditions** — report the condition, the evidence and the branch, then stop:

- the auth gate in step 1 fails;
- three rounds end with `FAIL` rows still in the report;
- the pull request is `CONFLICTING` or `DIRTY`, or a required check fails for a cause the loop cannot
  fix;
- a step needs a decision only the human can make (a product question, a credential, a destructive
  operation).
