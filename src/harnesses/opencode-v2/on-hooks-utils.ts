// src/harnesses/opencode-v2/on-hooks-utils.ts
// Helpers shared between the on-hooks adapter and its unit tests.
//
// IMPORTANT: this file must NOT live under hooks/ — the harness init symlinks
// and registers every .ts under hooks/ as an opencode plugin, and opencode's
// plugin loader invokes EVERY function export as a plugin factory. A plugin
// module (on-hooks.ts) therefore must export only its factory; any helper a
// test needs lives here instead.

import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync } from "fs"
import { dirname, join } from "path"

export interface HookDecl {
  id: string
  event: string
  match?: { file?: string; content?: string; tool?: string[]; command?: string }
  run?: string[]
  /** Path to a TS plugin factory (default export) to load and register — for
   * hook logic that needs the opencode client (e.g. prompt injection, session
   * inspection), which a shell `run` command cannot express. The factory is
   * invoked with the same plugin context as this adapter, and any handlers it
   * returns are merged into this adapter's dispatch. */
  plugin?: string
  blocking?: boolean
  log?: string
  /** Open-code only: skip dispatch when the file.edited is a file *create*
   * (companion file.watcher.updated "add"). Rewriting hooks (formatters) must
   * opt out of creates — normalizing a freshly-written file before the agent's
   * next edit is what lets opencode's fuzzy edit tool splice stale-indentation
   * hunks into the file (audit-48 FAIL-1). Read-only hooks (lint, indexers)
   * leave this unset so they keep firing on creates. */
  skipOnCreate?: boolean
  /** Fold this hook's stdout into the tool result of the edit that triggered it
   * ("tool-result"), so the agent reads the findings in the same turn instead
   * of only finding them in the log later. A host that cannot mutate a tool
   * result (claudecode's python dispatcher) ignores the field and falls back to
   * logging — which is why the hook always keeps its `log`. Surface hooks are
   * driven ONLY from the tool hook: the debounced file.edited dispatch skips
   * them, or every edit would run the command twice. */
  surface?: string
}

// Append a hook's output to a persistent log file (for hooks whose effect is
// otherwise invisible — e.g. a linter that only reports, unlike format/block).
function appendLog(path: string, hookId: string, text: string) {
  try {
    mkdirSync(dirname(path), { recursive: true })
    const ts = new Date().toISOString()
    appendFileSync(path, `[${ts}] ${hookId}\n${text}\n\n`, "utf8")
  } catch {
    // Fail open.
  }
}

// Default hook log path, as a function: opencode's plugin loader rejects any
// module export that is not a function (or {server} object) — a plain string
// export makes the whole plugin fail to load with "Plugin export is not a
// function". Function exports keep the constant importable AND loadable.
export function defaultHookLog(): string {
  return ".agents/logs/hooks.log"
}

// Resolve the global config path for guard hooks (audit-32 FAIL: guards not
// enforced live). The harness exports DEV_BOT_ROOT — not DEVBOT_ROOT — and the
// plugin already computes its own root from its real location, so reading the
// env var alone yielded "" and disabled every guard rule. Prefer the config
// beside the plugin's own root (the dev-bot install, realpath-resolved), then
// the DEV_BOT_ROOT env var, then "" (project-config-only — matches the prior
// no-var behavior).
export function resolveGlobalConfigPath(pluginRoot: string, env: NodeJS.ProcessEnv = process.env): string {
  const besidePlugin = join(pluginRoot, ".devbot.global.jsonc")
  if (existsSync(besidePlugin)) return besidePlugin
  const envRoot = env.DEV_BOT_ROOT
  if (envRoot) return join(envRoot, ".devbot.global.jsonc")
  return ""
}

function stripComments(text: string): string {
  const out: string[] = []
  let i = 0
  let inString = false
  while (i < text.length) {
    const ch = text[i]
    if (inString) {
      out.push(ch)
      if (ch === "\\") {
        out.push(text[i + 1] ?? "")
        i += 2
        continue
      }
      if (ch === '"') inString = false
      i += 1
      continue
    }
    if (ch === '"') {
      inString = true
      out.push(ch)
      i += 1
      continue
    }
    if (ch === "/" && text[i + 1] === "/") {
      const lineEnd = text.indexOf("\n", i)
      i = lineEnd === -1 ? text.length : lineEnd
      continue
    }
    if (ch === "/" && text[i + 1] === "*") {
      const close = text.indexOf("*/", i + 2)
      i = close === -1 ? text.length : close + 2
      continue
    }
    out.push(ch)
    i += 1
  }
  return out.join("")
}

