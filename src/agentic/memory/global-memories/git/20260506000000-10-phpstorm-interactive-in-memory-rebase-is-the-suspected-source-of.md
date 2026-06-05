---
date: 2026-05-06
keywords: ["git", "commit", "blob", "corruption"]
---

## PhpStorm "interactive in-memory rebase" is the suspected source of blob corruption — disable it

Both blob-corruption events this session correlate with `interactive in-memory rebase by PhpStorm Git plugin: updating HEAD` reflog entries — visible via `git reflog | grep "PhpStorm"`. Mechanism (suspected): PhpStorm's in-memory rebase rewrites trees and updates the index referencing newly-computed blob SHAs without flushing the corresponding blob objects to `.git/objects/` before `HEAD` is moved. If the IDE crashes, the user cancels mid-rebase, or any FS hiccup occurs, the index ends up pointing to blobs that were never written — exactly the `error: invalid object … Error building trees` failure. **Additional symptom**: PhpStorm may auto-attempt `git cherry-pick` to recover, which fails with `error: could not parse '<sha>'` / `unusable instruction sheet: '.git/sequencer/todo'` because the cherry-pick references the same broken commits. Recovery: `rm -rf .git/sequencer` to clear the failed cherry-pick state, then proceed with L1042 / L1050 recovery. **Operational rule**: in PhpStorm, prefer `git rebase -i` from the terminal over the IDE's "Interactively rebase from here" — or at minimum, run `git fsck --no-dangling` immediately after every IDE-driven rebase to catch corruption before more commits land on top. Cross-ref L1027, L1042, L1050. See [[memories]].
