#!/usr/bin/env bun
// =============================================================================
// src/agentic/k8s/server/kctl-mcp.ts
// One MCP server per Kubernetes cluster, exposing a single `kubectl` tool.
//
// The cluster is fixed at launch (`KCTL_CLUSTER`, set by tools/kctl-mcp.sh from
// the per-cluster manifest), so the agent's tool list names the target: there
// is no context argument to get wrong, and no way to reach another cluster
// through this server.
//
// The command itself is delegated to `kctl.sh exec`, which resolves the
// project's generated kubeconfig, applies that cluster's context, verifies the
// credential references and refuses the kubectl flags that would override the
// target. Keeping that in one place is deliberate: the CLI and the MCP must not
// disagree about which cluster a command ran against.
//
// stdout carries the MCP stream only — every diagnostic goes to stderr, which
// the manifest redirects to .agents/logs/kctl-<cluster>-mcp.log.
// =============================================================================

import * as path from "node:path"

const SERVER_VERSION = "0.1.0"

const CLUSTER = process.env.KCTL_CLUSTER ?? ""
const PROJECT_DIR = process.env.KCTL_PROJECT_DIR || process.cwd()
const DEV_BOT_ROOT = process.env.DEV_BOT_ROOT || ""

// Default wall-clock bound. A kubectl that hangs (a port-forward, a watch, a
// cluster that stopped answering) would otherwise outlive the client's wait and
// keep running invisibly. The override exists for the call an operator knows is
// slow; it is validated, never trusted as-is.
const DEFAULT_TIMEOUT_MS = 120_000
const MAX_TIMEOUT_MS = 2_147_483_647

// kubectl output is injected into a model's context, not into a pager. A
// 40k-line `get pods -A` would crowd out the conversation it is meant to
// inform, so the tail is dropped with an explicit marker. The two streams are
// bounded separately: a failed command's `[exit N]` marker and its error text
// must survive a chatty stdout.
const MAX_STDOUT_CHARS = 100_000
const MAX_STDERR_CHARS = 20_000

const TOOL_NAME = "kubectl"

const CLUSTER_RE = /^[A-Za-z0-9._-]+$/

function log(msg: string): void {
  process.stderr.write(`[kctl-mcp:${CLUSTER || "?"}] ${msg}\n`)
}

// ── Argument handling ───────────────────────────────────────────────────────

// kubectl flags that replace the target this server was pinned to. They are
// refused here as well as in kctl.sh — the two lists must stay identical, and
// kctl-mcp.test.ts fails when they drift.
const FORBIDDEN_FLAGS = new Set([
  "--kubeconfig",
  "-s",
  "--server",
  "--cluster",
  "--user",
  "--token",
  "--as",
  "--as-group",
  "--as-uid",
  "--username",
  "--password",
  "--proxy-url",
  "--tls-server-name",
  "--client-certificate",
  "--client-key",
  "--certificate-authority",
  "--insecure-skip-tls-verify",
])

// kctl.sh's `exec` applies the context, so a caller context is an attempt to
// retarget the call — refused rather than silently overridden (last flag wins
// in kubectl, which would make the attempt succeed).
const FORBIDDEN_CONTEXT_FLAGS = ["--context"]

// `kubectl config` subcommands that WRITE the file. The generated kubeconfig is
// module-owned and rendered again on every reinit; a call that rewrites it
// silently retargets the next call for this cluster (and `kctl run` for a
// human). Read-only subcommands (`view`, `get-contexts`, `current-context`)
// stay available.
const MUTATING_CONFIG_SUBCOMMANDS = new Set([
  "set",
  "set-cluster",
  "set-credentials",
  "set-context",
  "unset",
  "use-context",
  "use", // alias of use-context
  "delete-cluster",
  "delete-context",
  "delete-user",
  "rename-context",
])

// pflag accepts a shorthand's value attached (`-shttps://…`) as well as
// `-s=…`, so the shorthand is matched by prefix; a long flag needs its `=`.
export function matchesFlag(arg: string, flag: string): boolean {
  if (flag === "-s") return arg.startsWith("-s")
  return arg === flag || arg.startsWith(`${flag}=`)
}

