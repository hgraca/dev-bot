---
date: 2026-11-10
keywords: ["git", "force-with-lease", "refspec"]
aliases: ["stale info", "not a full refname", "unqualified push destination"]
---

## A raw SHA push source needs a fully qualified destination; the lease key must match it

`git push origin <sha>:<branch>` fails with "the destination you provided is not a full refname (i.e., starting with refs/)" when the source is a raw commit id — git cannot infer a namespace for the destination, and its hint is to write `refs/heads/<branch>`. Use `HEAD` as the source when the checkout is on the commit to publish. Separately, `--force-with-lease=refs/heads/<branch>:<sha>` can fail to associate with the refspec being pushed, and git then rejects with `! [rejected] ... (stale info)` instead of honouring the supplied expectation. Keep the lease key identical to the refspec destination — a short destination with a short key, or `refs/heads/` on both sides — and prefer `HEAD:<branch>` over a raw sha. A mismatched lease degrades to a plain non-fast-forward rejection, so the failure is safe, but it wastes a round trip and looks like a remote change.
