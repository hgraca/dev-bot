---
name: app-map
description: "Use this skill whenever the user wants to create, view, or edit an interactive architecture diagram or application map — a zoomable canvas for arranging modules, groups, and connectors with drag-and-drop, editing titles and colors, and saving back to JSON. Triggers on 'app map', 'application map', 'architecture canvas', 'visual architecture', 'interactive diagram', or when needing to manually create or edit an architecture overview diagram, even if they do not say 'app map'."
---

# app-map

Interactive, zoomable canvas for building and editing architecture diagrams. A standalone HTML application that loads, displays, and saves hierarchical application maps.

## What it Is

`AppMap.html` is a self-contained HTML application (no build step, no dependencies) that provides:

- **Infinite canvas** — pan and zoom with mouse/trackpad
- **Drag-and-drop modules** — position nodes anywhere on the board
- **Group containers** — group related modules together
- **Connectors** — draw labeled arrows between any items
- **Inline editing** — double-click to edit titles, subtitles
- **Color coding** — each module/item can have a custom CSS color
- **JSON persistence** — load from and save to `AppMap.schema.json`-compliant JSON
- **Minimap overlays** — visual overview of the entire board

### Schema (`AppMap.schema.json`)

Defines the JSON format the canvas loads and saves. Top-level structure:

```json
{
  "id": "unique-id",
  "title": "Application Map Title",
  "type": "map",
  "subtitle": "Optional subtitle",
  "items": [...]
}
```

Item types:

| Type              | Description                              |
| ----------------- | ---------------------------------------- |
| `map`             | Root — the entire canvas                 |
| `module`          | Draggable node container (header + body) |
| `action`          | Leaf node inside a module or group       |
| `connector`       | Labeled arrow between two items          |
| `moduleItemGroup` | Visual group container for modules       |

Each item has `id`, `title`, `type`, and optional `color`, `x`, `y`, `items`.

## When to Use

- **Initial architecture design** — sketch module boundaries and dependencies before coding
- **Architecture documentation** — create a visual map for onboarding or review
- **Refactoring planning** — move modules around to explore new structures
- **Ad-hoc diagramming** — quickly lay out system components with drag-and-drop
- **Complement to UseCaseMap** — UseCaseMap auto-generates from code; AppMap lets you manually arrange and annotate

## How to Use

### Opening the canvas

1. Serve the file from any HTTP server:
   ```bash
   # Simple Python server from the assets directory:
   cd src/agentic/docs/skills/app-map/assets
   python3 -m http.server 8080
   # Or from project root:
   python3 -m http.server 8080
   ```
2. Open `http://localhost:8080/AppMap.html` in a browser
3. The canvas starts empty — click **"Load"** to open a JSON file, or start building from scratch

### Loading existing data

- Click the **Load** button in the top menu bar
- Select a JSON file that follows `AppMap.schema.json`
- All modules, groups, and connectors render on the canvas

### Building from scratch

- Click **"New"** to clear the canvas
- Use the right-click context menu or toolbar buttons to:
  - Add modules
  - Add groups
  - Add connectors between items
- Drag modules to position them
- Double-click titles to edit
- Right-click → edit colors

### Saving

- Click **"Save"** to download the current state as a JSON file
- The output follows `AppMap.schema.json` and can be reloaded later

### Navigation

| Action              | Input                          |
| ------------------- | ------------------------------ |
| Pan                 | Click-and-drag on empty canvas |
| Zoom                | Mouse wheel / pinch            |
| Move module         | Drag module header             |
| Edit title/subtitle | Double-click text              |
| Context menu        | Right-click item/module        |

## Assets

| File                 | Purpose                                |
| -------------------- | -------------------------------------- |
| `AppMap.html`        | Self-contained HTML canvas application |
| `AppMap.schema.json` | JSON schema defining the data format   |

These live under `src/agentic/docs/skills/app-map/assets/`. The HTML is fully self-contained — no npm, no build, no CDN dependencies beyond Google Fonts (Caveat, DM Mono, DM Sans).

## Relationship to UseCaseMap

- **UseCaseMap** (`use-case-map` tool) — auto-generates architecture JSON from PHP code (message-bus call chains)
- **AppMap** (`app-map` skill) — interactive editor for manually creating and arranging architecture JSON

They share a common concern (architecture visualization) but serve different workflows:

- UseCaseMap = automated discovery from code
- AppMap = manual design and editing

Future: wire AppMap to consume UseCaseMap-generated JSON for visual editing of auto-discovered flows.

## Limitations

- **No tool wrapping yet** — this is a skill with static HTML assets, not a CLI tool. The canvas requires a browser.
- **Load/Save uses File API** — the HTML uses the browser's file picker (`<input type="file">`) and download API. No server-side persistence.
- **Manual creation** — items are added via UI, not generated from code. Use `use-case-map` for code-driven generation.
