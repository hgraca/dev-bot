---
date: 2026-04-24
keywords: ["graphify", "graph"]
---

## M-FLOW-067: graphify CLI already provides progress — don't hide it

graphify `update .` prints AST extraction progress (`AST extraction: 100/429 files (23%)`) and summary (`Rebuilt: 1147 nodes, 1150 edges, 267 communities`) to stdout. The init.sh script was capturing this in `output=$(graphify update . 2>&1)`, hiding everything.
When a CLI tool already provides useful progress output, pipe through `tee` instead of capturing in a subshell. Use the captured output to parse summary numbers for a formatted summary box, while letting the progress stream to the terminal live.
