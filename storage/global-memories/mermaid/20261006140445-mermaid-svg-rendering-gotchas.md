---
date: 2026-10-06
keywords: ["mermaid", "svg", "mmdc"]
trigger-on: ["mermaid-flowchart", "mmdc-svg"]
---

## Mermaid SVG rendering traps: labels, wrapping, background, subgraphs, viewers

Hard-won gotchas rendering a `flowchart LR` with `@mermaid-js/mermaid-cli` (mmdc v11):

- Node-label text as SVG `<text>` (not `<foreignObject>` HTML) requires the **top-level**
  `htmlLabels: false` in the Mermaid config; nesting it under `flowchart` does nothing. With
  `htmlLabels: true` labels are HTML `<div>`s inside a `<foreignObject>` — browsers paint them, but
  many non-browser viewers show empty boxes.
- `flowchart.wrappingWidth` widens node-label wrapping, but **edge labels ignore it** — they wrap
  mid-word at a fixed width regardless of `wrappingWidth` or `markdownAutoWrap: false`. Only
  `htmlLabels: true` stops edge wrapping (but reverts node labels to foreignObject). Keep edge labels
  short; an edge label equal to the target node's own label is redundant and can be dropped.
- `mmdc --backgroundColor` only sets a CSS `background-color` on the `<svg>` root — image viewers show
  it transparent. Paint a real `<rect width=viewBox>` as the first child to make the background opaque.
- Mermaid **stacks subgraphs that no edge connects**, and a node with no incoming edge ranks at the far
  left. To force ordered columns with invisible groups: emit `subgraph colN[" "]` plus
  `style colN fill:none,stroke:none,color:none`, and add invisible `~~~` links from each column's root
  nodes to the next column's, or the columns collapse and stack.
