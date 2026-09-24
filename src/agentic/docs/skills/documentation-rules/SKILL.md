---
name: devbot:documentation-rules
description: "Use when writing documentation or updating the README. Triggers on 'docs', 'README', 'documentation'."
---

# Repository Documentation

## When to Apply

- Writing or organizing repository documentation
- Creating new documentation files
- Updating README.md table of contents
- Deciding how to structure long documents

## Rules

### Module documentation (`src/<area>/<module>/docs.md`)

- A module documents itself in a `docs.md` at the module root (areas: `agentic`, `tools`, `harnesses`). It becomes the module's page at `/modules/<area>/<name>`.
- A module without a `docs.md` gets **no page and no reference anywhere** on the site.
- Front matter carries a required `description` plus a capability manifest (`skills`, `commands`, `agents`, `hooks`, `plugins`, `tools`, `mcps`). See [Create a module](/create-a-module) for the contract and the supported YAML subset.
- The `## Contents` table and the capability strip are **generated** from that manifest — never write them by hand.

### Hand-written pages (`docs/`)

- Only pages that belong to no single module live under `docs/`: `index.md`, `configuration.md`, `create-a-module.md`, `mcp-config.md`, `modules-and-tools.html`.
- Text docs are `.md` files; each subject is self-contained in one file.
- Repo README.md must have a TOC pointing to every committed text doc under `docs/`.
- Whenever a docs file is created or removed, the README TOC must be updated to match.
- TOC must use indentation and enumerated sections to reflect nesting levels of documentation sections it points to.
- When a `.md` file exceeds 200 lines and contains several sections:
  - Create folder with name of that `.md` file
  - Break up file into several files inside that folder, each new file containing one section of initial file
- Images used in documentation, should be stored under `docs/imgs/`
- After writing or editing any `.md` file, run `format-md` (built-in tool) on the file to align table columns. Add this as a post-write step — invoke `format-md path="<file>"` after every `.md` write.

### Generated pages (never hand-edited)

- The module pages, the `/modules` index, `docs/_data/modules.yml` and the aggregate pages (`agents.md`, `skills.md`, `commands.md`, `hooks.md`, `mcps.md`, `module-reference.md`) are produced by `src/agentic/docs/tools/gather-module-docs.py` and are gitignored — do not commit them.
- Their prose comes from `src/agentic/docs/tools/templates/`. To change an aggregate page, edit its template.
- `make docs` gathers and serves the site; `make docs-gather` only gathers.
