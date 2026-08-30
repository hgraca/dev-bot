// src/harnesses/opencode/on-hooks-utils.ts
// Helpers shared between the on-hooks adapter and its unit tests.
//
// IMPORTANT: this file must NOT live under hooks/ — the harness init symlinks
// and registers every .ts under hooks/ as an opencode plugin, and opencode's
// plugin loader invokes EVERY function export as a plugin factory. A plugin
// module (on-hooks.ts) therefore must export only its factory; any helper a
// test needs lives here instead.

import { appendFileSync, mkdirSync } from "fs"
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