export function forbiddenArg(args: string[]): string | null {
  for (const arg of args) {
    for (const flag of [...FORBIDDEN_FLAGS, ...FORBIDDEN_CONTEXT_FLAGS]) {
      if (matchesFlag(arg, flag)) return arg
    }
  }
  return null
}

// `config` need not be the first token: kubectl takes persistent flags before
// the subcommand (`--v=0 config use-context other`), so the token is searched
// for and the subcommand is the first argument after it that is not a flag.
//
// `config view --raw` is refused separately: it prints the kubeconfig's
// credentials (a static cluster's client certificate or token) into the tool
// result, which is model context.
export function configRefusal(args: string[]): string | null {
  const at = args.indexOf("config")
  if (at === -1) return null
  const rest = args.slice(at + 1)
  // Matched by name anywhere after `config`, not "the first non-flag token":
  // inherited flags take separate values (`config --v 0 set-cluster …`), and
  // `use` is an alias of `use-context`. A value that happens to equal a
  // subcommand name is refused too — failing closed on a mutating name costs a
  // retry, while missing one rewrites the generated kubeconfig.
  const sub = rest.find((arg) => MUTATING_CONFIG_SUBCOMMANDS.has(arg))
  if (sub) {
    return `refusing 'kubectl config ${sub}': the kubeconfig is generated by 'devbot reinit' — rewriting it here would retarget every later call for this cluster`
  }
  if (rest.some((arg) => arg === "--raw" || arg.startsWith("--raw="))) {
    return "refusing 'kubectl config --raw': it would print the kubeconfig's credentials into the tool result"
  }
  return null
}

// `args` is the whole kubectl command line, one array element per argument —
// the shape kubectl itself receives. A leading `kubectl`/`k` is the mistake
// this wrapper already handles by exec'ing the binary.
export function normaliseArgs(raw: unknown): { args?: string[]; error?: string } {
  if (!Array.isArray(raw)) {
    return { error: "`args` must be an array of kubectl arguments, e.g. [\"get\", \"pods\", \"-n\", \"core\"]" }
  }
  const args: string[] = []
  for (const value of raw) {
    if (typeof value !== "string") {
      return { error: "`args` must contain only strings — one kubectl argument per element" }
    }
    args.push(value)
  }
  if (args.length === 0) {
    return { error: "`args` is empty — pass the kubectl command, e.g. [\"get\", \"pods\"]" }
  }
  if (args[0] === "kubectl" || args[0] === "k") {
    return {
      error: `drop the leading '${args[0]}' — this tool already runs kubectl, pass its arguments only, e.g. ["get", "pods"]`,
    }
  }
  const forbidden = forbiddenArg(args)
  if (forbidden) {
    return { error: `refusing '${forbidden}': this server is bound to cluster '${CLUSTER}' and applies its context` }
  }
  const configError = configRefusal(args)
  if (configError) {
    return { error: configError }
  }
  return { args }
}

export function timeoutMs(): number {
  const raw = Number(process.env.KCTL_MCP_TIMEOUT_MS)
  if (!Number.isSafeInteger(raw) || raw <= 0 || raw > MAX_TIMEOUT_MS) {
    return DEFAULT_TIMEOUT_MS
  }
  return raw
}

// ── Execution ───────────────────────────────────────────────────────────────

export function kctlScript(devBotRoot: string): string {
  return path.join(devBotRoot, "src", "agentic", "k8s", "kctl.sh")
}

interface RunResult {
  text: string
  isError: boolean
}

