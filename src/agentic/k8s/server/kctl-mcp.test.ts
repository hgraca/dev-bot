// src/agentic/k8s/server/kctl-mcp.test.ts
// Black-box test for one cluster's kctl MCP server.
//
// The properties that matter are the scoping ones: the server exposes exactly
// one tool, the cluster comes from the launch environment (never from a call
// argument), and a call that tries to retarget it is refused before anything
// runs. The stub `kctl.sh` records the argv it was handed, so the assertions
// read the command that would have run.

import { describe, test, expect, beforeAll, afterAll } from "bun:test"
import { spawn } from "node:child_process"
import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"

const SERVER = path.resolve(import.meta.dir, "kctl-mcp.ts")
const CLUSTER = "gete-dev"

let tmpDir: string
let proc: ReturnType<typeof spawn>
let stderr = ""
let next: () => Promise<{ id?: number; result?: any; error?: any }>
let send: (payload: unknown) => void

function rpc(method: string, params?: unknown, id = 1) {
  return { jsonrpc: "2.0", id, method, params }
}

beforeAll(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "kctl-mcp-test-"))

  // A dev-bot root whose kctl.sh does what the call asks for: record the argv,
  // hang, flood, fail, or echo stdin. The server only delegates, so the stub is
  // the whole cluster.
  const script = path.join(tmpDir, "src", "agentic", "k8s", "kctl.sh")
  fs.mkdirSync(path.dirname(script), { recursive: true })
  fs.writeFileSync(
    script,
    `#!/usr/bin/env bash
case "$*" in
  *" -- hang") echo "hanging" ; sleep 30 ;;
  *" -- big")  i=0; while [[ $i -lt 4000 ]]; do echo "line $i padding padding padding padding"; i=$((i+1)); done ;;
  *" -- bigfail") i=0; while [[ $i -lt 4000 ]]; do echo "line $i padding padding padding padding"; i=$((i+1)); done; echo "and it failed" >&2; exit 7 ;;
  *" -- fail") echo "boom" >&2 ; exit 7 ;;
  *" -- stdin") cat ;;
  *) printf 'ARGS: %s\\\\n' "$*" ;;
esac
`,
  )

  proc = spawn("bun", ["run", SERVER], {
    cwd: tmpDir,
    env: {
      ...process.env,
      KCTL_CLUSTER: CLUSTER,
      KCTL_PROJECT_DIR: tmpDir,
      DEV_BOT_ROOT: tmpDir,
    },
    stdio: ["pipe", "pipe", "pipe"],
  })

  let buffer = ""
  const pending: Array<(msg: any) => void> = []
  const queued: any[] = []

  proc.stdout!.on("data", (chunk: Buffer) => {
    buffer += chunk.toString()
    const lines = buffer.split("\n")
    buffer = lines.pop() ?? ""
    for (const line of lines) {
      if (!line.trim()) continue
      const msg = JSON.parse(line)
      const resolve = pending.shift()
      if (resolve) resolve(msg)
      else queued.push(msg)
    }
  })
  proc.stderr!.on("data", (chunk: Buffer) => {
    stderr += chunk.toString()
  })

  send = (payload: unknown) => proc.stdin!.write(`${JSON.stringify(payload)}\n`)
  next = () => {
    const ready = queued.shift()
    if (ready) return Promise.resolve(ready)
    return new Promise((resolve) => pending.push(resolve))
  }

  send(rpc("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "test", version: "1" } }))
  await next()
  send({ jsonrpc: "2.0", method: "notifications/initialized" })
})

afterAll(() => {
  proc?.kill()
  fs.rmSync(tmpDir, { recursive: true, force: true })
})

