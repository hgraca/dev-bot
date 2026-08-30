---
name: devbot:create-claudecode-tool
description: "Use this skill whenever someone asks about adding custom tools to Claude Code agents via MCP — extending the agent tool palette, MCP servers in Claude Code, writing an MCP server, .mcp.json configuration, tool naming conventions (mcp__server__tool), giving Claude access to an API or database, subagent tool restrictions, or building domain-specific tools. The Claude Code equivalent of opencode's custom-tools."
---

# Custom Tools in Claude Code via MCP

Claude Code's equivalent to custom agent tools is **MCP (Model Context
Protocol)**. You define tools in an MCP server; Claude Code loads them and
Claude calls them exactly like its built-ins.

There are two ways to do this:

| Approach                             | When to use                                                     |
| ------------------------------------ | --------------------------------------------------------------- |
| **`.mcp.json` file**                 | Claude Code CLI — tools in the terminal tool palette            |
| **Agent SDK (`createSdkMcpServer`)** | Programmatic agents built with `@anthropic-ai/claude-agent-sdk` |

---

## Approach 1: `.mcp.json` for the Claude Code CLI

Create `.mcp.json` at your project root (committed = shared with team):

```json
{
    "mcpServers": {
        "my-tools": {
            "command": "node",
            "args": ["./tools/server.js"],
            "env": {
                "DB_URL": "${DB_URL}"
            }
        }
    }
}
```

Or add it via CLI instead of editing the file:

```bash
# Local (default) — only you, current project
claude mcp add --transport stdio my-tools -- node ./tools/server.js

# Project scope — committed to .mcp.json, shared with team
claude mcp add --transport stdio my-tools --scope project -- node ./tools/server.js

# User scope — available across all your projects
claude mcp add --transport stdio my-tools --scope user -- node ./tools/server.js

# Remote HTTP server
claude mcp add --transport http my-api https://api.example.com/mcp \
  --header "Authorization: Bearer ${MY_TOKEN}"
```

Check status and manage servers:

```bash
claude mcp list          # list all configured servers
claude mcp get my-tools  # details for one server
claude mcp remove my-tools
# inside Claude Code:
/mcp                     # live status panel with tool count per server
```

For details on scopes, transports, and `.mcp.json` syntax, see
[references/mcp-config.md](references/mcp-config.md).

---

## Approach 2: Agent SDK — In-Process Custom Tools

When building a programmatic agent, define tools in code using
`@anthropic-ai/claude-agent-sdk`. No separate server process needed.

### Install

```bash
npm install @anthropic-ai/claude-agent-sdk zod
# or Python:
pip install claude-agent-sdk httpx
```

### Define a tool

```typescript
// TypeScript
import { tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

const runTests = tool(
    "run_tests", // name — Claude calls this
    "Run the project test suite and return results. Use before marking work done.",
    {
        suite: z.string().optional().describe("Specific test suite to run"),
        bail: z.boolean().default(false).describe("Stop on first failure"),
    },
    async (args) => {
        const cmd = ["npm", "test", args.suite, args.bail ? "--bail" : ""].filter(Boolean).join(" ");
        const result = await runCommand(cmd);
        return {
            content: [{ type: "text", text: result.stdout }],
            isError: result.exitCode !== 0,
        };
    },
);
```

```python
# Python
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool(
    "run_tests",
    "Run the project test suite and return results. Use before marking work done.",
    {"suite": str},   # required params — optional ones: omit from schema, use args.get()
)
async def run_tests(args):
    suite = args.get("suite", "")
    result = await run_command(f"npm test {suite}".strip())
    return {
        "content": [{"type": "text", "text": result.stdout}],
        "is_error": result.exit_code != 0,
    }
```

### Wrap in a server and pass to `query`

