---
name: create-opencode-tool
description: "Use this skill whenever the user asks to create a new tool, add a custom tool, write a tool definition, or extend agent capabilities with a new function — e.g. 'I need the agent to query our database', 'make the agent send Slack messages'. Triggers on 'create tool', 'new tool', 'custom tool', 'tool definition', 'write a tool', 'add a tool', 'make a tool', or when the user describes a capability the agent should have."
---

# Skill: Create OpenCode Custom Tool

Create custom tool LLM can call. JS/TS wrappers, shell out any language. Filename = tool name.

## When to Apply

- User asks create new tool, custom tool, tool definition
- User describes capability agent should have (query DB, send Slack, run script)
- User says "I need agent to be able to X" where X repeatable action
- User asks extend built-in toolset
- User asks create tool shelling out to Python, PHP, other languages

Do NOT apply when user asks about existing tools, wants use tool, debugging — those are questions.

## Procedure

### Step 0: Gather reqs

Clarify before writing:

1. **What tool do?** — One action. Multiple → separate tools.
2. **Args?** — Minimal. Prefer primitives/enums.
3. **Lang?** — JS/TS wrapper, any lang for work.
4. **Local or global?** — `.opencode/tools/` vs `~/.config/opencode/tools/`.
5. **Permissions?** — Destructive → `require-approval`. Read-only → `allow`.
6. **Dry-run?** — Destructive MUST have dry-run or confirm step.
7. **Secrets?** — Never embed. Load from env vars or secret store.

### Step 1: Design

#### Single responsibility

- One tool = one action. "Query DB + format results" → two tools.
- Prefer several small tools over one large.

#### Security & least privilege

- Minimal args. Every extra arg = attack surface.
- Never embed secrets. Load from `process.env` or secret store.
- Check name shadows built-in (read, write, bash, glob, grep). If so, rename or disable via permissions.

#### Argument schema — MUST

- **MUST use Zod schema (`tool.schema`) for ALL tools.** Every tool must define its arguments with `tool.schema` — never use bare `args: {}`. This ensures tools are properly invocable through OpenCode's tool execution mechanism with typed parameters.
- Every field that IS used: add `.describe()`.
- Prefer `z.string()`, `z.number()`, `z.enum()` over `z.object()`.
- Required = required. Optional → `.optional()`.

#### Dual-mode hazard: tool is also a CLI subprocess

When a tool file is typescript (`.ts`) and lives under `.opencode/tools/`, opencode registers it as a custom tool. This is intentional for tool files under `src/instructions/tools/` — they are symlinked there by `init.sh`. **But**: if the tool is also designed to be invoked as a standalone CLI subprocess (by a plugin or by `Bun.spawn`), its `main()` call at the top level runs during opencode's module-load-time tool registration, printing junk to stdout/stderr and potentially breaking the session.

**Fix**: guard `main()` behind an entry-point check:

```typescript
const isEntryPoint = process.argv[1] && (process.argv[1] === import.meta.path || process.argv[1].endsWith("/<tool-name>.ts"));
if (isEntryPoint) {
    main();
}
```

This ensures `main()` runs only when `bun <tool-name>.ts ...` is called directly (plugin subprocess), not when opencode imports the file to register the custom tool export.

This pattern applies whenever a `.ts` file under `src/instructions/tools/` serves dual purpose: standalone CLI subprocess AND opencode custom tool. If the tool is exclusively a CLI subprocess, prefer excluding it from the tool registration entirely (e.g. storing it outside `tools/` or adding an exclusion to the init script). The entry-point guard is a practical mitigation when the file must live in `tools/` for path-resolution reasons (e.g. plugin resolves tool path relative to its own location).

#### Naming convention

- Filename = tool name. Use `snake_case.ts` or `kebab-case.ts`.
- Multi-tool: filename becomes prefix (`math_add`, `math_multiply`).
- Do NOT shadow built-in unless intentionally replacing.

### Step 2: Write tool file

#### DevBot agentic tools — colocated TS + bash pattern

**Return value — MUST return a string.** OpenCode calls `.split('\n')` on every tool return value. Returning an object, array, `undefined`, or `null` crashes with `p.split is not a function`. Always return `string`:

