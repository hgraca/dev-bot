---
date: 2026-05-16
keywords: ["ripgrep", "folder-ranking", "merge", "canonical", "prefix", "scoring"]
---

## Keyword-prefix canonical folder merge for folder-ranking tools

When ranking folders by keyword relevance, raw per-folder counts produce noisy results:
parent and child folders both appear separately, diluting the signal. Solution: two-pass
collapse into canonical keyword-prefix folders.

**Algorithm (two passes):**

**Pass 1** — collapse raw folders into keyword-prefix canonical:

1. For each folder, find the **shortest** prefix segment containing any keyword.
2. Accumulate raw counts into that canonical target.
3. Non-bonus folders remain unchanged.

**Pass 2** — collapse canonical children into canonical ancestors (loop until stable):

- If canonical folder A is a strict path-prefix of canonical folder B, merge B into A.
- Handles cases where two keywords appear at different depths in the same path.

```python
def keyword_prefix(folder: str, kw: str) -> str | None:
    parts = folder.replace("\\", "/").split("/")
    for i, part in enumerate(parts):
        if kw.lower() in part.lower():
            return "/".join(parts[:i + 1])
    return None

def canonical_folder(folder: str) -> str:
    # Pick shortest prefix across all keywords (not first-keyword-wins)
    best = None
    for kw in keywords:
        prefix = keyword_prefix(folder, kw)
        if prefix is not None and (best is None or len(prefix) < len(best)):
            best = prefix
    return best if best is not None else folder

# Pass 1
merged_scores = defaultdict(lambda: {"total": 0, "keywords": defaultdict(int)})
for folder, data in folder_scores.items():
    target = canonical_folder(folder)
    merged_scores[target]["total"] += data["total"]
    for kw, cnt in data["keywords"].items():
        merged_scores[target]["keywords"][kw] += cnt

# Pass 2 — ancestor collapse (repeat until stable)
def find_ancestor(folder, candidates):
    parts = folder.replace("\\", "/").split("/")
    best = None
    for i in range(1, len(parts)):
        prefix = "/".join(parts[:i])
        if prefix in candidates and prefix != folder:
            best = prefix
    return best

changed = True
while changed:
    changed = False
    keys = set(merged_scores.keys())
    for folder in list(merged_scores.keys()):
        ancestor = find_ancestor(folder, keys)
        if ancestor is not None:
            merged_scores[ancestor]["total"] += merged_scores[folder]["total"]
            for kw, cnt in merged_scores[folder]["keywords"].items():
                merged_scores[ancestor]["keywords"][kw] += cnt
            del merged_scores[folder]
            changed = True
            break
```

**Gotcha:** `canonical_folder` must pick the **shortest** prefix, not first-keyword-wins.
`Core/Port/Erp/BillingBackfill` hits `Erp` at depth 3 and `billing` at depth 4 —
shortest wins → `Core/Port/Erp`. First-keyword-wins gives wrong result when keyword
order differs from path depth order.

**Effect:** `Core/Component/Billing/Application/Service` and
`Core/Component/Billing/Application/UseCase/Backfill` both collapse to
`Core/Component/Billing`. `Core/Port/Erp/BillingBackfill` collapses to `Core/Port/Erp`
via pass 1; pass 2 then checks if `Core/Port/Erp` is a child of any other canonical
(it isn't, so it stays).

Combine with 3x path-bonus scoring so merged canonical folders rank above
high-volume generic folders.

Reference: `ripgrep-report.sh` (commits `a265c68`, `1490c93`). Cross-ref [[20260516164800-bash-tool-markdown-output-align-via-format-md-tmp-file]].