describe("kctl MCP server", () => {
  test("exposes exactly one tool, named kubectl", async () => {
    send(rpc("tools/list", {}, 2))
    const { result } = await next()

    expect(result.tools).toHaveLength(1)
    expect(result.tools[0].name).toBe("kubectl")
    expect(result.tools[0].inputSchema.required).toEqual(["args"])
    // The cluster is the server's identity, not a parameter a caller sets.
    expect(Object.keys(result.tools[0].inputSchema.properties).sort()).toEqual(["args", "stdin"])
    expect(result.tools[0].description).toContain(CLUSTER)
  })

  test("documents the single-string response shape in the tool description", async () => {
    send(rpc("tools/list", {}, 41))
    const { result } = await next()
    const description: string = result.tools[0].description

    // .stdout off a string is undefined: reads as silence.
    expect(description).toContain("one text string")
    expect(description).toContain("[stderr]")
    expect(description).toContain("[exit N]")
    expect(description).toContain("isError")
    expect(description).toContain("timeout")
  })

  test("runs the call through kctl.sh exec with its own cluster and argv", async () => {
    send(rpc("tools/call", { name: "kubectl", arguments: { args: ["get", "pods", "-n", "core"] } }, 3))
    const { result } = await next()

    expect(result.isError).toBe(false)
    const text = result.content[0].text
    expect(text).toContain(`exec ${CLUSTER} ${tmpDir} -- get pods -n core`)
  })

  test("refuses a leading kubectl without running anything", async () => {
    send(rpc("tools/call", { name: "kubectl", arguments: { args: ["kubectl", "get", "pods"] } }, 4))
    const { result } = await next()

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain("drop the leading 'kubectl'")
    expect(result.content[0].text).not.toContain("ARGS:")
  })

  test("refuses an attached shorthand endpoint override", async () => {
    send(rpc("tools/call", { name: "kubectl", arguments: { args: ["get", "pods", "-shttps://evil.example"] } }, 30))
    const { result } = await next()

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain("refusing '-shttps://evil.example'")
  })

  test("refuses flags that would retarget the call", async () => {
    for (const [id, flag] of [[5, "--context"], [6, "--kubeconfig"], [7, "--server"]] as const) {
      send(rpc("tools/call", { name: "kubectl", arguments: { args: ["get", "pods", `${flag}=x`] } }, id))
      const { result } = await next()

      expect(result.isError).toBe(true)
      expect(result.content[0].text).toContain(`refusing '${flag}=x'`)
      expect(result.content[0].text).not.toContain("ARGS:")
    }
  })

  test("rejects a malformed args value", async () => {
    send(rpc("tools/call", { name: "kubectl", arguments: { args: "get pods" } }, 8))
    const { result } = await next()

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain("`args` must be an array")
  })
})

// ── Behaviour the server exists for ─────────────────────────────────────────
// The delegation tests above prove the argv; these prove what happens to the
// child: it is killed as a whole process group, capped, and reported.

describe("kctl MCP call lifecycle", () => {
  test("forwards stdin to the command", async () => {
    send(rpc("tools/call", { name: "kubectl", arguments: { args: ["stdin"], stdin: "kind: Pod\n" } }, 20))
    const { result } = await next()

    expect(result.isError).toBe(false)
    expect(result.content[0].text).toContain("kind: Pod")
  })

  test("reports a non-zero exit as an error result", async () => {
    send(rpc("tools/call", { name: "kubectl", arguments: { args: ["fail"] } }, 21))
    const { result } = await next()

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain("boom")
    expect(result.content[0].text).toContain("[exit 7]")
  })

  test("caps a chatty output and keeps the exit marker", async () => {
    send(rpc("tools/call", { name: "kubectl", arguments: { args: ["bigfail"] } }, 22))
    const { result } = await next()

    const text = result.content[0].text
    expect(result.isError).toBe(true)
    expect(text).toContain("output truncated at 100000 characters")
    // The failure explanation must survive the caps.
    expect(text).toContain("and it failed")
    expect(text).toContain("[exit 7]")
    expect(text.length).toBeLessThan(125_000)
  })

  test("refuses a mutating kubectl config subcommand", async () => {
    send(rpc("tools/call", {
      name: "kubectl",
      arguments: { args: ["config", "use-context", "another-cluster"] },
    }, 23))
    const { result } = await next()

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain("refusing 'kubectl config use-context'")
    expect(result.content[0].text).not.toContain("ARGS:")
  })

  test("refuses a mutating config subcommand behind a persistent flag", async () => {
    send(rpc("tools/call", {
      name: "kubectl",
      arguments: { args: ["--v=0", "config", "use-context", "another-cluster"] },
    }, 25))
    const { result } = await next()

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain("refusing 'kubectl config use-context'")
  })

  test("refuses the config use alias", async () => {
    send(rpc("tools/call", {
      name: "kubectl",
      arguments: { args: ["config", "use", "another-cluster"] },
    }, 27))
    const { result } = await next()

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain("refusing 'kubectl config use'")
  })

  test("finds the config subcommand behind a flag that takes a value", async () => {
    send(rpc("tools/call", {
      name: "kubectl",
      arguments: { args: ["config", "--v", "0", "use-context", "another-cluster"] },
    }, 28))
    const { result } = await next()

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain("refusing 'kubectl config use-context'")
    expect(result.content[0].text).not.toContain("ARGS:")
  })

  test("refuses config view --raw, which prints credentials", async () => {
    send(rpc("tools/call", { name: "kubectl", arguments: { args: ["config", "view", "--raw"] } }, 26))
    const { result } = await next()

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain("--raw")
    expect(result.content[0].text).not.toContain("ARGS:")
  })

  test("leaves the read-only config subcommands alone", async () => {
    send(rpc("tools/call", { name: "kubectl", arguments: { args: ["config", "view"] } }, 24))
    const { result } = await next()

    expect(result.isError).toBe(false)
    expect(result.content[0].text).toContain("ARGS:")
  })
})