function dropTrailingCommas(text: string): string {
  const out: string[] = []
  let i = 0
  let inString = false
  while (i < text.length) {
    const ch = text[i]
    if (inString) {
      out.push(ch)
      if (ch === "\\") {
        out.push(text[i + 1] ?? "")
        i += 2
        continue
      }
      if (ch === '"') inString = false
      i += 1
      continue
    }
    if (ch === '"') inString = true
    if (ch === ",") {
      let j = i + 1
      while (j < text.length && /\s/.test(text[j])) j += 1
      if (text[j] === "}" || text[j] === "]") {
        i += 1
        continue
      }
    }
    out.push(ch)
    i += 1
  }
  return out.join("")
}

/**
 * Strip `//`, `/* *\/` and trailing commas so a JSONC file parses as JSON.
 *
 * Two passes: a comment following the last member (`"a": false, /* off *\/ }`)
 * leaves a comma the first pass cannot see past, so commas are dropped only
 * once every comment is gone.
 */
export function stripJsonc(text: string): string {
  return dropTrailingCommas(stripComments(text))
}

/**
 * Parse a JSONC file; a missing or malformed file yields `undefined`.
 *
 * A leading BOM is stripped first — the canonical Python reader opens with
 * `utf-8-sig`, and `JSON.parse` rejects a `\uFEFF` prefix, so without this a
 * BOM-authored config would silently read as absent and leave a disabled
 * module's hooks registered.
 */
export function readJsoncFile(path: string): unknown {
  if (!path) return undefined
  try {
    const raw = readFileSync(path, "utf8").replace(/^\uFEFF/, "")
    return JSON.parse(stripJsonc(raw))
  } catch {
    return undefined
  }
}

/**
 * Effective module state for a project.
 *
 * `modules.<name>` in the project config wins over the global one; absent in
 * both means enabled. This mirrors how the CLI resolves module state, so the
 * harness registers an MCP server and its hooks on the same rule — a disabled
 * module used to keep running its hooks, which is why `graphify` still ran a
 * no-op update in the polyrepo root (whose graph is disabled there).
 */
export function moduleEnabled(
  name: string,
  projectRoot: string,
  devbotRoot: string,
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const modulesOf = (path: string): Record<string, unknown> | undefined => {
    const parsed = readJsoncFile(path)
    if (typeof parsed !== "object" || parsed === null) return undefined
    const modules = (parsed as { modules?: unknown }).modules
    if (typeof modules !== "object" || modules === null) return undefined
    return modules as Record<string, unknown>
  }
  const project = modulesOf(join(projectRoot, ".devbot.project.jsonc"))?.[name]
  if (typeof project === "boolean") return project
  const global = modulesOf(resolveGlobalConfigPath(devbotRoot, env))?.[name]
  if (typeof global === "boolean") return global
  return true
}

/**
 * Modules the CLI considers disabled for this project.
 *
 * Asks `_devbot_get_disabled_modules` rather than re-deriving the rule: that
 * function also excludes the non-selected codebase engine, the non-selected
 * memory-search engine and every unselected harness, so two implementations
 * would drift. The paths go in as positional arguments — never interpolated
 * into the script text, where a project path containing `$(...)` would run.
 *
 * Falls back to the plain `modules` map when the resolver cannot run.
 */
export function disabledModules(projectRoot: string, devbotRoot: string): Set<string> {
  const functions = join(devbotRoot, "src", "_shared", "functions.sh")
  if (existsSync(functions)) {
    try {
      const result = Bun.spawnSync([
        "bash",
        "-c",
        'source "$1" >/dev/null 2>&1; _devbot_get_disabled_modules "$2"',
        "devbot-hooks",
        functions,
        projectRoot,
      ])
      const parsed = JSON.parse(result.stdout.toString() || "[]")
      if (Array.isArray(parsed)) return new Set(parsed.map(String))
    } catch {
      // Fall through to the local rule.
    }
  }
  const fallback = new Set<string>()
  const base = join(devbotRoot, "src", "agentic")
  try {
    for (const dir of readdirSync(base)) {
      if (!moduleEnabled(dir, projectRoot, devbotRoot)) fallback.add(dir)
    }
  } catch {
    // No module tree: nothing to disable.
  }
  return fallback
}

