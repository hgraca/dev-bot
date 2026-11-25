---
title: "Codebase Memory"
description: "Fast structural code intelligence via a persistent tree-sitter knowledge graph — no Ollama, no API key."
skills: ["codebase-index"]
hooks: ["codebase-memory-commit-refresh"]
tools: ["index-project", "mcp-index"]
mcps:
  codebase-memory: "Structural code intelligence — call graph, architecture, impact"
---

Find code by structure and meaning — call graphs, architecture, impact — backed by a persistent knowledge graph built from a native tree-sitter engine.

## What it does

- **Knowledge graph indexing**: functions, classes, call chains, HTTP routes, and cross-service links parsed from 160+ languages
- **Call graph tracing**: who calls a function and what it calls (`trace_path`)
- **Architecture overview**: languages, packages, routes, hotspots, clusters in one call (`get_architecture`)
- **Semantic + structural search**: bundled nomic embeddings, BM25, and regex structural queries (`search_graph`, `search_code`)
- **Impact analysis**: git diff → affected symbols with risk classification (`detect_changes`)
- **Cypher-like queries**: read-only relationship queries (`query_graph`)

## How agents use it

Instead of grepping for keywords or reading files one at a time, agents query the graph: trace callers of a function, map what a change touches, or get a whole-codebase architecture summary in a single structured call.

**Cold start:** `devbot up` primes the index — the module's `up.sh`
background-indexes the project's `src` or `app` folder (whichever exists at the
project root) through the shared gateway over MCP — so indexing is already under
way when the harness starts (it runs detached, so give the graph a moment). An
agent-run `git commit` re-primes it via a `command.after` hook — a commit from a
terminal is not covered. Without a src/app dir, run
`index_repository <dir>` once when
the structural tools first error (audit-51/52 NOTE).

## Known limits

- **Root-too-broad guard**: `index_repository` rejects a path it judges too
  broad to index as one root (e.g. a whole repo whose only subdirectory is
  `src/`); name a project directory below it (upstream engine heuristic).
- **Group-writable daemon warn**: the server may log
  `daemon.private_dir_group_writable_ancestor mode=0775` where the container
  user's home has a group-writable ancestor — benign (server still serves).

## Engine

Powered by `codebase-memory-mcp` (DeusData) — a single native binary with embeddings compiled in. No Ollama, no GPU, no API key. dev-bot runs it as a shared Docker gateway (`devbot up`), and the index persists on the `devbot-codebase-memory-store` named volume rather than under your home directory.

**A gateway container that is not running is recreated once.** `devbot up` runs compose with `--no-recreate`, so a container whose own state went bad is started again rather than rebuilt: the server exits 1 within seconds, nothing listens on 18504, and every harness reports the server as failed. When the readiness probe finds the container not running, `up.sh` force-recreates it, re-checks, and says so with a `WARN` line — at most once per run, and never while it is running or its state cannot be read.

A recreate that does not help only rules the container out: the store volume below is the next thing to check, but a bad image, entrypoint or configuration presents the same way. Check the volume before removing anything — that discards the index.

**One volume, and a check that it is the one in use.** The compose pins `name: devbot-codebase-memory-store`; an install from before that pin has a second volume called `devbot_devbot-codebase-memory-store` (compose used to derive `<project>_<volume>`). Docker leaves the old one alone and warns on every `devbot up`:

```
volume "devbot_devbot-codebase-memory-store" carries the compose label
"devbot-codebase-memory-store" but does not match the compose file ...
```

Confirm which one the container mounts before touching either — `docker inspect dev-bot-codebase-memory-mcp --format '{{range .Mounts}}{{.Name}}{{end}}'` — then remove only the unused one: `docker volume rm devbot_devbot-codebase-memory-store`. Removing the mounted name discards the index (rebuild it with `index_repository`).

## Selecting the engine

This module is one of two interchangeable codebase engines. Which one is active is set by `codebase_index_provider` in `.devbot.global.jsonc` (see [Configuration](/configuration)):

| Provider          | Engine                                                  |
| ----------------- | ------------------------------------------------------- |
| `codebase-index`  | Ollama-based semantic index (`opencode-codebase-index`) |
| `codebase-memory` | Tree-sitter knowledge graph (`codebase-memory-mcp`)     |

The two are mutually exclusive — flip the key, run `devbot reinit`, and only the selected engine is wired.

## Configuration

No project configuration is required.

## See also

- [Polyrepo sessions](/polyrepo-sessions) — how this module scopes itself to the owning project
- [Codebase Index](/modules/agentic/codebase-index) — the sibling Ollama-based engine
- [Graphify](/modules/agentic/graphify) — structural knowledge graph
- [QMD](/modules/agentic/qmd) — knowledge vault search
- [Configuration](/configuration) — `codebase_index_provider` key