// ── The shell and the server must refuse the same flags ─────────────────────
// kctl.sh is the single implementation of the refusal, but the server checks
// before delegating so a call never reaches the CLI's message as its only
// guard. Two hand-maintained lists drift; this keeps them identical.
describe("override-flag parity with kctl.sh", () => {
  function block(text: string, start: string, end: string): string {
    const from = text.indexOf(start)
    const to = text.indexOf(end, from + start.length)
    if (from === -1 || to === -1) throw new Error(`marker not found: ${start}`)
    return text.slice(from, to)
  }

  test("the server refuses every flag kctl.sh refuses", () => {
    const server = fs.readFileSync(SERVER, "utf8")
    const shell = fs.readFileSync(path.resolve(import.meta.dir, "..", "kctl.sh"), "utf8")

    const serverFlags = new Set(
      server
        .slice(server.indexOf("const FORBIDDEN_FLAGS = new Set(["), server.indexOf("])", server.indexOf("const FORBIDDEN_FLAGS")))
        .match(/"(-s|--[a-z-]+)"/g)
        ?.map((m) => m.replace(/"/g, "")) ?? [],
    )
    const contextBlock = block(server, "const FORBIDDEN_CONTEXT_FLAGS", "\n")
    for (const m of contextBlock.match(/"--[a-z-]+"/g) ?? []) serverFlags.add(m.replace(/"/g, ""))

    const caseBody = block(shell, 'case "${flag}" in', "esac")
    const shellFlags = new Set(caseBody.match(/(^|\s)(-s|--[a-z-]+)(\s|\||\*)/gm)?.map((m) => m.trim().replace(/\s*\|\s*$/, "").replace(/\s*\*$/, "")) ?? [])

    expect([...serverFlags].sort()).toEqual([...shellFlags].sort())
  })
})

// ── The bound on a call ─────────────────────────────────────────────────────
// A kubectl that never returns (a port-forward, a watch, a cluster that stopped
// answering) must not outlive the client's wait and stay running invisibly. The
// bound is per process, so this needs its own instance.
describe("kctl MCP call timeout", () => {
  async function callWithBound(boundMs: string, args: string[]): Promise<{ result: any; elapsed: number }> {
    const started = Date.now()
    const child = spawn("bun", ["run", SERVER], {
      cwd: tmpDir,
      env: {
        ...process.env,
        KCTL_CLUSTER: CLUSTER,
        KCTL_PROJECT_DIR: tmpDir,
        DEV_BOT_ROOT: tmpDir,
        KCTL_MCP_TIMEOUT_MS: boundMs,
      },
      stdio: ["pipe", "pipe", "pipe"],
    })

    const messages: any[] = []
    let buffer = ""
    child.stdout!.on("data", (chunk: Buffer) => {
      buffer += chunk.toString()
      const lines = buffer.split("\n")
      buffer = lines.pop() ?? ""
      for (const line of lines) if (line.trim()) messages.push(JSON.parse(line))
    })

    child.stdin!.write(`${JSON.stringify(rpc("initialize", {}, 1))}\n`)
    child.stdin!.write(`${JSON.stringify(rpc("tools/call", { name: "kubectl", arguments: { args } }, 2))}\n`)

    const deadline = Date.now() + 20_000
    while (messages.length < 2 && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 20))
    }
    child.kill()
    return { result: messages[1]?.result, elapsed: Date.now() - started }
  }

  test("kills the call when the bound expires and says so", async () => {
    const { result, elapsed } = await callWithBound("700", ["hang"])

    expect(result.isError).toBe(true)
    expect(result.content[0].text).toContain("killed after 700ms")
    // Well inside the stub's 30 s sleep: the bound, not the command, ended it.
    expect(elapsed).toBeLessThan(15_000)
  })
})