```typescript
// CORRECT
return stdout.trim();
return JSON.stringify({ status: "ok", result });
return `error: ${message}`;

// WRONG — crashes opencode
return { status: "ok" }; // object
return undefined; // undefined
return JSON.parse(stdout); // parsed object
```

**Multi-value args — MUST handle all formats.** When accepting array arguments, the LLM may pass a multi-value parameter as a native JS array, a JSON array string, a comma-separated string, or a space-separated string. Always normalise before use:

```typescript
function toArray(val: unknown): string[] {
    if (Array.isArray(val)) return val.map(String);
    const s = String(val ?? "").trim();
    if (!s) return [];
    // Try JSON array
    if (s.startsWith("[")) {
        try {
            return (JSON.parse(s) as unknown[]).map(String);
        } catch {}
    }
    // Comma-separated
    if (s.includes(","))
        return s
            .split(",")
            .map((v) => v.trim())
            .filter(Boolean);
    // Space-separated or single value
    return s.split(/\s+/).filter(Boolean);
}
```

**Never `JSON.parse` stdout and return the result directly.** `JSON.parse` returns an object — returning it crashes opencode. Either return `stdout.trim()` (raw string) or `JSON.stringify(JSON.parse(stdout))` (re-serialised string).

```typescript
// CORRECT — return raw string
return stdout.trim();

// CORRECT — re-serialise if you need to validate JSON
try {
    return JSON.stringify(JSON.parse(stdout.trim()));
} catch {
    return stdout.trim();
}

// WRONG — returns object, crashes opencode
return JSON.parse(stdout.trim());
```

**Partial failure over total abort.** Multi-path tools (e.g. tree, git-report) MUST skip invalid paths and report them, not abort the whole call. Collect errors, continue processing valid inputs, include error summary in return string.

Tools that live under `src/instructions/tools/<tool-name>/` (DevBot's own agentic tools) follow a stricter pattern. Each tool directory contains:

- `<tool-name>.ts` or `<tool-name>.py` — **Source of truth.** Contains all business logic. Accepts `--json` / `--markdown` flags if there is data output.
- if `<tool-name>.py` exists, then `<tool-name>.ts` is a thin wrapper that exports the MCP tool for opencode AND exposes a `main()` for CLI invocation. Accepts `--json` / `--markdown` flags if there is data output.
- `<tool-name>.sh` — **Thin CLI wrapper.** Calls the source of truth file (`.py` or `.ts` file via `bun`). Exists so users can run the tool from the shell without typing `bun <tool-name>.ts ...` directly. Accepts `--json` / `--markdown` flags if there is data output, but by default it assumes `--markdown`.

MUST: Ask the user if the tool is to be available to the agents on-demand as an internal built-in tool. If so, then the `<tool-name>.ts` MUST exist.

**TS tool (DevBot agentic tool)** — source of truth with business logic

```typescript
import { tool } from "@opencode-ai/plugin";
import path from "path";

function parseArgs(argv: string[]): { format: string; targets: string[] } {
    let format = "json";
    const targets: string[] = [];
    let i = 0;
    while (i < argv.length) {
        switch (argv[i]) {
            case "--markdown":
                format = "markdown";
                i++;
                break;
            case "--json":
                format = "json";
                i++;
                break;
            case "--format":
                format = argv[++i];
                i++;
                break;
            default:
                targets.push(argv[i]);
                i++;
                break;
        }
    }
    return { format, targets };
}

function main() {
    const { format, targets } = parseArgs(process.argv.slice(2));
    if (targets.length === 0) {
        console.error("Usage: <tool-name>.ts [--markdown|--json|--format markdown|json] <target> [...]");
        process.exit(1);
    }
    // --- BUSINESS LOGIC HERE ---
    // This is the single source of truth.
    const results = targets.map((t) => ({ target: t, status: "ok" }));

    if (format === "json") {
        console.log(JSON.stringify({ status: "ok", results }, null, 2));
    } else {
        for (const r of results) {
            console.log(`## ${r.target}\n\nstatus: ${r.status}\n`);
        }
    }
}