```typescript
const devServer = createSdkMcpServer({
    name: "dev-tools",
    version: "1.0.0",
    tools: [runTests, lintFiles, checkTypes], // all your tools
});

for await (const message of query({
    prompt: "Implement the auth feature and make sure tests pass",
    options: {
        mcpServers: { dev: devServer },
        allowedTools: ["mcp__dev__run_tests", "mcp__dev__lint_files"],
        // or wildcard: ["mcp__dev__*"]
    },
})) {
    if (message.type === "result") console.log(message.result);
}
```

```python
dev_server = create_sdk_mcp_server(
    name="dev-tools",
    version="1.0.0",
    tools=[run_tests, lint_files, check_types],
)

options = ClaudeAgentOptions(
    mcp_servers={"dev": dev_server},
    allowed_tools=["mcp__dev__run_tests", "mcp__dev__lint_files"],
)

async for message in query(prompt="...", options=options):
    if isinstance(message, ResultMessage):
        print(message.result)
```

---

## Tool Naming Convention

Tools are always addressed as:

```
mcp__{server_name}__{tool_name}
```

The `server_name` is the key you use in `mcpServers` (e.g. `"dev"`).
The `tool_name` is the name you passed to `tool()`.

So `runTests` in server `"dev"` → `mcp__dev__run_tests`.

Use wildcards to allow all tools from a server: `mcp__dev__*`.

---

## Writing a Good Tool Handler

### Return format

```typescript
return {
    content: [{ type: "text", text: "result text here" }], // required
    isError: false, // optional — set true so Claude knows to retry/adjust
    structuredContent: {}, // optional — machine-readable JSON alongside content
};
```

### Error handling — keep the loop alive

```typescript
async (args) => {
    try {
        const data = await callApi(args.endpoint);
        return { content: [{ type: "text", text: JSON.stringify(data) }] };
    } catch (err) {
        // Return isError instead of throwing — throwing kills the whole query() call
        return {
            content: [{ type: "text", text: `API error: ${err.message}` }],
            isError: true,
        };
    }
};
```

### Return images

```typescript
return {
    content: [
        {
            type: "image",
            data: base64EncodedBytes, // no URL — inline base64 only
            mimeType: "image/png",
        },
    ],
};
```

### Tool annotations (metadata)

```typescript
tool("query_db", "...", schema, handler, {
    annotations: {
        readOnlyHint: true, // no side effects → Claude can batch in parallel
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false, // false = stays inside your process
    },
});
```

`readOnlyHint: true` is the most impactful — it lets Claude call this tool in
parallel with other read-only tools instead of sequentially.

---

## Restricting Tools per Subagent

In `.claude/agents/my-agent.md`, list exactly which tools the agent can use:

```yaml
---
name: test-runner
description: Runs tests and reports failures. Only use for CI verification.
tools: Read, Grep, mcp__dev__run_tests, mcp__dev__lint_files
permissionMode: acceptEdits
---
You are a CI verification agent. Run tests, report failures clearly.
Do not modify code — only read and run tests.
```

Omitting `tools` = agent inherits all tools available in the session.

To scope an MCP server to a subagent only (keeping it out of the main
conversation context):

```yaml
---
name: db-agent
description: Queries the database
mcpServers:
    database:
        command: node
        args: ["./db-server.js"]
        env:
            DB_URL: "${DB_URL}"
---
```

Inline server definitions here don't load in the parent conversation at all.

---

## Scaffold a New MCP Server Fast

Use the official plugin to have Claude build the server for you:

```
/plugin install mcp-server-dev@claude-plugins-official
/mcp-server-dev:build-mcp-server
```

Claude will ask about your use case and scaffold a stdio or HTTP server.

---

## Reference Files

- [references/mcp-config.md](references/mcp-config.md) — full `.mcp.json` schema, all transports, scopes, env var expansion, timeouts
- Official custom tools guide: https://code.claude.com/docs/en/agent-sdk/custom-tools
- MCP CLI guide: https://code.claude.com/docs/en/mcp
- Subagents guide: https://code.claude.com/docs/en/sub-agents
