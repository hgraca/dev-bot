# guards

Evaluates bash commands against configurable guard rules from global and project config files.

## OpenCode

Registered in `opencode.jsonc` as `tool.execute.before` plugin. Intercepts every bash/shell tool call automatically.

No manual configuration needed.

### Plugin path

`src/agentic/guards/hooks/opencode/on-tool_execute_before-guards.ts`

## Usage

Check whether command would be blocked:

```bash
bash src/agentic/guards/tools/guards.sh --command "rm -rf /"
```

Use `--json` for machine-readable output:

```bash
bash src/agentic/guards/tools/guards.sh --command "rm -rf /" --json
```