// Dual-mode guard: runs main() only when invoked directly, not when imported
const isEntryPoint = process.argv[1] && (process.argv[1] === import.meta.path || process.argv[1].endsWith("/<tool-name>.ts"));
if (isEntryPoint) {
    main();
}

export default tool({
    description: "Short description of what the tool does.",
    args: {
        targets: tool.schema.array(tool.schema.string()).describe("One or more targets to operate on."),
    },
    async execute(args) {
        // Forward to the same business logic invoked programmatically.
        // In-process call — no subprocess overhead.
        const targets = Array.isArray(args.targets) ? args.targets : [String(args.targets ?? "")];
        const results = targets.map((t) => ({ target: t, status: "ok" }));
        return JSON.stringify({ status: "ok", results });
    },
});
```

**Bash script (DevBot agentic tool)** — thin wrapper around `.ts`

```bash
#!/usr/bin/env bash
# src/instructions/tools/<tool-name>/<tool-name>.sh
# Thin wrapper: delegates everything to the .ts source of truth.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bun "$DIR/<tool-name>.ts" "$@"
```

Reference implementation: `src/instructions/tools/tree/` (`tree.ts` + `tree.sh`) — note this may still follow the legacy T→bash pattern; new tools MUST follow the TS-as-source-of-truth pattern above.

#### General project tool — single TS file

Place in `.opencode/tools/<tool-name>.ts` (project) or `~/.config/opencode/tools/<tool-name>.ts` (global).

#### Single-tool file template

```typescript
import { tool } from "@opencode-ai/plugin";

export default tool({
    description: "Short description of what this tool does. One sentence.",
    args: {
        arg1: tool.schema.string().describe("What this argument is for"),
        arg2: tool.schema.number().describe("Another argument"),
    },
    async execute(args, context) {
        // Use context.directory for session working directory
        // Use context.worktree for git worktree root
        // Use context.sessionID for the current OpenCode session identifier
        // Also available: context.messageID (current message ID), context.agent (current agent name)
        // Your logic here
        return JSON.stringify({ status: "ok", result: "..." });
    },
});
```

#### Multi-tool file template

```typescript
import { tool } from "@opencode-ai/plugin";

export const actionOne = tool({
    description: "Does one thing.",
    args: {/* ... */},
    async execute(args, context) {
        /* ... */
    },
});

export const actionTwo = tool({
    description: "Does another thing.",
    args: {/* ... */},
    async execute(args, context) {
        /* ... */
    },
});
```

Creates `<filename>_actionOne` and `<filename>_actionTwo`.

#### Shell-out pattern (Python, PHP, bash)

```typescript
import { tool } from "@opencode-ai/plugin";
import path from "path";

export default tool({
    description: "Runs a Python script to do X.",
    args: {
        input: tool.schema.string().describe("Input data"),
    },
    async execute(args, context) {
        const script = path.join(context.worktree, ".opencode/tools/my-script.py");
        const result = await Bun.$`python3 ${script} ${args.input}`.text();
        return result.trim();
    },
});
```

### Step 3: Permissions

Configure in `.opencode/permissions.jsonc`:

```jsonc
{
    "tools": {
        // Read-only, safe: allow without approval
        "my-read-tool": "allow",
        // Destructive: require explicit approval
        "my-write-tool": "require-approval",
        // Block entirely
        "my-dangerous-tool": "deny",
    },
}
```

### Step 4: Tests

- **Unit tests** for wrapper logic (arg validation, return formatting).
- **Integration tests** for subprocesses or external API calls.
- Tests MUST run in CI.
- Test file: `<tool-name>.test.ts` alongside tool file, or `tests/` mirroring path.

### Step 5: Logging + structured output

- Return structured JSON with fixed keys.
- Include error codes + human-friendly messages on failure.
- Append log entries to `.agents/logs/<tool-name>.log` (not stdout). Each entry: tool name, args, result, timestamp.

```typescript
import { tool } from "@opencode-ai/plugin";
import path from "path";

