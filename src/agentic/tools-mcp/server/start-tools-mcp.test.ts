// src/agentic/tools-mcp/server/start-tools-mcp.test.ts
// Black-box regression test for the devbot-tools MCP server.
//
// Guards audit-18 NOTE: "discovered 12 tool(s)" logged 6x/2min. The server
// used to re-discover (and re-log) tools on every `tools/list` AND every
// `tools/call` — log spam plus a full mcp-meta subprocess spawn per tool per
// request. Discovery must happen once per process and be reused.

import { describe, test, expect, beforeAll, afterAll } from "bun:test"
import { spawn } from "node:child_process"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"

const SERVER = path.resolve(import.meta.dir, "start-tools-mcp.ts")

let tmpDir: string
let proc: ReturnType<typeof spawn>
let stderr = ""
let next: () => Promise<{ id?: number; result?: any; error?: any }>

beforeAll(async () => {
  // Hermetic project: a tools dir with one stub .mcp.sh tool.
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tools-mcp-test-"))
  const toolsDir = path.join(tmpDir, ".agents", "tools")
  fs.mkdirSync(toolsDir, { recursive: true })
  fs.writeFileSync(
    path.join(toolsDir, "fake-tool.mcp.sh"),
    `#!/usr/bin/env bash
if [[ "\${1:-}" == "mcp-meta" ]]; then
  cat <<'EOF'
{"name":"fake-tool","description":"A fake tool for the devbot-tools server test","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"}},"required":[]}}}
EOF
  exit 0
fi
echo "fake-tool ok: $*"
`,
  )

  proc = spawn("bun", ["run", SERVER], {
    env: { ...process.env, TOOLS_MCP_PROJECT_DIR: tmpDir },
    stdio: ["pipe", "pipe", "pipe"],
  })

  proc.stderr.on("data", (chunk: Buffer) => {
    stderr += chunk.toString()
  })

  // Response reader: resolves the next complete JSON-RPC line, in order.
  let buffer = ""
  const waiters: ((msg: any) => void)[] = []
  proc.stdout.on("data", (chunk: Buffer) => {
    buffer += chunk.toString()
    let idx: number
    while ((idx = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, idx).trim()
      buffer = buffer.slice(idx + 1)
      if (!line) continue
      let msg: any = null
      try {
        msg = JSON.parse(line)
      } catch {
        continue
      }
      const w = waiters.shift()
      if (w) w(msg)
    }
  })
  next = () =>
    new Promise((resolve) => {
      waiters.push(resolve)
    })

  // Wait for the server to be ready before the first request.
  await new Promise((r) => setTimeout(r, 300))
})

afterAll(() => {
  proc.kill("SIGKILL")
  fs.rmSync(tmpDir, { recursive: true, force: true })
})

function send(id: number, method: string, params: object = {}) {
  proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n")
}

describe("devbot-tools MCP server", () => {
  test("initialize handshake works", async () => {
    send(1, "initialize")
    const res = await next()
    expect(res.id).toBe(1)
    expect(res.result.serverInfo.name).toBe("devbot-tools")
  })

  test("tools/list returns the discovered tool", async () => {
    send(2, "tools/list")
    const res = await next()
    expect(res.id).toBe(2)
    expect(res.result.tools.map((t: any) => t.name)).toContain("fake-tool")
  })

  test("tools/call runs the tool and returns its output", async () => {
    send(3, "tools/call", { name: "fake-tool", arguments: { args: ["a", "b"] } })
    const res = await next()
    expect(res.id).toBe(3)
    expect(res.result.content[0].text).toContain("fake-tool ok: a b")
  })

  test("tool discovery is cached: logged once across list+call, and still works after", async () => {
    // Two more tools/list round-trips (the client pattern from audit-18:
    // batched lists every couple of minutes) and one more call.
    send(4, "tools/list")
    await next()
    send(5, "tools/list")
    const res5 = await next()
    expect(res5.result.tools.map((t: any) => t.name)).toContain("fake-tool")

    send(6, "tools/call", { name: "fake-tool", arguments: { args: [] } })
    const res6 = await next()
    expect(res6.result.content[0].text).toContain("fake-tool ok")

    // stderr is flushed asynchronously; give it a moment before asserting.
    await new Promise((r) => setTimeout(r, 150))
    const discoveries = stderr.match(/discovered \d+ tool\(s\)/g)
    expect(discoveries ?? []).toHaveLength(1)
  })
})
