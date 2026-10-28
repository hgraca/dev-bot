---
date: 2026-10-28
keywords: ["git", "force-with-lease", "rebase", "push"]
aliases: ["non-fast-forward after rebase", "force-with-lease refname form", "stale lease"]
---

## A fully-qualified `--force-with-lease=<ref>:<sha>` can leave the push unforced

After rewriting a branch with `git rebase --onto`, this was rejected as a plain non-fast-forward
rather than a lease mismatch:

```bash
git push --force-with-lease=refs/heads/my-branch:<sha> origin my-branch
! [rejected] my-branch -> my-branch (non-fast-forward)
```

The remote was exactly `<sha>`, so the lease value was correct. The flag simply did not apply to the
pushed ref: with a bare refspec (`origin <branch>`, no explicit `:<dest>`), git resolves the
destination while building the push, and the fully-qualified `<refname>:<expect>` form can end up not
associated with it — the push then runs unforced.

Use the bare form, which keys the lease off the remote-tracking ref, or the short branch name:

```bash
git push --dry-run --force-with-lease origin my-branch            # expect: Would force-update ...
git push --force-with-lease origin my-branch
git push --force-with-lease=my-branch:<sha> origin my-branch      # alternative
```

Always `--dry-run` first: it prints `Would force-update <old>...<new>` when the force is actually
going to happen, so a mis-parsed lease is caught before it costs a round trip. Do **not** add
`--force-if-includes` after a `rebase --onto` — the old tip is no longer an ancestor, and that flag
rejects exactly the rewrite you are trying to publish.
