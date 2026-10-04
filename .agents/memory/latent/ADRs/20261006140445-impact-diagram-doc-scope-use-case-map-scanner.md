---
date: 2026-10-06
keywords: ["impact-diagram", "use-case-map", "php-scanner"]
see: ["PDRs/20261006140445-impact-diagram-plain-bash-cli.md"]
---

## impact-diagram is a diff-scoped use-case map reusing the use-case-map scanner

The impact diagram — which flows a git diff affects — lives in the `docs` module as
`src/agentic/docs/tools/ImpactDiagram/` and reuses the use-case-map scanner
(`create-use-case-map.py`'s `GraphScanner` + `UseCaseMapBuilder`) rather than the codebase-memory
graph. It runs the full PHP scan, then keeps only the flows whose units are classes the diff changed
(`git diff --name-only <range>` → class basenames), marking those units red. The scanner is imported
via `importlib`, not forked. Output is UseCaseMap-shaped JSON, rendered either to a static SVG
(deterministic `render_svg` in Python) or to an SVG that embeds the HTML app's `#app` render. This
supersedes the earlier architecture-module pipeline (codebase-memory MCP port/adapter + Mermaid
generator + mmdc render), whose failures were a stale index, entry/exit guessing, and Mermaid
layout/wrapping churn. PHP-first by design — the scanner is PHP reflection + ast-grep.
