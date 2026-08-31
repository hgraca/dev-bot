---
date: 2026-08-12
keywords: ['leaflet', 'marker', 'hover', 'table', 'bidirectional']
trigger-on: ['leaflet-marker-hover-table', 'bidirectional-map-table-selection']
---

## Bidirectional selection between Leaflet map markers and data table

To highlight a table row when hovering a map marker: add an `onHotelHover(id | null)` callback prop to the map component. Bind Leaflet `marker.on('mouseover')` / `marker.on('mouseout')` to call the callback. In the parent, track hovered ID in a separate state variable (distinct from `selectedId` to avoid triggering detail panels). Pass it to the table component alongside the existing `selectedId` prop. Use a different highlight color for hover vs selected (e.g. light blue `#e8f0fe` for hover, yellow `#fffde7` for selected). This creates a clean bidirectional link: click table row → map pans to marker; hover marker → table row highlights.
