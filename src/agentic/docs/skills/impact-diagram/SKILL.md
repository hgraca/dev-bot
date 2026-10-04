---
name: devbot:impact-diagram
description: "Use when mapping which flows a git diff affects in a PHP codebase. Triggers on 'impact diagram', 'blast radius', 'what does this change affect', 'affected flows'."
---

# impact-diagram

Draw the **use-case flows a change touches**: the entry points that reach the changed classes and the
ports/adapters/HTTP clients they fan out to, with the changed units highlighted in red.

It is the diff-scoped sibling of `devbot:use-case-map`: the same deterministic PHP scanner builds the
full architecture map, then `impact-diagram` keeps only the flows that pass through the classes the
diff changed. No code-graph gateway, no Mermaid — a schema-shaped JSON rendered by a standalone HTML
visualizer.

## When to Use

- Before a refactor or a PR: see the blast radius of a branch's changes.
- "What flows does this change affect?" / "impact diagram" / "affected flows".
- Documentation: a focused flow view for a single change, not the whole app.

## Prerequisites

Same as `devbot:use-case-map`: a PHP project with `composer.json`, message-bus conventions and the
explicit-architecture layout, plus `sg` (ast-grep) and a PHP CLI (or Docker). `graphify-out/graph.json`
is used for file grouping when present.

## Tool: `impact-diagram`

Plain CLI (in the docs module's `tools/ImpactDiagram/`), **not** exposed over MCP:

```bash
src/agentic/docs/tools/ImpactDiagram/impact-diagram.sh \
  --project-root /path/to/php-project \
  --diff "origin/main...HEAD" \
  --output docs/impact-diagram.json \
  --copy-visualizer docs/impact-diagram.html
```

| Arg                    | Required | Description                                                                                               |
| ---------------------- | -------- | --------------------------------------------------------------------------------------------------------- |
| `--project-root`       | No       | PHP project root (default: current directory)                                                             |
| `--diff`               | No       | Git range (default `HEAD` = working tree). Use `main...<branch>` for a branch                             |
| `--output`             | No       | Output JSON (default: stdout)                                                                             |
| `--component`          | No       | Filter to a component (e.g. `Billing`)                                                                    |
| `--title`/`--subtitle` | No       | Diagram title / subtitle                                                                                  |
| `--copy-visualizer`    | No       | Copy `ImpactDiagram.html` to the given path                                                               |
| `--svg`                | No       | Also write a static **SVG** of the flows to the given path                                                |
| `--svg-app`            | No       | Write an SVG embedding the HTML app's `#app` rendering (browser fidelity; needs `node` + Chrome/Chromium) |

## Output

A JSON document in the `UseCaseMap` shape (`sections → subsections → columns → units`), pruned to the
flows that contain a changed class, plus:

- the changed units are marked `"color": "changed"` (rendered red);
- a top-level `"changed": [...]` list of the diff's class basenames.

## Visualizing

`--svg docs/impact-diagram.svg` writes a **static SVG** of the flows — deterministic, no browser, opens
anywhere (GitHub, a PR, an editor preview). Columns run entry → component → port → adapter → HTTP
client; changed units are red and carry a pencil (edit) icon.

`--svg-app docs/impact-diagram.svg` gives the **exact browser rendering**: headless Chrome loads the app
with the JSON and its `#app` render is embedded as an image inside an SVG, so it looks like the HTML app
yet paints in any viewer. It needs `node` + Chrome, and the embedded image is raster (not scalable).
Alternatively, for the interactive view:

1. Generate the JSON and copy the visualizer (above).
2. Open `docs/impact-diagram.html` in a browser and load `docs/impact-diagram.json` with the file
   picker, or pass `?file=docs/impact-diagram.json`. (Browsers block `fetch()` on `file://`, so a
   local server or the file picker is needed.)

## How It Works

1. `git diff --name-only <range>` → the changed `.php` files → their class basenames.
2. Reuses `create-use-case-map.py`'s `GraphScanner` + `UseCaseMapBuilder` (imported, not copied) to
   build the full map.
3. Marks every unit whose class is in the changed set (`color: "changed"`) and drops every flow that
   contains none.

## Troubleshooting

| Symptom                      | Likely cause                           | Fix                                             |
| ---------------------------- | -------------------------------------- | ----------------------------------------------- |
| Empty output                 | the diff changed no PHP class          | check `--diff` (a valid range, e.g. `main...X`) |
| `FATAL: git diff ... failed` | unknown ref                            | fetch first, or use a range that exists         |
| Empty flows, `degraded` set  | PHP CLI/Docker unavailable             | install PHP ≥8.0 or Docker                      |
| No changed units red         | class basenames differ from file names | confirm PSR-4 naming                            |

## Related Skills

- `devbot:use-case-map` — the full (non-diff-scoped) architecture map this reuses.
- `devbot:explicit-architecture` — the directory conventions the scanner depends on.