// Route a hook's captured output to a persistent log file — its declared
// `log` file, or the shared default. Stderr is appended after stdout, labeled
// [stderr]. Hook output must never reach the plugin process stderr — opencode
// surfaces plugin stderr in the TUI.
// ── Surfacing a hook's output in the tool result (surface: "tool-result") ────
//
// A file.edited hook normally only writes its declared `log`: the agent sees the
// findings when it reads that file, which is a turn later at best. A hook that
// declares `surface` instead has its stdout folded into the tool result of the
// edit that triggered it, so the finding lands in front of the model in the same
// turn — the behaviour Claude Code and Codex get from a post-tool-use hook.
//
// `result` is v1's `output.output` (a string) or v2's `Tool.Result.content`
// (string or content parts); both are mutated in place so the host reads the
// appended text back. Returns false when the shape is unknown, so a host change
// degrades to logging instead of throwing inside the tool hook.
export function appendToToolResult(result: any, text: string): boolean {
  const body = String(text ?? "").trim()
  if (!body) return false
  const content = result?.content
  if (typeof content === "string") {
    result.content = `${content}\n\n${body}`
    return true
  }
  if (Array.isArray(content)) {
    content.push({ type: "text", text: body })
    return true
  }
  if (typeof result?.output === "string") {
    result.output = `${result.output}\n\n${body}`
    return true
  }
  return false
}

export function routeHookOutput(out: { stdout: string; stderr: string; exitCode?: number }, hook: HookDecl, root: string): void {
  const stdout = out.stdout.trim()
  const stderr = out.stderr.trim()
  const parts: string[] = []
  if (stdout) parts.push(stdout)
  if (stderr) parts.push(`[stderr]\n${stderr}`)
  // audit-57 §8 / audit-54 F6: formatters are silent on success, so a
  // stdout/stderr gate left the declared per-hook log (format-*.log) never
  // created and a broken formatter invisible. A hook that ran ALWAYS gets a
  // log entry: output when there is any, an explicit marker when silent, and
  // the exit code on failure.
  if (out.exitCode !== undefined && out.exitCode !== 0) {
    parts.push(`exit=${out.exitCode}`)
  } else if (!parts.length) {
    parts.push("ok (no output)")
  }
  appendLog(join(root, hook.log ?? defaultHookLog()), hook.id, parts.join("\n\n"))
}

export interface CommandResult {
  stdout: string
  stderr: string
  exitCode: number
}

// Serialize and coalesce per-file async work (audit-32 FAIL: format-yml burst
// race — two file.edited events ~1s apart spawned two concurrent format runs
// whose read-modify-write interleaves corrupted the .yml). For each file path
// at most one run executes at a time; an edit arriving while a run is in
// flight marks the file dirty and triggers exactly one trailing run over the
// latest content, so bursts collapse instead of piling up.
export type FileEditGate = (file: string, run: () => Promise<void>) => void

export function createFileEditGate(): FileEditGate {
  const active = new Map<string, { dirty: boolean }>()

  return (file, run) => {
    const existing = active.get(file)
    if (existing) {
      existing.dirty = true
      return
    }
    const state = { dirty: false }
    active.set(file, state)

    const loop = async () => {
      try {
        do {
          state.dirty = false
          try {
            await run()
          } catch {
            // Hook failure — dispatch() logs it. Keep the gate alive so a
            // dirty re-run still happens; the error must not wedge the file.
          }
        } while (state.dirty)
      } finally {
        if (active.get(file) === state) active.delete(file)
      }
    }
    void loop()
  }
}

// ── Create/edit classification (audit-48 FAIL-1: format-on-create corrupts) ─
// opencode's write/edit/apply_patch tools publish file.edited AND a companion
// file.watcher.updated whose event is "add" (create) or "change" (edit).
// file.edited alone cannot distinguish the two (payload: { file }), but the
// adapter needs to — formatting a freshly-written file before the agent's next
// edit silently normalizes it, and opencode's fuzzy edit tool then splices the
// agent's stale-indentation hunk into the normalized file, producing invalid
// YAML that prettier refuses to repair. The resolver pairs each file.edited
// with its companion watcher event so the adapter can skip create dispatches.
export type FileChangeKind = "add" | "change"

