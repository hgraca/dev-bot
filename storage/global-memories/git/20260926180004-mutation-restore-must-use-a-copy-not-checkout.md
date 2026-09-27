---
date: 2026-09-26
keywords: ["git", "mutation-testing", "checkout", "uncommitted"]
trigger-on: ["mutation-testing-restore"]
---

## Restoring a mutated file with `git checkout -- <file>` destroys uncommitted work in it

To prove a test has teeth, mutate the source temporarily, run the test, then restore. Restoring with `git checkout -- <file>` restores from **HEAD**, not from the pre-mutation working tree — so if that file also carried uncommitted changes (a fix written but not yet committed), they are destroyed silently, and the suite can afterwards go green while testing code you did not intend to ship. Verified the hard way: a mutation-check restore wiped an uncommitted refactor out of `src/tui/index.ts`, and the full suite still passed because the tests did not pin the removed behaviour, so the loss was invisible until the file was re-read. Copy the file aside first (`cp <file> /tmp/…`) and restore from that copy, or capture a patch (`git diff -- <file> > /tmp/x.patch`) and reapply; and treat any green suite that follows a restore as unverified until the file's content is confirmed against what was intended.
