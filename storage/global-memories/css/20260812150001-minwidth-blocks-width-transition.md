---
date: 2026-08-12
keywords: ['css', 'transition', 'minWidth', 'width']
trigger-on: ['css-width-transition-minwidth', 'panel-slide-animation']
---

## minWidth prevents smooth CSS width transition

When animating a panel from `width: 0` to `width: 650px` using `transition: width 0.3s ease`, adding `minWidth: show ? 650 : 0` causes the panel to snap to full width instantly instead of sliding. Root cause: `minWidth` changes immediately on state toggle, and browsers prioritize `minWidth` over the `width` transition. Fix: remove `minWidth` entirely — rely only on `width` with `transition` for smooth animation. Combine with `overflow: hidden` to hide content during the transition.
