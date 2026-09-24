---
date: 2026-09-24
keywords: ["devbot", "documentation", "docs.md", "jekyll", "generated-pages"]
---

## Module documentation lives with the module and is gathered at build time

Each module documents itself in `src/<area>/<module>/docs.md` (areas: `agentic`, `tools`, `harnesses`), and `src/agentic/docs/tools/gather-module-docs.py` compiles those files at build time into the Jekyll site: one page per module at `/modules/<area>/<name>`, a `/modules` index, `docs/_data/modules.yml`, and six aggregate pages (`agents`, `skills`, `commands`, `hooks`, `mcps`, `module-reference`). The generated output is gitignored, never committed — only `src/**/docs.md` and the hand-written meta pages (`docs/index.md`, `configuration.md`, `create-a-module.md`, `mcp-config.md`, `modules-and-tools.html`) are tracked, and a module without a `docs.md` gets no page and no reference anywhere on the site. The front matter is a required `description` plus a concise capability manifest (`skills`, `commands`, `agents`, `hooks`, `plugins`, `tools`, `mcps`); that manifest is the single capability source for every generated view, while per-item purposes are derived from the module's own files (`SKILL.md`, agent/command front matter, `hooks.json`, `mcp.json`, a tool's `# description:` header). The aggregates' prose lives in committed templates under `src/agentic/docs/tools/templates/`, with the tables substituted in at build time.