export interface CreateKindResolver {
  /** A file.edited arrived for `file`. Resolves `cb` with the write kind once
   * known: the companion file.watcher.updated event, or "change" when none
   * arrives within the settle window (backward-compatible default — versions
   * that publish only file.edited keep dispatching every write). A second
   * onEdited while one is pending replaces the first (latest write wins). */
  onEdited(file: string, cb: (kind: FileChangeKind) => void): void
  /** A file.watcher.updated arrived for `file` (add|change|unlink). Resolves a
   * pending onEdited if one is buffered; otherwise remembers the kind briefly
   * for a file.edited that may arrive out of order. "unlink" cancels any
   * pending onEdited for the file (a deleted file has nothing to dispatch). */
  onWatcher(file: string, kind: FileChangeKind | "unlink"): void
}

export interface CreateKindResolverOptions {
  /** ms to wait for the companion file.watcher.updated before defaulting to
   * "change". Default 250 — the tool publishes both events back-to-back, so a
   * real pair resolves in well under this; the timeout only fires for
   * watcher-less versions. */
  settleMs?: number
  /** ms a watcher kind is remembered for an out-of-order file.edited. Short on
   * purpose: a remembered "add" must never outlive the write it paired with
   * and swallow the format dispatch of the file's first real edit. */
  rememberMs?: number
  now?: () => number
}

export function createKindResolver(opts: CreateKindResolverOptions = {}): CreateKindResolver {
  const settleMs = opts.settleMs ?? 250
  const rememberMs = opts.rememberMs ?? 500
  const now = opts.now ?? Date.now
  const pending = new Map<string, { cb: (kind: FileChangeKind) => void; timer: ReturnType<typeof setTimeout> }>()
  const remembered = new Map<string, { kind: FileChangeKind; at: number }>()

  function forgetExpired(): void {
    if (remembered.size <= 64) return
    const cutoff = now() - rememberMs
    for (const [file, entry] of remembered) if (entry.at < cutoff) remembered.delete(file)
  }

  return {
    onEdited(file, cb) {
      const prior = remembered.get(file)
      if (prior) {
        remembered.delete(file) // consumed — one pairing per write
        if (now() - prior.at <= rememberMs) {
          cb(prior.kind)
          return
        }
      }
      const existing = pending.get(file)
      if (existing) {
        // Latest write wins: replace the callback, keep the original timer.
        existing.cb = cb
        return
      }
      const entry = { cb, timer: null as unknown as ReturnType<typeof setTimeout> }
      entry.timer = setTimeout(() => {
        if (pending.get(file) !== entry) return
        pending.delete(file)
        entry.cb("change")
      }, settleMs)
      pending.set(file, entry)
    },

    onWatcher(file, kind) {
      if (kind === "unlink") {
        const entry = pending.get(file)
        if (entry) {
          clearTimeout(entry.timer)
          pending.delete(file)
        }
        remembered.delete(file)
        return
      }
      const entry = pending.get(file)
      if (entry) {
        clearTimeout(entry.timer)
        pending.delete(file)
        entry.cb(kind)
        return
      }
      forgetExpired()
      remembered.set(file, { kind, at: now() })
    },
  }
}

// ── Rewrite-echo suppression (audit-37 §2: formatter ping-pong) ───────────────
// A format hook that rewrites a file triggers a second file.edited event from
// the watcher; without suppression that echo re-runs every matching hook —
// lint-k8s double-fires and the formatter no-ops on its own output. The
// adapter records the file's content signature after each dispatch; an
// incoming event whose signature matches (within a short window) is the echo
// of the adapter's own rewrite and is dropped, so one user edit runs content
// hooks exactly once. A real edit changes the signature and still dispatches.

export interface RewriteEchoTracker {
  /** Whether (file, sig) matches the adapter's own last rewrite of the file
   * within the window. A match is consumed (one echo per rewrite). */
  isEcho(file: string, sig: string, now?: number): boolean
  /** Record the post-dispatch content signature of a file. */
  record(file: string, sig: string, now?: number): void
}

export function createRewriteEchoTracker(windowMs = 2000): RewriteEchoTracker {
  const written = new Map<string, { sig: string; at: number }>()

  return {
    isEcho(file, sig, now = Date.now()) {
      const prev = written.get(file)
      if (!prev) return false
      written.delete(file)
      if (now - prev.at > windowMs) return false
      return prev.sig === sig
    },
    record(file, sig, now = Date.now()) {
      written.set(file, { sig, at: now })
    },
  }
}