// Read a stream to completion, keeping only its first `limit` characters.
// tools-mcp reads its pipes the same way: the reader loop is what Bun's spawn
// streams support on every version this toolkit pins, unlike wrapping them in a
// Response. The stream is drained even past the limit — a full pipe would block
// kubectl — but a chatty command cannot hold hundreds of MB in this process.
async function readCapped(
  stream: ReadableStream<Uint8Array>,
  limit: number,
): Promise<{ text: string; truncated: boolean }> {
  const decoder = new TextDecoder()
  const reader = stream.getReader()
  let out = ""
  let truncated = false
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    const chunk = decoder.decode(value, { stream: true })
    if (truncated) continue
    const room = limit - out.length
    if (chunk.length > room) {
      out += chunk.slice(0, room)
      truncated = true
    } else {
      out += chunk
    }
  }
  if (!truncated) out += decoder.decode()
  return { text: out, truncated }
}

function capped(stream: { text: string; truncated: boolean }, limit: number): string {
  if (!stream.truncated) return stream.text
  return `${stream.text}\n\n… output truncated at ${limit} characters`
}

async function runKubectl(args: string[], stdin: string | undefined): Promise<RunResult> {
  const script = kctlScript(DEV_BOT_ROOT)
  const bound = timeoutMs()

  const proc = Bun.spawn(
    ["bash", script, "exec", CLUSTER, PROJECT_DIR, "--", ...args],
    {
      cwd: PROJECT_DIR,
      stdin: stdin === undefined ? "ignore" : "pipe",
      stdout: "pipe",
      stderr: "pipe",
      detached: true, // own process group, so a timeout can kill kubectl and its children
    },
  )

  if (stdin !== undefined && proc.stdin) {
    proc.stdin.write(stdin)
    await proc.stdin.end()
  }

  const killTree = (signal: "SIGTERM" | "SIGKILL") => {
    try {
      process.kill(-proc.pid, signal)
    } catch {
      try {
        proc.kill(signal)
      } catch {
        /* already exited */
      }
    }
  }

  let timedOut = false
  const termTimer = setTimeout(() => {
    timedOut = true
    killTree("SIGTERM")
  }, bound)
  const killTimer = setTimeout(() => killTree("SIGKILL"), Math.min(bound + 5_000, MAX_TIMEOUT_MS))
  for (const timer of [termTimer, killTimer]) (timer as { unref?: () => void }).unref?.()

  const [stdout, stderr] = await Promise.all([
    readCapped(proc.stdout, MAX_STDOUT_CHARS),
    readCapped(proc.stderr, MAX_STDERR_CHARS),
  ])
  const exitCode = await proc.exited
  clearTimeout(termTimer)
  clearTimeout(killTimer)

  if (timedOut) {
    const detail = capped(stderr, MAX_STDERR_CHARS) || capped(stdout, MAX_STDOUT_CHARS)
    return {
      isError: true,
      text: `kubectl in cluster '${CLUSTER}' was killed after ${bound}ms without finishing.\n${detail}`.trim(),
    }
  }

  // Both streams matter: kubectl writes results to stdout and the context
  // banner (from kctl.sh) to stderr, and a failure may explain itself on
  // either. They are labelled rather than interleaved, because kubectl's error
  // text and its resource output are not in a meaningful order.
  const parts: string[] = []
  const out = capped(stdout, MAX_STDOUT_CHARS)
  const err = capped(stderr, MAX_STDERR_CHARS)
  if (out.trim()) parts.push(out.trimEnd())
  if (err.trim()) parts.push(`[stderr]\n${err.trimEnd()}`)
  if (exitCode !== 0) parts.push(`[exit ${exitCode}]`)

  const text = parts.join("\n") || `kubectl in cluster '${CLUSTER}' completed successfully with no output.`
  return { text, isError: exitCode !== 0 }
}

// ── MCP plumbing ────────────────────────────────────────────────────────────

