---
name: explicit-architecture
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
        Query/<QueryName>/                  # Query handlers
        Repository/
        Listener/                           # Event handlers
        Service/
        UseCase/<UseCaseName>/              # Command handlers
    Component/<ComponentYName>/             # Can not depend on <ComponentXName>
      <SubComponentYA>/                     # Same inner structure as <ComponentXName>, can depend on <SubComponentYB>
      <SubComponentYB>/                     # Same inner structure as <ComponentXName>, can depend on <SubComponentYA>
    Port/<ToolName>/                        # Interfaces core needs
  Infrastructure/<ToolName>/<AdapterName>/  # Implements ports
  Presentation/{Api,Web,Cli}/               # Thin delivery layer
```

Shared Kernel: events, query objects, DTOs, value objects crossing component boundaries.

Component may have subcomponents when domain is large.

`Core/Component/` grouping required even for single-component projects — establishes boundaries for future growth. Do not flatten `Domain/`, `Application/`, or `Port/` to source root.

**Legacy:** anything in `<root>/` outside this structure is legacy, unless explicitly mentioned otherwise.
Never place new files in legacy namespaces.

## Dependency Rules

```
                Domain
                  ^
Presentation -> Application -> Port <- Infrastructure
                    |           |          |
                language-overlay (treated as language runtime)
```

## See also

- `architecture-rules` skill
