# guards

Evaluates bash commands against configurable guard rules from global and project config files.

## OpenCode

Registered in `opencode.jsonc` as `tool.execute.before` plugin. Intercepts every bash/shell tool call automatically.

No manual configuration needed.

### How it's wired

Declared in `src/agentic/guards/hooks.json` (`command.before`, `blocking: true`) and wired by the generic adapter `src/harnesses/opencode/hooks/on-hooks.ts`.

## Usage

Check whether command would be blocked:

```bash
bun src/agentic/guards/tools/guards.ts --command "rm -rf /"
```

Use `--json` for machine-readable output:

```bash
bun src/agentic/guards/tools/guards.ts --command "rm -rf /" --json
```
