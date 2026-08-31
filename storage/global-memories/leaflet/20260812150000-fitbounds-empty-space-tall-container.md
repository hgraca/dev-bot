---
date: 2026-08-12
keywords: ['leaflet', 'css', 'fitBounds', 'aspect-ratio']
trigger-on: ['leaflet-fitBounds-tall-container', 'leaflet-sidebar-map']
---

## Leaflet fitBounds leaves empty horizontal space in tall narrow containers

When using Leaflet's `map.fitBounds()` in a tall, narrow container (e.g., a 750px wide sidebar panel that stretches full viewport height), the map leaves ~10-25% empty space on the right. Root cause: `fitBounds` constrains the view to the marker bounding box, but the container's aspect ratio (tall/narrow) forces zoom-out to fit vertical bounds, leaving unused horizontal space. Fix: remove `fitBounds` entirely and use only `map.setView([lat, lon], zoom)` to center on project coordinates at a fixed zoom level. The radius circle and markers remain visible. Users can zoom manually if needed.