// Decide whether a command.before hook blocks the tool. Fail-closed contract
// (audit-31 §2): a blocking hook whose subprocess fails to execute (non-zero
// exit, missing script/interpreter, unparseable output) must DENY — a guard
// that produced no valid decision must not silently let the command through.
// A non-blocking hook only blocks on an explicit {"blocked": true}.
export function guardDecision(result: CommandResult, blocking?: boolean): { blocked: boolean; message: string } {
  if (!blocking) {
    try {
      const parsed = JSON.parse(result.stdout || "{}")
      if (parsed?.blocked) {
        return { blocked: true, message: parsed.message ?? "guard rule" }
      }
    } catch {
      // Non-JSON output — not blocked.
    }
    return { blocked: false, message: "" }
  }

  if (result.exitCode !== 0) {
    return { blocked: true, message: `guard temporarily unavailable (exited ${result.exitCode})` }
  }
  let parsed: any = {}
  try {
    parsed = JSON.parse(result.stdout || "{}")
  } catch {
    return { blocked: true, message: "guard temporarily unavailable (unparseable output)" }
  }
  if (parsed?.blocked) {
    return { blocked: true, message: parsed.message ?? "guard rule" }
  }
  return { blocked: false, message: "" }
}

// opencode does not export the session id to the AI's shell, so a skill that
// writes per-session artefacts (grade-tools) cannot name its own session. The
// adapter injects it via the shell.env hook (verified to reach bash tool calls).
//
// Which agent wrote a row matters as much — grade-tools records it as the row's
// actor — but the hooks that see the agent name (chat.message, chat.params,
// chat.headers) have no shell environment to write to. chat.params carries it as
// a required field, so cache it there and read it back here.
export const SESSION_ID_ENV = "DEV_BOT_SESSION_ID"
export const AGENT_NAME_ENV = "DEV_BOT_AGENT_NAME"
// Without a bound, a long-lived server accumulates one entry per session it has
// ever seen.
export const MAX_TRACKED_SESSIONS = 512

const agentBySession = new Map<string, string>()

export function rememberAgent(
  sessionID?: string,
  agent?: string,
  cache: Map<string, string> = agentBySession,
): void {
  const id = sessionID?.trim()
  const name = agent?.trim()
  if (!id || !name) return
  // Re-inserting moves the session to the young end, so eviction stays LRU-ish.
  cache.delete(id)
  cache.set(id, name)
  if (cache.size > MAX_TRACKED_SESSIONS) {
    const oldest = cache.keys().next()
    if (!oldest.done) cache.delete(oldest.value)
  }
}

// The MCP server process is shared by every session in one opencode instance,
// so a tool cannot tell which session called it. The tool's own args carry the
// answer once this hook names the caller.
const SESSION_AWARE_TOOLS = new Set(["devbot-tools_session-usage"])

export function injectSessionId(tool: string, sessionID: unknown, args: unknown): boolean {
  const name = String(tool || "").toLowerCase()
  if (!SESSION_AWARE_TOOLS.has(name)) return false
  const id = typeof sessionID === "string" ? sessionID.trim() : ""
  if (!id) return false
  const target = args as { args?: unknown } | null
  if (!target || typeof target !== "object") return false
  const list = Array.isArray(target.args) ? target.args.map(String) : []
  // The hook is the identity boundary: a caller-supplied --session is replaced
  // by the real one, never trusted.
  const kept: string[] = []
  for (let i = 0; i < list.length; i++) {
    if (list[i] === "--session") {
      i += 1
      continue
    }
    if (list[i].startsWith("--session=")) continue
    kept.push(list[i])
  }
  target.args = [...kept, "--session", id]
  return true
}

export function sessionEnvVars(
  sessionID?: string,
  cache: Map<string, string> = agentBySession,
): Record<string, string> {
  const id = sessionID?.trim()
  if (!id) return {}
  const env: Record<string, string> = { [SESSION_ID_ENV]: id }
  const agent = cache.get(id)
  if (agent) env[AGENT_NAME_ENV] = agent
  return env
}

// Shell tools whose command can be prefixed without changing meaning.
const SHELL_TOOLS = new Set(["shell", "bash"])

