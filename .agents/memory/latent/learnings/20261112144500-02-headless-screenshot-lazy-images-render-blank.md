---
date: 2026-11-12
keywords: ["headless-chrome", "screenshot", "lazy-loading", "docs-site", "verification"]
---

# Headless screenshots render `loading="lazy"` images as blank cards

`google-chrome --headless=new --screenshot` captures before `loading="lazy"` images below the initial paint are fetched, so they show as empty boxes. Because the `<img>` carries `width`/`height` attributes, the white card still has the correct dimensions — which reads as a broken layout, not a missing image.

`--virtual-time-budget` alone was not reliable for the large diagrams on this repo's landing page: a 4416×4352 PNG stayed blank across captures while a 2016×5024 one in the same capture rendered. What worked:

- add `--virtual-time-budget=20000 --run-all-compositor-stages-before-draw`;
- for a faithful capture, strip the attribute from the **built** page first and rebuild afterwards:

```bash
sed -i 's/ loading="lazy"//g' docs/_site/index.html
```

Never strip it from the source — lazy is correct for a landing page whose diagrams sit below the fold.

Related: `learnings/20260918064354-docs-site-visual-verification-without-devtools-mcp.md` (the base recipe) and `learnings/20260924234656-01-headless-screenshot-tiling-looks-like-a-layout-bug.md` (window sizing).