export default tool({
    description: "Short description of what this tool does. One sentence.",
    args: {
        arg1: tool.schema.string().describe("What this argument is for"),
    },
    async execute(args, context) {
        const logPath = path.join(context.worktree, ".agents/logs/my-tool.log");
        try {
            const result = await doSomething(args);
            // Append structured log entry
            await Bun.write(
                logPath,
                JSON.stringify({
                    tool: "my-tool",
                    args,
                    result,
                    timestamp: new Date().toISOString(),
                }) + "\n",
            );
            return JSON.stringify({ status: "ok", result });
        } catch (error) {
            return JSON.stringify({
                status: "error",
                code: "MY_TOOL_FAILED",
                message: error instanceof Error ? error.message : String(error),
            });
        }
    },
});
```

### Step 6: Gate check

Check every gate before signalling completion:

| #   | Gate                                                                                                                                             | Pass/Fail |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------ | --------- |
| 1   | One action, short description                                                                                                                    |           |
| 2   | Zod schema (`tool.schema`) used for all tools — never bare `args: {}`                                                                            |           |
| 3   | No secrets in repo; runtime reads from env/secret store                                                                                          |           |
| 4   | Permission policy set (allow / deny / require-approval)                                                                                          |           |
| 5   | Idempotent or dry-run for destructive actions                                                                                                    |           |
| 6   | Structured JSON output + error codes                                                                                                             |           |
| 7   | Tests (unit + integration) and CI runs them                                                                                                      |           |
| 8   | Logging to `.agents/logs/<tool-name>.log` (append-only)                                                                                       |           |
| 9   | Name follows convention, no built-in shadowing                                                                                                   |           |
| 10  | Dependencies documented and pinned (runtimes, binaries)                                                                                          |           |
| 11  | Example usage in tool file or README                                                                                                             |           |
| 12  | Manual-approval gating for risky operations                                                                                                      |           |
| 13  | Tool in correct folder (`.opencode/tools/` or `~/.config/opencode/tools/`)                                                                       |           |
| 14  | Changelog entry for capability/permission changes                                                                                                |           |
| 15  | DevBot agentic tool: `.ts` is source of truth with business logic; `.sh` is thin wrapper calling `bun <tool-name>.ts`                            |           |
| 16  | `execute` returns a `string` in all code paths (never object, array, undefined, or raw `JSON.parse` result)                                      |           |
| 17  | Multi-value args normalised with `toArray()` pattern (handles native array, JSON string, comma-sep, space-sep)                                   |           |
| 18  | Multi-path tool: invalid paths skipped and reported, not aborting the whole call                                                                 |           |
| 19  | Dual-mode tool (CLI subprocess + opencode custom tool): `main()` guarded by `isEntryPoint` check so module import does not trigger CLI execution |           |

Any gate fails → fix before signalling completion.

### Step 7: Signal done

When tool written, tested, permissions set, all gates pass:

- `[FINISHED]` — absolute path, line count, gate checklist result.
- Include example usage so orchestrator knows how to invoke.

## Session ID Access

Inside a custom tool's `execute` function, the session ID is available on the `context` (or `ctx`) parameter:

```typescript
import { tool } from "@opencode-ai/plugin";

export default tool({
    description: "My tool",
    args: tool.schema.object({}),
    async execute(args, context) {
        const sessionId = context.sessionID;
        // also available: context.messageID, context.agent, context.abort (AbortSignal)
        return `Session: ${sessionId}`;
    },
});
```

The `ToolContext` type exposes:

- `sessionID` — current session identifier
- `messageID` — current message identifier
- `agent` — current agent identifier (e.g. `"DevBot"`, `"Developer"`)
- `abort` — an `AbortSignal` for cancellation

## Definitions

| Term                | Meaning                                                             |
| ------------------- | ------------------------------------------------------------------- |
| `tool.schema`       | Zod schema helper from `@opencode-ai/plugin`. Same as `z` from zod. |
| `context.directory` | Session working dir (not necessarily git root).                     |
| `context.worktree`  | Git worktree root. Use for resolving relative paths.                |
| `context.sessionID` | Current OpenCode session identifier.                                |
| `context.messageID` | Current message identifier.                                         |
| `context.agent`     | Current agent name (e.g. `"DevBot"`).                               |
| `context.abort`     | AbortSignal for cancellation awareness.                             |
| `Bun.$`             | Bun shell utility for subprocesses. Available in OpenCode runtime.  |
| `require-approval`  | Permission level prompting user before tool executes.               |
