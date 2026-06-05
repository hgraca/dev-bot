---
name: format-md
description: "Format markdown files with consistent formatting via prettier. Use this skill after writing or editing any .md file to keep formatting consistent."
---

# Format-md

Formats markdown files with consistent formatting via `prettier`. Handles tables, headings, lists, code fences, blank lines, and all markdown features. Operates on one or more `.md` files, or recursively on all `.md` files in a directory. Also supports pipe mode.

**Dependency**: `prettier` must be installed globally (`npm install -g prettier`).

## When to Use

| Situation                                                  | Tool          |
| ---------------------------------------------------------- | ------------- |
| Just wrote or edited a `.md` file                          | **Format-md** |
| Tables look misaligned in raw markdown                     | **Format-md** |
| Headings, lists, or blank lines need consistent formatting | **Format-md** |
| Need to format all documentation at once                   | **Format-md** |
| Working with agent-generated markdown that looks messy     | **Format-md** |

**Run format-md after every markdown edit.** Keeps the repo's documentation consistent without manual formatting.

## How to Call

```
format-md path=<file-or-directory>
```

| Parameter | Required | Description                                                                                                                   |
| --------- | -------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `path`    | yes      | Absolute or relative path to a `.md` file or directory. Directories are walked recursively and all `.md` files are formatted. |

## Output Format

Reports the path that was processed on success. Warnings appear if any file could not be read or written.

Errors exit non-zero with a message.

## Pipe Mode

When called with no arguments and piped input, reads from stdin and writes formatted output to stdout:

```
cat file.md | format-md path=""
```

(Pass empty string or omit path to trigger pipe mode.)

## Examples

```
# Format a single file
format-md path="docs/README.md"

# Format all docs
format-md path="docs/"

# Format using pipe
cat docs/README.md | format-md path=""
```