function toolDefinition() {
  return {
    name: TOOL_NAME,
    description:
      `Run kubectl against the '${CLUSTER}' cluster. The kubeconfig and that cluster's context are applied ` +
      `for you — never pass --context, --kubeconfig or other flags that would retarget the command. ` +
      `\`args\` is kubectl's own argv, one element per argument (e.g. ["get","pods","-n","core"]); ` +
      `do not include the leading \`kubectl\`. Use \`stdin\` for manifest input (e.g. ["apply","-f","-"]). ` +
      `Returns one text string, never { stdout, stderr }: for a command that finished, stdout, then ` +
      `an optional "[stderr]" block, then "[exit N]" on a non-zero exit. A timeout kill returns its ` +
      `own message plus one capped stream; rejected arguments return the message alone. All three ` +
      `set isError.`,
    inputSchema: {
      type: "object",
      properties: {
        args: {
          type: "array",
          items: { type: "string" },
          description:
            "kubectl arguments, one element per argument — e.g. [\"get\",\"pods\",\"-n\",\"core\"] or [\"logs\",\"-n\",\"core\",\"deploy/api\",\"--tail=100\"]",
        },
        stdin: {
          type: "string",
          description: "Optional text piped to kubectl's stdin, for commands that read a manifest (apply -f -)",
        },
      },
      required: ["args"],
      additionalProperties: false,
    },
  }
}

function sendJSON(data: unknown): void {
  process.stdout.write(`${JSON.stringify(data)}\n`)
}

function errorResult(id: unknown, message: string): void {
  sendJSON({
    jsonrpc: "2.0",
    id,
    result: { content: [{ type: "text", text: message }], isError: true },
  })
}

async function handleRequest(msg: string): Promise<void> {
  let req: { jsonrpc?: string; id?: unknown; method?: string; params?: Record<string, unknown> }
  try {
    req = JSON.parse(msg)
  } catch {
    log(`Failed to parse request: ${msg.slice(0, 200)}`)
    return
  }
  if (!req || req.jsonrpc !== "2.0") return

  const { id, method, params } = req

  if (method === "initialize") {
    sendJSON({
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: `kctl-${CLUSTER}`, version: SERVER_VERSION },
      },
    })
    return
  }

  if (method === "notifications/initialized") return

  if (method === "tools/list") {
    sendJSON({ jsonrpc: "2.0", id, result: { tools: [toolDefinition()] } })
    return
  }

  if (method === "tools/call") {
    const name = params?.name as string | undefined
    if (name !== TOOL_NAME) {
      sendJSON({ jsonrpc: "2.0", id, error: { code: -32601, message: `Unknown tool: ${name ?? "(missing)"}` } })
      return
    }

    const callArgs = (params?.arguments as Record<string, unknown>) ?? {}
    const { args, error } = normaliseArgs(callArgs.args)
    if (!args) {
      errorResult(id, error ?? "invalid arguments")
      return
    }
    if (callArgs.stdin !== undefined && typeof callArgs.stdin !== "string") {
      errorResult(id, "`stdin` must be a string")
      return
    }

    const result = await runKubectl(args, callArgs.stdin as string | undefined)
    sendJSON({
      jsonrpc: "2.0",
      id,
      result: { content: [{ type: "text", text: result.text }], isError: result.isError },
    })
    return
  }

  if (method === "ping") {
    sendJSON({ jsonrpc: "2.0", id, result: {} })
    return
  }

  sendJSON({ jsonrpc: "2.0", id, error: { code: -32601, message: `Method not found: ${method}` } })
}

async function main(): Promise<void> {
  if (!CLUSTER || !CLUSTER_RE.test(CLUSTER)) {
    log(`KCTL_CLUSTER is missing or invalid (${JSON.stringify(CLUSTER)}); refusing to start`)
    process.exit(1)
  }
  if (!DEV_BOT_ROOT) {
    log("DEV_BOT_ROOT is not set; refusing to start")
    process.exit(1)
  }

  log(`Starting for project ${PROJECT_DIR} via ${kctlScript(DEV_BOT_ROOT)}`)

  const decoder = new TextDecoder()
  let buffer = ""
  const reader = Bun.stdin.stream().getReader()

  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    const lines = buffer.split("\n")
    buffer = lines.pop() ?? ""
    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed) continue
      await handleRequest(trimmed)
    }
  }
}

if (import.meta.main) {
  main().catch((err) => {
    log(`Fatal error: ${(err as Error).message}`)
    process.exit(1)
  })
}
