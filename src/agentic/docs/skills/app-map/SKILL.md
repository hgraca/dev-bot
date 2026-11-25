---
name: devbot:app-map
description: "Use when drawing, creating or editing an architecture diagram or application map. Triggers on 'app map', 'architecture diagram', 'architecture canvas', 'visual architecture'."
---

# app-map

Interactive, zoomable canvas for building and editing architecture diagrams. A standalone HTML application that loads, displays, saves and exports hierarchical application maps.

## What it Is

`AppMap.html` is a self-contained HTML application (no build step, no dependencies) that provides:

- **Infinite canvas** — pan and zoom with mouse/trackpad
- **Drag-and-drop modules** — position nodes anywhere on the board
- **Group containers** — group related modules together
- **Connectors** — draw labeled arrows between any items
- **Inline editing** — double-click to edit titles, subtitles
- **Color coding** — each module/item can have a custom CSS color
- **JSON persistence** — load from and save to `AppMap.schema.json`-compliant JSON
- **File ownership** — Save writes back into the open file, Save as picks a new one
- **SVG export** — the drawn board as a standalone image, trimmed to its content
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

- **Drawing an architecture diagram** — when the user asks for a diagram of how modules, services and flows fit together, draw it in AppMap; do not hand back ASCII art or Mermaid when a diagram is what was asked for
- **Initial architecture design** — sketch module boundaries and dependencies before coding
- **Architecture documentation** — create a visual map for onboarding or review
- **Refactoring planning** — move modules around to explore new structures
- **Ad-hoc diagramming** — quickly lay out system components with drag-and-drop
- **Complement to UseCaseMap** — UseCaseMap auto-generates from code; AppMap lets you manually arrange and annotate

## How to Use

### Drawing a diagram

AppMap is the place to draw architecture. Its JSON is hand-authorable, so you can build the map
without the UI:

1. Write the map against `AppMap.schema.json` — `map` root, `module` nodes, `action` leaves,
   `connector` arrows, `moduleItemGroup` containers. Give modules `x`/`y`, or let the editor lay
   them out.
2. Save it where the user wants it and open it in the editor (below) for them to adjust.
3. Export the board as SVG when the picture belongs in a pull request, ticket or page.

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
3. The canvas starts empty — click **"Load JSON"** to open a file, or **New** to start building from scratch

### Loading existing data

- Click the **Load JSON** button in the top menu bar
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

### Saving and exporting

The editor keeps the file it opened, so the buttons mean what they say:

| Button         | Behaviour                                                                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| **Save**       | writes straight into the open file; with nothing open it behaves as **Save as**                                                            |
| **Save as**    | asks where to write, starting in the folder of the last opened file                                                                        |
| **Reload**     | re-reads the open file from disk, discarding unsaved edits; disabled until a file is open — fallback browsers re-read the last loaded copy |
| **Export SVG** | writes the drawn board as a standalone `.svg`, starting in the last file's folder; disabled while the board holds no modules or groups     |

`New` starts an untitled board and drops the file association: `Save` then asks where to write and
`Reload` returns to disabled.

The SVG holds only the board — no menu bar — cropped to the content's bounding box plus a 10px
border, so it drops into a document without whitespace around it.

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
- **AppMap** (`devbot:app-map` skill) — interactive editor for manually creating and arranging architecture JSON

They share a common concern (architecture visualization) but serve different workflows:

- UseCaseMap = automated discovery from code
- AppMap = manual design and editing

Future: wire AppMap to consume UseCaseMap-generated JSON for visual editing of auto-discovered flows.

## Limitations

- **No tool wrapping yet** — this is a skill with static HTML assets, not a CLI tool. The canvas requires a browser.
- **File access needs a Chromium browser** — Save, Save as, Reload and Export SVG use the File System Access API. Firefox and Safari have no equivalent: there the editor falls back to the file input and a download, so Save downloads and Reload re-reads the last loaded copy.
- **The picker cannot start at the home directory** — a browser has no handle on the OS home folder. With no file opened yet, the picker opens wherever the browser last left it.
- **Export is a rendered board, not an editable vector** — the SVG wraps the live DOM in a `foreignObject`, so it renders in browsers but shows an empty frame in Illustrator or Inkscape.
- **No server-side persistence** — nothing is stored outside the file the user picks.
