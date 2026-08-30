#!/usr/bin/env bun
// =============================================================================
// src/agentic/auto-recover/tools/auto-recover.ts
// Harness-agnostic auto-recovery engine — the single home of the transient-error
// detection, recovery text, and lock/counter rate-limiting logic.
//
// Used by both the opencode plugin (direct import) and the claudecode Stop hook
// (CLI via `bun auto-recover.ts`). The harness only injects the recovery prompt;
// the decision and state live here.
// =============================================================================

import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "fs"
import { basename, dirname, join } from "path"

const LOCK_TTL_MS = 2 * 60 * 1000
const DEFAULT_MAX_ATTEMPTS = 5
const COOLDOWN_BASE_MS = 5_000

export const RECOVERY_TEXT =
  "[devbot-AutoRecover] The previous response was interrupted by a transient " +
  "provider error (mid-stream connection failure). Resume the task you were " +
  "working on from where it left off. Do not restart from scratch and do not " +
  "explain the error — continue silently with the next concrete step."

export const TRANSIENT_RE =
  /(MidStreamFallbackError|APIConnectionError|OpenAIException|ECONNRESET|ETIMEDOUT|socket hang up|stream (?:closed|aborted)|fetch failed|503 |502 |504 |overloaded|assistant message prefill|must end with a user message|SSE read timed out)/i

export interface RecoverResult {
  recover: boolean
  attempt?: number
  maxAttempts?: number
  errorPreview?: string
  recoveryText?: string
}

export function isTransient(msg: string): boolean {
  return TRANSIENT_RE.test(msg)
}

function slug(worktree: string): string {
  return basename(worktree || "default").replace(/[^a-z0-9_-]/gi, "-").toLowerCase()
}

function readDevbotDir(worktree: string): string {
  const cfgPath = join(worktree, ".devbot.project.jsonc")
  if (!existsSync(cfgPath)) return ".agents"
  try {
    const raw = readFileSync(cfgPath, "utf8")
    const stripped = raw.replace(/^\s*\/\/.*$/gm, "")
    return JSON.parse(stripped)?.devbot_dir ?? ".agents"
  } catch {
    return ".agents"
  }
}

function readMaxAttempts(worktree: string): number {
  const cfgPath = join(worktree, ".devbot.project.jsonc")
  if (!existsSync(cfgPath)) return DEFAULT_MAX_ATTEMPTS
  try {
    const raw = readFileSync(cfgPath, "utf8")
    const stripped = raw.replace(/^\s*\/\/.*$/gm, "")
    return JSON.parse(stripped)?.auto_recover?.max_attempts ?? DEFAULT_MAX_ATTEMPTS
  } catch {
    return DEFAULT_MAX_ATTEMPTS
  }
}

/** Decide whether to recover, and if so acquire the lock + bump the counter. */
export function checkAndAcquire(sessionId: string, errorMsg: string, worktree: string): RecoverResult {
  if (!sessionId || !isTransient(errorMsg)) return { recover: false }

  const dbDir = readDevbotDir(worktree)
  const s = slug(worktree)
  const lockFile = join(worktree, `${dbDir}/memory/thinking/.auto-recover-lock-${s}`)
  const counterFile = join(worktree, `${dbDir}/memory/thinking/.auto-recover-attempts-${s}.json`)

  if (existsSync(lockFile)) {
    try {
      const lock = JSON.parse(readFileSync(lockFile, "utf8"))
      const started = new Date(lock.started).getTime()
      if (!Number.isNaN(started) && Date.now() - started < LOCK_TTL_MS) return { recover: false }
    } catch {
      // Corrupt lock — fall through.
    }
  }

  const max = readMaxAttempts(worktree)
  let counter: Record<string, { count: number; lastAt: number }> = {}
  if (existsSync(counterFile)) {
    try {
      counter = JSON.parse(readFileSync(counterFile, "utf8"))
    } catch {
      counter = {}
    }
  }
  const entry = counter[sessionId] ?? { count: 0, lastAt: 0 }

  if (entry.count >= max) return { recover: false }
  const sinceLast = Date.now() - entry.lastAt
  if (entry.lastAt > 0 && sinceLast < COOLDOWN_BASE_MS * Math.pow(2, entry.count)) return { recover: false }

  mkdirSync(dirname(lockFile), { recursive: true })
  writeFileSync(
    lockFile,
    JSON.stringify({ started: new Date().toISOString(), sessionId, attempt: entry.count + 1 }),
    "utf8",
  )
  counter[sessionId] = { count: entry.count + 1, lastAt: Date.now() }
  mkdirSync(dirname(counterFile), { recursive: true })
  writeFileSync(counterFile, JSON.stringify(counter), "utf8")

  return {
    recover: true,
    attempt: entry.count + 1,
    maxAttempts: max,
    errorPreview: errorMsg.slice(0, 200),
    recoveryText: RECOVERY_TEXT,
  }
}

/** Release the recovery lock after the harness has injected the prompt. */
export function releaseLock(worktree: string): void {
  const dbDir = readDevbotDir(worktree)
  const s = slug(worktree)
  const lockFile = join(worktree, `${dbDir}/memory/thinking/.auto-recover-lock-${s}`)
  try {
    unlinkSync(lockFile)
  } catch {
    // Ignore.
  }
}

// ── CLI entry (for shell hooks, e.g. claudecode) ────────────────────────────
if (import.meta.main) {
  const args = process.argv.slice(2)
  const get = (name: string): string | undefined => {
    const i = args.indexOf(name)
    return i !== -1 ? args[i + 1] : undefined
  }

  const mode = args[0]
  if (mode === "--check") {
    const result = checkAndAcquire(
      get("--session-id") ?? "",
      get("--error") ?? "",
      get("--worktree") ?? ".",
    )
    console.log(JSON.stringify(result))
  } else if (mode === "--release") {
    releaseLock(get("--worktree") ?? ".")
    console.log(JSON.stringify({ released: true }))
  } else {
    console.error("Usage: auto-recover.ts --check --session-id <id> --error <msg> --worktree <dir>")
    console.error("       auto-recover.ts --release --worktree <dir>")
    process.exit(1)
  }
}
