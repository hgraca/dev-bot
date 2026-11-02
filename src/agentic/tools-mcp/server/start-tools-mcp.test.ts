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

  // Exits 0 with an empty stdout and a diagnostic on stderr — the shape a
  // fail-open tool has (search-memories on a stale index).
  fs.writeFileSync(
    path.join(toolsDir, "warn-tool.mcp.sh"),
    `#!/usr/bin/env bash
if [[ "\${1:-}" == "mcp-meta" ]]; then
  cat <<'EOF'
{"name":"warn-tool","description":"A stub tool that exits 0 with only a stderr diagnostic","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"}},"required":[]}}}
EOF
  exit 0
fi
echo "WARN: the index is stale" >&2
exit 0
`,
  )

  // Declares its own bound through mcp-meta and outlives the server default,
  // which is set deliberately tiny below so the override is what saves it.
  fs.writeFileSync(
    path.join(toolsDir, "slow-tool.mcp.sh"),
    `#!/usr/bin/env bash
if [[ "\${1:-}" == "mcp-meta" ]]; then
  cat <<'EOF'
{"name":"slow-tool","description":"A stub tool that declares its own timeout","timeoutMs":5000,"parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"}},"required":[]}}}
EOF
  exit 0
fi
sleep 0.6
echo "slow-tool ok"
`,
  )

  // Declares no bound: the server default must still kill it.
  fs.writeFileSync(
    path.join(toolsDir, "hang-tool.mcp.sh"),
    `#!/usr/bin/env bash
if [[ "\${1:-}" == "mcp-meta" ]]; then
  cat <<'EOF'
{"name":"hang-tool","description":"A stub tool with no declared timeout","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"}},"required":[]}}}
EOF
  exit 0
fi
sleep 2
echo "never printed"
`,
  )

  // Declares an unusable bound (0): it must be ignored, not treated as "kill at
  // once", or a typo turns a generous timeout into an immediate failure.
  fs.writeFileSync(
    path.join(toolsDir, "bad-timeout-tool.mcp.sh"),
    `#!/usr/bin/env bash
if [[ "\${1:-}" == "mcp-meta" ]]; then
  cat <<'EOF'
{"name":"bad-timeout-tool","description":"A stub tool with an out-of-range timeout","timeoutMs":0,"parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"}},"required":[]}}}
EOF
  exit 0
fi
sleep 2
echo "never printed"
`,
  )

  // Declares its bound as a string: the contract is a JSON number, so this must
  // be rejected rather than coerced (Number("5000") is a working 5s bound).
  fs.writeFileSync(
    path.join(toolsDir, "string-timeout-tool.mcp.sh"),
    `#!/usr/bin/env bash
if [[ "\${1:-}" == "mcp-meta" ]]; then
  cat <<'EOF'
{"name":"string-timeout-tool","description":"A stub tool declaring its timeout as a string","timeoutMs":"5000","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"}},"required":[]}}}
EOF
  exit 0
fi
sleep 2
echo "never printed"
`,
  )

  // In-process tool: only mcp-meta is meaningful. Its body exits non-zero, so
  // a regression that spawns it instead of dispatching fails the call loudly.
  fs.copyFileSync(
    path.resolve(import.meta.dir, "../tools/heap-snapshot.mcp.sh"),
    path.join(toolsDir, "heap-snapshot.mcp.sh"),
  )

  // Unknown in-process handler: must be hidden,
  // not advertised as a broken tool.
  fs.writeFileSync(
    path.join(toolsDir, "bogus-inproc.mcp.sh"),
    `#!/usr/bin/env bash
if [[ "\${1:-}" == "mcp-meta" ]]; then
  cat <<'EOF'
{"name":"bogus-inproc","description":"A stub tool declaring an unknown in-process handler","inProcess":"no-such-handler","parameters":{"type":"object","properties":{}}}
EOF
  exit 0
fi
echo "bogus-inproc body must never run" >&2
exit 1
`,
  )

  // Empty inProcess is presence of the key, not absence: it must stay hidden
  // and must never fall back to spawning the body.
  fs.writeFileSync(
    path.join(toolsDir, "empty-inproc.mcp.sh"),
    `#!/usr/bin/env bash
if [[ "\${1:-}" == "mcp-meta" ]]; then
  cat <<'EOF'
{"name":"empty-inproc","description":"A stub tool declaring an empty in-process handler","inProcess":"","parameters":{"type":"object","properties":{}}}
EOF
  exit 0
fi
exit 1
`,
  )

  // Inherited Object.prototype names must not pass as handlers.
  fs.writeFileSync(
    path.join(toolsDir, "proto-inproc.mcp.sh"),
    `#!/usr/bin/env bash
if [[ "\${1:-}" == "mcp-meta" ]]; then
  cat <<'EOF'
{"name":"proto-inproc","description":"A stub tool naming an inherited handler","inProcess":"toString","parameters":{"type":"object","properties":{}}}
EOF
  exit 0
fi
exit 1
`,
  )

  proc = spawn("bun", ["run", SERVER], {
    env: { ...process.env, TOOLS_MCP_PROJECT_DIR: tmpDir, TOOLS_MCP_TIMEOUT_MS: "500" },
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

  test("a tool that declares its own timeoutMs outlives the server default", async () => {
    // A datasource reload outlives the 120s default by design: it may pull an
    // image, canary every source and build sidecars. mcp-meta lets it say so.
    send(8, "tools/call", { name: "slow-tool", arguments: { args: [] } })
    const res = await next()
    expect(res.id).toBe(8)
    expect(res.result.isError).toBeUndefined()
    expect(res.result.content[0].text).toContain("slow-tool ok")
  })

  test("a tool without a declared timeout is still bounded by the default", async () => {
    send(9, "tools/call", { name: "hang-tool", arguments: { args: [] } })
    const res = await next()
    expect(res.id).toBe(9)
    expect(res.result.isError).toBe(true)
    expect(res.result.content[0].text).toContain("timed out after 500ms")
  })

  test("an out-of-range timeoutMs is ignored and the default still applies", async () => {
    send(10, "tools/call", { name: "bad-timeout-tool", arguments: { args: [] } })
    const res = await next()
    expect(res.id).toBe(10)
    expect(res.result.isError).toBe(true)
    expect(res.result.content[0].text).toContain("timed out after 500ms")
  })

  test("a non-numeric timeoutMs is rejected rather than coerced", async () => {
    send(11, "tools/call", { name: "string-timeout-tool", arguments: { args: [] } })
    const res = await next()
    expect(res.id).toBe(11)
    expect(res.result.isError).toBe(true)
    expect(res.result.content[0].text).toContain("timed out after 500ms")
  })

  test("a tool that exits 0 with only a stderr diagnostic surfaces it", async () => {
    // The response used to be "Tool 'warn-tool' completed successfully." — an
    // agent calling a fail-open tool then saw an empty result with no reason.
    send(7, "tools/call", { name: "warn-tool", arguments: { args: [] } })
    const res = await next()
    expect(res.id).toBe(7)
    expect(res.result.content[0].text).toContain("WARN: the index is stale")
    expect(res.result.content[0].text).not.toContain("completed successfully")
  })

  test("an in-process tool is listed and dispatches inside the server", async () => {
    // A subprocess has its own heap, so a script
    // would snapshot an empty process.
    send(12, "tools/list")
    const list = await next()
    expect(list.result.tools.map((t: any) => t.name)).toContain("heap-snapshot")

    const out = path.join(tmpDir, "snap.heapsnapshot")
    send(13, "tools/call", { name: "heap-snapshot", arguments: { args: [out] } })
    const res = await next()
    expect(res.id).toBe(13)
    expect(res.result.isError).toBeUndefined()
    expect(res.result.content[0].text).toContain(out)
    expect(res.result.content[0].text).toMatch(/Wrote \d+\.\d MB/)

    // Process memory: owner-only, never the umask default.
    expect(fs.statSync(out).mode & 0o777).toBe(0o600)

    const snapshot = JSON.parse(fs.readFileSync(out, "utf-8"))
    expect(snapshot.snapshot.meta.node_fields).toBeDefined()
    expect(Array.isArray(snapshot.nodes)).toBe(true)
  })

  test("a tool declaring an unknown in-process handler is not advertised", async () => {
    send(14, "tools/list")
    const res = await next()
    expect(res.result.tools.map((t: any) => t.name)).not.toContain("bogus-inproc")

    await new Promise((r) => setTimeout(r, 150))
    expect(stderr).toContain("unknown inProcess handler")
  })

  test("an inherited property name is not a registered handler", async () => {
    send(15, "tools/list")
    const res = await next()
    expect(res.result.tools.map((t: any) => t.name)).not.toContain("proto-inproc")
  })

  test("an empty inProcess value is not advertised and never spawns", async () => {
    send(16, "tools/list")
    const res = await next()
    expect(res.result.tools.map((t: any) => t.name)).not.toContain("empty-inproc")
  })

  test("refuses to write through a pre-existing symlink", async () => {
    // /tmp is world-writable: a guessed name must not be a write primitive.
    const victim = path.join(tmpDir, "victim.txt")
    fs.writeFileSync(victim, "untouched")
    const link = path.join(tmpDir, "evil.heapsnapshot")
    fs.symlinkSync(victim, link)

    send(17, "tools/call", { name: "heap-snapshot", arguments: { args: [link] } })
    const res = await next()
    expect(res.id).toBe(17)
    expect(res.result.isError).toBe(true)
    expect(fs.readFileSync(victim, "utf-8")).toBe("untouched")
  })
})
