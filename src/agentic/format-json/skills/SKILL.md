---
name: format-json
description: "Format JSON and JSONC files with consistent 2-space indentation via prettier. Use this skill after writing or editing any .json or .jsonc file to keep formatting consistent."
---

# Format-json

Formats JSON and JSONC files with consistent 2-space indentation via `prettier`. Handles JSONC (comments, trailing commas) natively — no pre-processing needed. Operates on one or more `.json`/`.jsonc` files, or recursively on all such files in a directory. Also supports pipe mode.

**Dependency**: `prettier` must be installed globally (`npm install -g prettier`).

## When to Use

| Situation                                                   | Tool            |
| ----------------------------------------------------------- | --------------- |
| Just wrote or edited a `.json` or `.jsonc` file             | **Format-json** |
| JSON file has inconsistent indentation                      | **Format-json** |
| Need to format all config files at once                     | **Format-json** |
| Working with agent-generated JSON that has ugly formatting  | **Format-json** |
| Writing or editing a `.json` file with no formatting issues | Nothing needed  |

**Run format-json after every JSON/JSONC edit.** Keeps the repo's config files consistent without manual formatting.

## How to Call

```
format-json path=<file-or-directory>
```

| Parameter | Required | Description                                                                                                                                 |
| --------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `path`    | yes      | Absolute or relative path to a `.json`/`.jsonc` file or directory. Directories are walked recursively and all matching files are formatted. |

## Output Format

Reports the path that was processed on success. Warnings appear if any file could not be read or written.

Errors exit non-zero with a message.

## Pipe Mode

When called with no arguments and piped input, reads from stdin and writes formatted output to stdout:

```
cat file.json | format-json path=""
```

(Pass empty string or omit path to trigger pipe mode.)

## Examples

```
# Format a single file
format-json path="config/settings.json"

# Format a JSONC file
format-json path="config/options.jsonc"

# Format all JSON files in a directory (recursive)
format-json path="config/"

# Format using pipe
cat data.json | format-json path=""
```
