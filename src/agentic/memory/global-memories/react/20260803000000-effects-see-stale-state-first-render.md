---
date: 2026-08-03
keywords: ['react', 'useEffect', 'state', 'fetch']
---

## React effects run with stale state — first render localHotels is empty

On component mount, `localHotels` starts at its initial value (`[]`). Effects run after first render with this empty value. Even though the API effect calls `setLocalHotels([5])` in the same effect batch, the fetch effect runs in the SAME batch and still sees `localHotels = []`. React batches state updates within effects but doesn't apply them between effects in the same batch.

**Fix**: Guard the fetch effect against both the in-memory state AND persisted data (localStorage/API). The persisted data is available synchronously even on first render, unlike React state which is only updated after commit.
