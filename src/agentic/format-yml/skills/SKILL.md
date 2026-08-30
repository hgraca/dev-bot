---
name: devbot:format-yml
description: "Format YAML files with consistent 2-space indentation via prettier. Use this skill after writing or editing any .yml or .yaml file to keep formatting consistent."
---

# Format-yml

Formats YAML files with consistent 2-space indentation via `prettier`. Preserves comments, key ordering, and block scalars (|, >). Quotes ambiguous unquoted strings (true/false/yes/no/null/numbers). Operates on one or more `.yml`/`.yaml` files, or recursively on all such files in a directory. Also supports pipe mode.

**Dependency**: `prettier` must be installed globally (`npm install -g prettier`).

## When to Use

| Situation                                                   | Tool           |
| ----------------------------------------------------------- | -------------- |
| Just wrote or edited a `.yml` or `.yaml` file               | **Format-yml** |
| YAML file has inconsistent indentation                      | **Format-yml** |
| Need to format all config files at once                     | **Format-yml** |
| Working with agent-generated YAML that has ugly formatting  | **Format-yml** |
| Writing or editing a `.yaml` file with no formatting issues | Nothing needed |

**Run format-yml after every YAML edit.** Keeps the repo's config files consistent without manual formatting.

## How to Call

```
format-yml path=<file-or-directory>
```

| Parameter | Required | Description                                                                                                                               |
| --------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `path`    | yes      | Absolute or relative path to a `.yml`/`.yaml` file or directory. Directories are walked recursively and all matching files are formatted. |

## Output Format

Reports the path that was processed on success. Warnings appear if any file could not be read or written.

Errors exit non-zero with a message.

## Pipe Mode

When called with no arguments and piped input, reads from stdin and writes formatted output to stdout:

```
cat file.yml | format-yml path=""
```

(Pass empty string or omit path to trigger pipe mode.)

## Examples

```
# Format a single file
format-yml path="config/settings.yml"

# Format a .yaml file
format-yml path="config/options.yaml"

# Format all YAML files in a directory (recursive)
format-yml path="config/"

# Format using pipe
cat data.yml | format-yml path=""
```
