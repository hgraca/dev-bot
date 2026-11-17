---
date: 2026-11-15
keywords: ["css", "oklch", "getComputedStyle", "contrast"]
aliases: ["contrast audit", "WCAG AA check", "colour parser returns null"]
trigger-on: ["contrast-audit", "computed-color-parsing"]
---

## Computed CSS colours come back as `oklch()`, so a regex parser silently fails

`getComputedStyle(el).color` returns the authored colour space, so on a daisyUI/Tailwind 4 page it is `oklch(0.977 0.007 106.5)` — not `rgb()`. An audit that parses `rgba?(…)` with a regex gets `null` and either throws or silently skips every element, which reads as "no contrast problems". Resolve each colour through a canvas instead: set `ctx.fillStyle = cssValue`, `fillRect(0,0,1,1)`, `getImageData(...)`, and read RGBA including alpha — it accepts any CSS colour and normalises it. Then composite the element's possibly-transparent colour over the nearest non-transparent ancestor background before computing the ratio, or a `text-base-content/70` will be measured as fully opaque and pass when it does not.
