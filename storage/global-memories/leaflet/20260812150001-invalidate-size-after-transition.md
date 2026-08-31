---
date: 2026-08-12
keywords: ['leaflet', 'invalidateSize', 'transition', 'tiles']
trigger-on: ['leaflet-transition-resize', 'leaflet-panel-slide']
---

## Leaflet tiles load incorrectly when container size changes via CSS transition

When a Leaflet map initializes inside a container that's undergoing a CSS `width` transition (e.g., sliding panel from 0 to 750px), tiles load for the intermediate viewport size and appear missing/incomplete after the transition finishes. Fix: call `map.invalidateSize()` after the transition completes. Use a `useEffect` watching the map's `ready` state with a `setTimeout` slightly longer than the transition duration (e.g., 400ms for a 300ms transition) to trigger tile reload at the final container size.
