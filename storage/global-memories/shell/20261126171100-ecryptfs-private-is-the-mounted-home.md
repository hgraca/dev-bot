---
date: 2026-11-26
keywords: ["shell", "du", "ecryptfs", "disk-usage"]
aliases: [".Private", "encrypted home", "du double count"]
---

## /home/.ecryptfs is the backing store of the mounted home — never delete it to reclaim space

A `du -x` of `/home` reports `/home/.ecryptfs` (428G on this box) next to `/home/<user>` (467G), which reads like a duplicated copy and an obvious reclaim. It is not: `/home/.ecryptfs/<user>/.Private` is mounted _as_ `/home/<user>` via eCryptfs, so those are the same bytes counted twice — one ciphertext, one plaintext view. Deleting `.ecryptfs` destroys the home directory. Confirm with `mount | grep ecryptfs` before touching anything that looks like a duplicate; size the home once with `du -sh ~` and never add `.ecryptfs` on top of it when totalling a partition.
