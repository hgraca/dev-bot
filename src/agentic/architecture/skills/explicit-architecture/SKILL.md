---
name: devbot:explicit-architecture
description: "Project directory structure and dependency rules: DDD + Hexagonal + CQRS layers, component boundaries, port/adapter layout. Use this skill whenever understanding project structure, placing new files, checking layer dependencies, or reviewing code placement — especially in a clean/hexagonal architecture codebase."
---

# Explicit Architecture

## When to Apply

- Understanding project directory structure and where files belong
- Placing new classes, interfaces, or modules
- Checking dependency direction between layers
- Reviewing whether code is in correct layer

In this document:

- `<root>` is `app/` for Laravel projects, otherwise `src/`.
- `/` is namespace separator, might differ by programming language.

## Directory Structure

```
<root>/
  Core/
    Component/<ComponentXName>/             # Can not depend on <ComponentYName>
      Domain/<EntityName>/                  # Pure business logic. Zero framework deps.
      Application/
        Query/<QueryName>/                  # SHARED queries, used by multiple consumers
        Repository/
        Listener/                           # Event handlers
        Service/
        UseCase/<UseCaseName>/              # Command handlers
          Query/<QueryName>/                # Query used ONLY by this use case
    Component/<ComponentYName>/             # Can not depend on <ComponentXName>
      <SubComponentYA>/                     # Same inner structure as <ComponentXName>, can depend on <SubComponentYB>
      <SubComponentYB>/                     # Same inner structure as <ComponentXName>, can depend on <SubComponentYA>
    Port/<ToolName>/                        # Interfaces core needs
  Infrastructure/<ToolName>/<AdapterName>/  # Implements ports
  Presentation/{Api,Web,Cli}/               # Thin delivery layer
    <Area>/<ControllerName>/                # Controller folder: controller + its exclusive artifacts
      Query/<QueryName>/                    # Query used ONLY by this controller
```

Shared Kernel: events, query objects, DTOs, value objects crossing component boundaries.

Component may have subcomponents when domain is large.

`Core/Component/` grouping required even for single-component projects — establishes boundaries for future growth. Do not flatten `Domain/`, `Application/`, or `Port/` to source root.

**Legacy:** anything in `<root>/` outside this structure is legacy, unless explicitly mentioned otherwise.
Never place new files in legacy namespaces.

## Consumer-scoped placement rule

Every consumer — controller, use case (command handler), CLI command — owns a namespace/folder of its own, and everything used exclusively by it lives inside that folder:

- **Controller namespace** — every controller is a delivery-mechanism adapter (UI entry point) and lives under `Presentation`: `Presentation/Web/<Area>/<ControllerName>/<ControllerName>.php` for UI (browser) controllers, `Presentation/Api/<Area>/<ControllerName>/<ControllerName>.php` for API controllers, `Presentation/Cli/<CommandName>/<CommandName>.php` for CLI commands. A controller's layer (Web vs Api) is determined by the routes it serves, not by its name. Never place new controllers (or their artifacts) under legacy namespaces such as `app/Http/Controllers/`. A use case owns `Application/UseCase/<UseCaseName>/`.
- **Exclusive artifacts** — anything used only by that consumer lives inside its folder: `Query/<QueryName>/` for single-consumer queries (query + handler), flat next to the controller for the rest (form requests, DTOs, resource/transformer classes).
- **Shared artifacts** — used by multiple consumers → shared level: `Application/Query/<QueryName>/` for queries, the component/area level for DTOs and resource classes (e.g. `Presentation/Api/<Area>/<SharedResource>.php`).

Placement is decided by actual usage, not by the artifact's topic. Moving a single-consumer artifact to the shared level (or vice versa) is a refactor that changes code placement, not behavior.

## Dependency Rules

```
                Domain
                  ^
Presentation -> Application -> Port <- Infrastructure
                    |           |          |
                language-overlay (treated as language runtime)
```

## See also

- `devbot:architecture-rules` skill
