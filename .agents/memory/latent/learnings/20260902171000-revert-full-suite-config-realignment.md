---
date: 2026-09-02
keywords: ["devbot", "external-modules", "revert", "make-test", "config"]
---

# Reverting a cross-cutting feature: full suite plus runtime-config realignment

Reverting the org/repo namespaced external-modules machinery back to named
imports (2026-09-02, commits `715e19a6` + `6cebf512`) showed that restoring
only the obvious module files is not enough:

- Targeted greps (provenance keys, storage-mirror names) and the scoped BATS
  files were all green, yet the full `make test` caught feature-era residue in
  unexpected places: the devbot-cli scaffold e2e asserted the nested
  namespaced `.agents/.../org/repo` links (`src/tools/devbot-cli/tests/devbot_tests.bats`)
  and `/devbot:audit` docs referenced namespaced wiring
  (`src/tools/devbot-cli/commands/audit.md`). Run the FULL suite after any
  cross-cutting revert — feature tests hide in files the diff stats don't
  suggest.
- The gitignored runtime config `.devbot.global.jsonc` still carried the
  namespaced entries (and `_declared_by` provenance). Restored code + restored
  tests expect named keys, so the e2e scaffold test failed until the config's
  `external_modules` block was realigned by hand to the restored declarations
  (`addyosmani`, `mattpocock-grilling`). Machine-local config is part of the
  revert surface even though git never sees it.
- Tooling breadth regressed with the code: origin's `merge_modules_jsonc.py`
  is insert-only — the `--remove` mode was feature-era — so config cleanup
  cannot go through the merge script and must be a direct JSONC edit.

Pattern for future reverts: restore module files AND their test/docs stragglers
(verified by full suite, not grep), realign any runtime config the reverted
code wrote, then re-run `make test` to green.