// Single-quote for the shell that is about to run it: `'` is closed, escaped
// and reopened, so a value can never end the quoting early.
function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`
}

// V2's shell.create.before carries no session, so the identity it exports is
// scoped to the last session that ran a context hook. That is right for the
// primary and wrong for a subagent: its rows get graded under the parent's id
// and agent, silently (audit-03 F2). tool.execute.before *does* carry the real
// session, so the command is stamped with it — an export inside the command
// wins over the environment the shell was created with.
//
// Returns the command unchanged when the shell env already names this session,
// so a primary session's commands are never rewritten.
export function stampShellIdentity(
  tool: string,
  command: string,
  sessionID?: string,
  agent?: string,
  envSessionID?: string,
): string {
  if (!SHELL_TOOLS.has(String(tool || "").toLowerCase())) return command
  const id = sessionID?.trim()
  if (!command || !id) return command
  if (id === String(envSessionID ?? "").trim()) return command
  const name = agent?.trim()
  const prefix = name
    ? `export ${SESSION_ID_ENV}=${shellQuote(id)} ${AGENT_NAME_ENV}=${shellQuote(name)}; `
    : `export ${SESSION_ID_ENV}=${shellQuote(id)}; unset ${AGENT_NAME_ENV}; `
  return prefix + command
}

// The wire: read the command out of the call's own input, rewrite it in place.
// v2 hands execute.before ONE mutable event, so `event.input` is the surface —
// the same one skill-name-resolver rewrites. Returns true when it changed
// something, which is the only observable the hook has.
export function stampShellCall(
  tool: string,
  input: unknown,
  sessionID?: string,
  agent?: string,
  envSessionID?: string,
): boolean {
  const target = input as { command?: unknown } | null | undefined
  if (!target || typeof target.command !== "string") return false
  const stamped = stampShellIdentity(tool, target.command, sessionID, agent, envSessionID)
  if (stamped === target.command) return false
  target.command = stamped
  return true
}

// ── Tool-name canonicalisation (audit-01 FAIL-2) ─────────────────────────────
// The PTY extension is retired, so no tool carries a second name: the live set is
// the shell tool plus V2's built-in file tools. The helper stays as the single
// place a host-supplied name is normalised before it reaches a matcher.
export function canonicalToolName(tool: string, _args?: unknown): string {
  return String(tool || "").toLowerCase()
}

// The guard hook needs one command string per tool. V2 has a single shell tool,
// whose input carries `command`; every other tool has no command to evaluate.
export function commandString(_tool: string, args: unknown): string {
  const a = (args ?? {}) as { command?: unknown }
  return String(a.command ?? "")
}

// ── V2 event payloads and file-writing tools (audit-01 FAIL-1) ───────────────
// A V2 event is `{ id, type, data, location }`; V1 carried the same payload
// under `properties`. Reading only `properties` on a V2 host yielded `{}` for
// every event, which is why the adapter looked like it had no events at all.
export function eventPayload(event: any): Record<string, any> {
  const data = event?.data
  if (data && typeof data === "object") return data as Record<string, any>
  const props = event?.properties
  if (props && typeof props === "object") return props as Record<string, any>
  return {}
}

// Files a tool call will write, from its input. V2 names the field `path`
// (`edit`, `write`), V1 named it `filePath`, and `patch` carries a lark patch
// text whose `*** Update File:` headers name every target.
const FILE_WRITE_TOOLS = new Set(["edit", "write", "patch", "apply_patch"])

export function toolFileTargets(tool: string, input: unknown): string[] {
  const name = canonicalToolName(tool, input)
  if (!FILE_WRITE_TOOLS.has(name)) return []
  const a = (input ?? {}) as { path?: unknown; filePath?: unknown; patchText?: unknown }
  if (name === "patch" || name === "apply_patch") {
    const text = String(a.patchText ?? "")
    const out: string[] = []
    for (const line of text.split("\n")) {
      const match = /^\*\*\* (?:Update|Add|Delete) File: (.+)$/.exec(line.trim())
      if (match) out.push(match[1].trim())
    }
    return out
  }
  const path = a.path ?? a.filePath
  return typeof path === "string" && path ? [path] : []
}

// An empty command has nothing for the guards to evaluate. The guards tool
// exits non-zero on an empty --command, and a blocking guard maps a non-zero
// exit to "blocked" — so a tool call with no command would surface as "guard
// temporarily unavailable" instead of passing through.
export function hasCommand(command: string): boolean {
  return command.trim().length > 0
}
