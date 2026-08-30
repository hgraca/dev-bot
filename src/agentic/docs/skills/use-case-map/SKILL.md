---
name: devbot:use-case-map
description: "Use this skill whenever the user wants a visual map of how commands flow through a PHP codebase — generate a UseCaseMap architecture diagram JSON tracing call chains from entry points through commands, handlers, ports, adapters, and HTTP clients. Triggers on 'use case map', 'architecture diagram', 'system overview', 'message flow', or when needing a visual map of the system, even if they do not say 'use case map'."
---

# use-case-map

Generate an architecture diagram (UseCaseMap) from a PHP codebase that follows message-bus conventions and explicit-architecture layering.

## What it Does

Scans a PHP project and traces every call chain:

```
Entry Point → Command/Query → Handler → Port → Adapter → HTTP Client
```

Discovers:

- **CLI commands** and **HTTP controllers** (entry points)
- **Commands** and **Queries** (message-bus dispatch)
- **CommandHandlers** and **QueryHandlers**
- **Domain Events** and **Listeners**
- **Ports** (interfaces) and **Adapters** (implementations)
- **HTTP Clients** (external service calls)
- **Callback handlers** with event dispatch chains

Uses:

1. **PHP reflection** (dockerized or local) — resolves full inheritance chains and interface implementations
2. **ast-grep** — matches dispatch patterns (`dispatchSync`, `dispatchAsync`, etc.)
3. **Filesystem scan** — discovers PHP files across configured directories

Output: a JSON file following the `UseCaseMap.schema.json` schema, renderable by the `UseCaseMap.html` visualizer.

## When to Use

- Onboarding: understand how a new codebase is wired
- Architecture review: verify layering and coupling
- Before refactoring: see the blast radius of changes
- After implementation: verify the flow matches the design
- Documentation: generate a visual overview for stakeholders

## Prerequisites

- PHP project with `composer.json` (version auto-detected)
- Message-bus library conventions (Command, CommandHandler, Event, EventListener, Query, QueryHandler interfaces)
- Explicit architecture directory structure (see `devbot:explicit-architecture` skill)
- `sg` (ast-grep) in PATH — for AST-level dispatch pattern matching
- Docker (optional) — used if local PHP CLI is not available; auto-detects PHP version from composer.json

## Tool: `use-case-map`

### CLI

```bash
# From the project root:
src/agentic/docs/tools/UseCaseMap/use-case-map.mcp.sh [flags]

# Or if wired in PATH:
use-case-map.mcp.sh [flags]
```

### OpenCode Tool

The `use-case-map` custom tool is available in the OpenCode palette. Parameters:

| Arg               | Required | Description                                             |
| ----------------- | -------- | ------------------------------------------------------- |
| `project-root`    | No       | PHP project root (default: current directory)           |
| `output`          | No       | Output file path (default: stdout)                      |
| `component`       | No       | Filter to a specific component (e.g. `Billing`)         |
| `title`           | No       | Diagram title                                           |
| `subtitle`        | No       | Diagram subtitle                                        |
| `copy-visualizer` | No       | Copy `UseCaseMap.html` visualizer to the specified path |

### Tool call pattern

```
use-case-map(project-root: "/path/to/php-project", component: "Billing", output: "docs/use-case-map.json")
```

### Output

A JSON object matching `UseCaseMap.schema.json`:

```json
{
  "title": "Architecture",
  "subtitle": "Auto-generated from graphify knowledge graph + PHP declaration analysis",
  "items": [
    {
      "title": "1. Cli commands",
      "items": [
        {
          "title": "1.1 ImportInvoices - ImportInvoices",
          "items": [
            { "title": "CLI Command", "color": "cli", "items": [...] },
            { "title": "Component", "color": "uc", "items": [...] },
            { "title": "Port", "color": "port", "items": [...] },
            { "title": "Adapter", "color": "adapter", "items": [...] },
            { "title": "HTTP Client", "color": "http", "items": [...] }
          ]
        }
      ]
    }
  ]
}
```

Each flow is a horizontal chain of **columns** (architectural layers), each containing **units** (classes/methods). Layers are color-coded: CLI (`cli`), Controller (`ctrl`), UseCase (`uc`), Handler (`handler`), Port (`port`), Adapter (`adapter`), HTTP Client (`http`), Event (`event`), Listener (`listnr`).

### Visualizing

To render the JSON output:

1. Generate the JSON: `use-case-map.mcp.sh -o docs/use-case-map.json`
2. Copy the visualizer: `use-case-map.mcp.sh --copy-visualizer docs/use-case-map-app.html`
3. Open `docs/use-case-map-app.html` in a browser — it loads `use-case-map.json` from the same directory

The visualizer (`UseCaseMap.html`) is in `src/agentic/docs/tools/UseCaseMap/UseCaseMap.html`. It's a standalone HTML page that fetches and renders the JSON diagram with:

- Collapsible sections (CLI Commands, HTTP Controllers, Listeners)
- Color-coded layer columns
- Sync/async dispatch arrows
- Nested sub-command delegation chains
- Port → Adapter → HTTP Client trace lines

## How It Works

1. **Load config**: reads `conf/php/structure-explicit-architecture.php` for directory layout, `conf/php/message-bus-dispatch-patterns.php` for dispatch methods, `conf/php/http-clients-types.php` for HTTP client base classes
2. **Index PHP files**: walks all configured directories (src, entry points, ports, adapters)
3. **PHP reflection**: runs `conf/php/message-bus-types.php` via PHP CLI (local or dockerized) to discover all Command→Handler, Query→QueryHandler, and Event→Listener mappings with full inheritance chain resolution
4. **AST parsing** (ast-grep): finds `$this->messageBus->dispatchSync(new Foo(...))` calls in entry points and handlers
5. **Source analysis**: reads handler files for port method calls (`$this->erp->createInvoice()`), adapter files for HTTP client calls
6. **Graph scanning**: uses graphify knowledge graph for community structure and file grouping (when `graphify-out/graph.json` exists)
7. **JSON assembly**: builds the section/column/unit hierarchy, deduplicates, sorts by namespace

## Troubleshooting

| Symptom                      | Likely cause                                      | Fix                                                                                 |
| ---------------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------- |
| "PHP CLI not found"          | No local PHP, no Docker                           | Install PHP >=8.0 or Docker                                                         |
| "composer.json not found"    | Not a PHP project or wrong `project-root`         | Verify project-root points to a PHP project root                                    |
| Empty output (no sections)   | No entry points discovered                        | Check that `conf/php/structure-explicit-architecture.php` matches project structure |
| Missing handlers             | Handler naming doesn't match convention           | Ensure handlers follow `<CommandName>Handler` naming                                |
| "ast-grep not found"         | `sg` binary not in PATH                           | Install: `npm install -g @ast-grep/cli` or `brew install ast-grep`                  |
| PHP reflection returns empty | PHP CLI version mismatch or missing autoloader    | Check composer.json PHP constraint; run `composer dump-autoload`                    |
| Docker PHP fails             | Docker not available or image can't mount project | Install Docker, or install local PHP CLI                                            |

## Related Skills

- `devbot:explicit-architecture` — directory structure and layer conventions this tool depends on
- `devbot:app-map` — interactive app map for browsing the same architecture visually
- `devbot:graphify` — knowledge graph tool used for structural discovery
