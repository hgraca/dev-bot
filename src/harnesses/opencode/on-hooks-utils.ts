// src/harnesses/opencode/on-hooks-utils.ts
// Helpers shared between the on-hooks adapter and its unit tests.
//
// IMPORTANT: this file must NOT live under hooks/ — the harness init symlinks
// and registers every .ts under hooks/ as an opencode plugin, and opencode's
// plugin loader invokes EVERY function export as a plugin factory. A plugin
// module (on-hooks.ts) therefore must export only its factory; any helper a
// test needs lives here instead.

import { appendFileSync, existsSync, mkdirSync } from "fs"
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

// Route a hook's captured output to a persistent log file — its declared
// `log` file, or the shared default. Stderr is appended after stdout, labeled
// [stderr]. Hook output must never reach the plugin process stderr — opencode
// surfaces plugin stderr in the TUI.
export function routeHookOutput(out: { stdout: string; stderr: string }, hook: HookDecl, root: string): void {
  const stdout = out.stdout.trim()
  const stderr = out.stderr.trim()
  if (!stdout && !stderr) return
  const parts: string[] = []
  if (stdout) parts.push(stdout)
  if (stderr) parts.push(`[stderr]\n${stderr}`)
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
