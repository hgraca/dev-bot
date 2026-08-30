---
name: devbot:tree
description: "Use the built-in `tree` tool to inspect directory structure — shows all subfolders and files in one or more paths. Use this skill instead of raw shell commands like `ls -R` or `find` whenever you need to see a directory's structure."
---

# Tree

Inspects one or more directories and returns the full directory tree (all subfolders and files) as Markdown.

## When to Use

| Situation                                                         | Tool              |
| ----------------------------------------------------------------- | ----------------- |
| Need to understand directory layout before reading files          | **Tree**          |
| Exploring unfamiliar area of the codebase                         | **Tree**          |
| Checking if a path or file exists before operating on it          | **Tree**          |
| Verifying structure after creating or modifying files             | **Tree**          |
| Mapping project layout (src/, tests/, config/, docs/)             | **Tree**          |
| Reporting directory structure in documentation or session context | **Tree**          |
| Looking at 1–3 specific, known files for content                  | Read (individual) |
| Searching for files by name pattern                               | Glob              |
| Searching file contents by pattern                                | Grep              |
| Getting full module or feature context across 5+ files            | Repomix           |

**Prefer Tree over `ls -R`, `find`, or manual `ls` calls.** A single `devbot:tree` call replaces many raw shell commands and returns structured output.

## How to Call

```
tree paths="<dir>"
```

| Parameter | Required | Description                                                                                                                                            |
| --------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `paths`   | yes      | One or more directory paths. Accepts a single path (`src`), JSON array (`["src","lib"]`), comma-separated (`src,lib`), or space-separated (`src lib`). |

No other parameters.

## Output Format

```
## Tree structure

<output of the `tree` command>
```

When multiple directories are given, each directory produces its own `## Tree structure` section in order.

## Usage Guidelines

### Before reading files

Run `devbot:tree` first instead of guessing file names. The full layout often reveals files you did not know existed — config files, READMEs, entry points.

```
tree paths="src/components"
```

→ Shows all components at once: `index.ts`, `types.ts`, `utils/` alongside the component files.

```
tree paths='["src/","tests/"]'
```

→ Multiple `## Tree structure` sections, one per directory.

### After creating or modifying files

Run `devbot:tree` on the affected directory to verify the new structure — no missing files, no orphaned directories, correct nesting.

### When mapping a project

Run `devbot:tree` on each top-level directory to build a mental model of where everything lives.

### Limitations

| Limitation                                    | Workaround                                 |
| --------------------------------------------- | ------------------------------------------ |
| Shows structure only, not contents            | Use **Read** for contents                  |
| No pattern filtering                          | Use **Glob** for `**/*.ts` matching        |
| Large directories (10k+ entries) may truncate | Narrow scope: `tree paths="src/specific/"` |

## Examples

```
tree paths="src/auth"
```

Produces:

````
## Tree structure
```text
src/auth/
├── config/
├── routes/
├── middleware/
├── tests/
└── index.ts
````

```
tree paths='["src/","config/"]'
```

Produces two `## Tree structure` sections — one for `src/`, one for `config/`.
