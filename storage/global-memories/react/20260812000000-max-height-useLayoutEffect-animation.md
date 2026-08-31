---
date: 2026-08-12
keywords: ['react', 'height-animation', 'max-height', 'useLayoutEffect']
trigger-on: ['smooth-height-transition', 'auto-height-animation']
---

## Smooth height animation for dynamic content using max-height + useLayoutEffect

CSS cannot transition `height: auto`. To animate height changes when React content swaps (e.g., switching between two panels with different amounts of content), use `max-height` with `overflow: hidden` and `transition: max-height 0.3s ease`. In a `useLayoutEffect` (fires after DOM mutation but before paint), capture the previous scrollHeight via a ref, set `max-height` to the previous value, force layout with `el.offsetHeight`, then set `max-height` to the new `scrollHeight`. On first render set `max-height: 'none'` to show full content without animation. The browser animates between the two explicit max-height values.
