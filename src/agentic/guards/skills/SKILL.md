---
name: guards
description: "Evaluate a bash command against configurable guard rules from global and project config files. Use this skill whenever you need to check whether a command would be blocked by security/guard rules, or before running a potentially dangerous command."
---

# Guards

Evaluates bash commands against guard rules from two config files: a global `.devbot.global.jsonc` and a per-project `.devbot.project.jsonc`. Returns whether the command would be blocked and why.

## When to Use

| Situation                                                         | Tool                                       |
| ----------------------------------------------------------------- | ------------------------------------------ |
| Need to check if a command will be blocked before running it      | **Guards**                                 |
| Debugging why a command was blocked by a guard rule               | **Guards**                                 |
| Testing new guard rules before deploying                          | **Guards**                                 |
| Need to understand which guard rules apply in the current project | **Guards**                                 |
| Actually running a bash command                                   | Bash (guards run automatically via plugin) |

The guards plugin (`tool.execute.before`) intercepts every bash command automatically — this tool is for explicit checking.

## How to Call

```
guards --command "<command>"
```

| Parameter          | Required | Description                                                                |
| ------------------ | -------- | -------------------------------------------------------------------------- |
| `--command`        | yes      | The bash command string to evaluate against guard rules                    |
| `--global-config`  | no       | Path to the global `.devbot.global.jsonc` (auto-resolved if omitted)       |
| `--project-config` | no       | Path to the per-project `.devbot.project.jsonc` (auto-resolved if omitted) |
| `--agent`          | no       | Agent name for agent-filtered guard rules                                  |

Output is Markdown by default. Add `--json` for programmatic use.

## Output Format (Markdown)

```
## Guards check

**Result:** [BLOCKED] | ALLOWED

**Reason:** <message if blocked>
```

## Output Format (JSON)

```json
{ "blocked": true, "message": "Dangerous recursive delete blocked." }
```

## Examples

```
# Check if rm -rf / would be blocked
guards --command "rm -rf /"

# Check with explicit config paths
guards --command "docker system prune" \
  --global-config /path/to/.devbot.global.jsonc \
  --project-config /path/to/project/.devbot.project.jsonc

# Check as JSON for scripting
guards --command "rm -rf /" --json

# Check with agent filter
guards --command "git push --force" --agent developer
```
