---
date: 2026-08-12
keywords: ['react', 'height-animation', 'useLayoutEffect', 'scrollHeight']
trigger-on: ['smooth-height-transition', 'auto-height-animation', 'content-switch-height']
---

## Height animation with useLayoutEffect + scrollHeight + CSS transition

CSS cannot transition `height: auto`. To animate height changes when content changes in React, use `useLayoutEffect` (fires after DOM mutation, before paint) with `[contentDependency]`. Store the previous `scrollHeight` in a `useRef`. On content change: set `el.style.height = prevHeightRef.current + 'px'` (locks at old height), force layout with `el.offsetHeight`, then set `el.style.height = newScrollHeight + 'px'`. Both changes happen synchronously in useLayoutEffect before the browser paints, so the CSS `transition: height 0.3s ease` animates between them. Use `height` (not `max-height`) for both expand and contract — `max-height` doesn't constrain actual height during contraction and produces no visual effect. Wrap the content in a div with `overflow: hidden` to clip during the animation.
