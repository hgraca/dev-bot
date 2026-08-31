---
date: 2026-08-12
keywords: ['css', 'flex', 'alignSelf', 'stretch']
trigger-on: ['flex-child-zero-height', 'align-self-stretch-panel']
---

## Flex child has zero height when parent uses align-items: flex-start

When a flex container has `align-items: flex-start`, children that rely on `flex: 1` for height (e.g., a side panel containing a Leaflet map with `height: 100%`) collapse to zero height because the cross-axis doesn't stretch. The Leaflet map renders in the DOM but is invisible (0px tall). Fix: add `alignSelf: 'stretch'` to the child that needs to fill available height. This overrides the parent's `align-items` for that specific child, allowing `flex: 1` to work correctly in the cross-axis.
