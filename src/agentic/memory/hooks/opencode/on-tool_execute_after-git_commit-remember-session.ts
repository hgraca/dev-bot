// remember-session opencode plugin (post-commit variant)
// Two-phase design to avoid mid-response disruption:
//   1. tool.execute.after — detects git commit, writes trigger file
//   2. event (session.idle) — reads trigger, injects capture prompt when idle
//
// This decouples deterministic commit detection from non-disruptive idle-gated
// execution. The trigger file bridges the two phases.
//
// Safety:
// - Dedup by commit hash prevents double-fire from same commit
// - Consolidated lock file (remember-session.locks.json) with 10 min TTL
// - Loop prevention: checks last user message for [DevBot-RememberSession-PostCommit]
// - Fail-open: all errors silently caught and logged
// - Trigger TTL: 5 min — stale triggers discarded (prevents capture from hours-old commits)
//
// Lock TTL rationale: 10 minutes prevents rapid successive captures across
// different commits in the same session.

import type { Plugin } from "@opencode-ai/plugin"
import { existsSync, readFileSync, writeFileSync, mkdirSync, appendFileSync, unlinkSync } from "fs"
import { join, basename, dirname } from "path"
import { execSync } from "child_process"

// ─── Constants ──────────────────────────────────────────────────────────────

const LOCK_TTL_MS = 10 * 60 * 1000 // 10 minutes
const REMEMBER_SESSION_TAG = "[DevBot-RememberSession-PostCommit]"

// ─── Dedup guard (module-level) ──────────────────────────────────────────────
// Keyed by commit hash to prevent double-fire when the same commit triggers
// the hook twice (e.g., plugin registered twice in opencode.jsonc).

const processedCommits = new Set<string>()

// ─── Config reader ────────────────────────────────────────────────────────────

function readDevbotDir(directory: string): string {
  try {
    const cfgPath = join(directory, ".devbot.project.jsonc")
    if (!existsSync(cfgPath)) return ".agents"
    const raw = readFileSync(cfgPath, "utf8")
    const stripped = raw.replace(/^\s*\/\/.*$/gm, "")
    return JSON.parse(stripped)?.devbot_dir ?? ".agents"
  } catch { return ".agents" }
}

function logsDir(directory: string): string {
  return join(directory, readDevbotDir(directory), "logs")
}

// ─── Log file path ────────────────────────────────────────────────────────────
// Writes to <devbot-dir>/logs/remember-session.log alongside the hook-runner log.

function logFilePath(directory: string): string {
  return join(logsDir(directory), "remember-session.log")
}

// ─── Log write helper ──────────────────────────────────────────────────────────
// Appends a line to the log file. Creates the logs directory if needed.
// Fail-open: log write failures are silently ignored.

function logWrite(directory: string, message: string): void {
  try {
    const logPath = logFilePath(directory)
    mkdirSync(dirname(logPath), { recursive: true })
    const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z")
    appendFileSync(logPath, `[${timestamp}] ${message}\n`, "utf8")
  } catch {
    // Fail open — log write failure is not fatal
  }
}

// ─── Slug derivation ─────────────────────────────────────────────────────────
// Uses session ID when available (per-session slugs), falling back to
// worktree/directory basename.

function deriveSlug(worktree: string | undefined, directory: string, sessionId?: string): string {
  if (sessionId) {
    return sessionId.replace(/[^a-z0-9_-]/gi, "-").toLowerCase()
  }
  const raw = basename(worktree || directory || "default")
  return raw.replace(/[^a-z0-9_-]/gi, "-").toLowerCase()
}

// ─── Watermark write ──────────────────────────────────────────────────────────
// Advances the remember-session watermark after a successful capture.
// Writes to <directory>/<devbot-dir>/logs/remember-session.watermark.json
// Uses directory (session project dir) — always available, never undefined.

function writeWatermark(directory: string, sessionId: string): void {
  try {
    const watermarkFile = join(logsDir(directory), "remember-session.watermark.json")
    const timestamp = new Date().toISOString().replace(/\.\d{3}Z$/, "Z")

    mkdirSync(dirname(watermarkFile), { recursive: true })

    let data: Record<string, string> = {}
    try {
      const raw = readFileSync(watermarkFile, "utf8")
      if (raw.trim()) data = JSON.parse(raw)
    } catch {
      // File doesn't exist or is corrupt — start fresh
    }

    data[sessionId] = timestamp

    // Sort by key for consistent output
    const sorted = Object.fromEntries(
      Object.entries(data).sort(([a], [b]) => a.localeCompare(b))
    )

    writeFileSync(watermarkFile, JSON.stringify(sorted, null, 2) + "\n")
  } catch {
    // Fail open — watermark write failure is not fatal
  }
}

// ─── Watermark read ──────────────────────────────────────────────────────────
// Reads the watermark file and returns the last capture timestamp for the
// given sessionId, or null if no watermark exists. Fail-open — returns null
// on any error.

function readWatermark(directory: string, sessionId: string): string | null {
  try {
    const watermarkFile = join(logsDir(directory), "remember-session.watermark.json")
    const raw = readFileSync(watermarkFile, "utf8")
    if (!raw.trim()) return null
    const data = JSON.parse(raw)
    return data[sessionId] || null
  } catch {
    return null
  }
}

// ─── Locks file path (single JSON file) ──────────────────────────────────────
// Consolidated lock file: maps session IDs to timestamps. Replaces per-session
// lock files. Path: <devbot-dir>/logs/remember-session.locks.json

function locksFilePath(directory: string): string {
  return join(logsDir(directory), "remember-session.locks.json")
}

// ─── Read locks ────────────────────────────────────────────────────────────────
// Reads and parses the single locks JSON file. Returns empty object if file
// doesn't exist or is corrupt.

function readLocks(directory: string): Record<string, string> {
  try {
    const path = locksFilePath(directory)
    if (!existsSync(path)) return {}
    const raw = readFileSync(path, "utf8")
    return JSON.parse(raw)
  } catch {
    return {}
  }
}

// ─── Write locks ───────────────────────────────────────────────────────────────
// Writes the locks object to the single JSON file. Creates parent dir if needed.

function writeLocks(directory: string, locks: Record<string, string>): void {
  try {
    const path = locksFilePath(directory)
    mkdirSync(dirname(path), { recursive: true })
    writeFileSync(path, JSON.stringify(locks, null, 2), "utf8")
  } catch {
    // Fail open — lock write failure is not fatal
  }
}

// ─── Is session locked? ───────────────────────────────────────────────────────
// Checks if this session has a fresh lock (within TTL window).

function isSessionLocked(directory: string, sessionId: string): boolean {
  try {
    const locks = readLocks(directory)
    const started = locks[sessionId]
    if (!started) return false
    const age = Date.now() - new Date(started).getTime()
    return age < LOCK_TTL_MS
  } catch {
    return false
  }
}

// ─── Acquire lock ──────────────────────────────────────────────────────────────
// Adds/updates this session's entry in the locks file.

function acquireLock(directory: string, sessionId: string): void {
  const locks = readLocks(directory)
  locks[sessionId] = new Date().toISOString()
  writeLocks(directory, locks)
}

// ─── Release lock ──────────────────────────────────────────────────────────────
// Removes this session's entry from the locks file and logs the removal.

function releaseLock(directory: string, sessionId: string): void {
  const locks = readLocks(directory)
  delete locks[sessionId]
  writeLocks(directory, locks)
  logWrite(directory, `Lock released (session: ${sessionId})`)
}

// ─── Trigger file (bridges tool.execute.after → session.idle) ────────────────
// Path: <devbot-dir>/logs/remember-session.trigger.json
// Written by tool.execute.after when a git commit is detected.
// Read and cleared by the session.idle handler.
// TTL: 5 minutes — stale triggers from old commits are discarded.

const TRIGGER_TTL_MS = 5 * 60 * 1000 // 5 minutes

function triggerFilePath(directory: string): string {
  return join(logsDir(directory), "remember-session.trigger.json")
}

function writeTrigger(directory: string, ctx: CommitContext, sessionId: string): void {
  try {
    const path = triggerFilePath(directory)
    mkdirSync(dirname(path), { recursive: true })
    const data = {
      ...ctx,
      sessionId,
      committedAt: new Date().toISOString(),
    }
    writeFileSync(path, JSON.stringify(data, null, 2), "utf8")
  } catch {
    // Fail open
  }
}

function readTrigger(directory: string): (CommitContext & { sessionId: string; committedAt: string }) | null {
  try {
    const path = triggerFilePath(directory)
    if (!existsSync(path)) return null
    const raw = readFileSync(path, "utf8")
    if (!raw.trim()) return null
    const data = JSON.parse(raw)
    // Discard stale triggers (older than 5 min)
    const age = Date.now() - new Date(data.committedAt).getTime()
    if (age > TRIGGER_TTL_MS) {
      try { unlinkSync(path) } catch {}
      return null
    }
    return data
  } catch {
    return null
  }
}

function clearTrigger(directory: string): void {
  try {
    const path = triggerFilePath(directory)
    if (existsSync(path)) {
      unlinkSync(path)
    }
  } catch {
    // Fail open
  }
}

// ─── Commit context extraction ────────────────────────────────────────────────
// Runs git log -1 after the commit to extract hash, message, author, timestamp,
// and list of files changed. Returns null if git log fails (e.g., no commits).

interface CommitContext {
  hash: string
  message: string
  author: string
  timestamp: string
  files: string[]
}

function extractCommitContext(worktree?: string, directory?: string): CommitContext | null {
  try {
    const cwd = worktree || directory || process.cwd()
    const output = execSync('git log -1 --format="%H%n%s%n%an%n%ai" --name-only', {
      cwd,
      encoding: "utf8",
      timeout: 5000,
    })
    const lines = output.trim().split("\n")
    if (lines.length < 4) return null

    const hash = lines[0]
    const message = lines[1]
    const author = lines[2]
    const timestamp = lines[3]
    // Files start after the format lines (indices 0-3); skip the blank separator
    const files = lines.slice(4).filter((l) => l.trim() !== "")

    return { hash, message, author, timestamp, files }
  } catch {
    return null
  }
}

// ─── Check for existing tag in last user message ────────────────────────────
// Loop prevention: checks if the LAST user message contains the
// [DevBot-RememberSession-PostCommit] tag, meaning the capture just finished.
// Only checks the last user message (not all messages) to avoid
// blocking forever when a previous visible command left the tag.
//
// Message structure: { info: { role }, parts: [...] }

function hasRememberSessionTag(messages: any[]): boolean {
  const allMessages = messages ?? []
  // Find the last user message
  for (let i = allMessages.length - 1; i >= 0; i--) {
    const m = allMessages[i]
    if (m.info?.role !== "user") continue
    const parts = m.parts ?? []
    return parts.some((p: any) => {
      return typeof p.text === "string" && p.text.includes(REMEMBER_SESSION_TAG)
    })
  }
  return false
}

// ─── Is commit successful? ───────────────────────────────────────────────────
// Checks if the git commit completed successfully:
// 1. Check output.metadata?.exitCode === 0
// 2. Fallback: check output.output for fatal git error patterns

function isCommitSuccessful(output: any): boolean {
  // Primary: check exit code in metadata
  const ec = output?.metadata?.exitCode
  if (typeof ec === "number") return ec === 0

  // Fallback: check output text for fatal git errors
  const outStr = String(output?.output ?? "")
  if (/fatal:/i.test(outStr)) return false
  if (/Aborting/i.test(outStr)) return false

  // No errors detected — assume success
  return true
}

// ─── Plugin factory ───────────────────────────────────────────────────────────
// Two-phase design:
//   Phase 1 (tool.execute.after): detect commit, write trigger file — no prompt
//   Phase 2 (event session.idle): read trigger, inject capture prompt when idle
//
// Exported as default so opencode's plugin loader can find it.

export default async function rememberSessionPostCommitPlugin({
  directory,
  worktree,
  client,
}: {
  directory: string
  worktree?: string
  client: any
}): Promise<{ "tool.execute.after": (input: any, output: any) => Promise<void>; event: (args: { event: any }) => Promise<void> }> {

  // ── Phase 1: Detect commit, write trigger ────────────────────────────────
  // Fires on every bash/shell tool completion. When it detects a successful
  // git commit, extracts commit context and writes a trigger file. Does NOT
  // inject any prompt — that happens later when the session goes idle.

  const onToolAfter = async (input: any, output: any) => {
    let commitHash = ""

    try {
      // 1. Tool filter — only respond to bash/shell tool calls
      const tool = String(input?.tool ?? "").toLowerCase()
      if (tool !== "bash" && tool !== "shell") return

      // 2. Command must contain "git commit"
      const command = String(input?.args?.command ?? "")
      if (!/git\s+commit/.test(command)) return

      // 3. Check if commit was successful
      if (!isCommitSuccessful(output)) return

      // 4. Extract session ID
      const sessionId = String(input?.sessionID ?? "")
      if (!sessionId) return

      // 5. Extract commit context via git log -1
      const commitCtx = extractCommitContext(worktree, directory)
      if (!commitCtx) return
      commitHash = commitCtx.hash

      // 6. Dedup guard — keyed by commit hash
      if (processedCommits.has(commitHash)) return
      processedCommits.add(commitHash)

      // 7. Write trigger file (bridges to session.idle handler)
      writeTrigger(directory, commitCtx, sessionId)

      logWrite(directory, `Trigger queued (commit: ${commitHash.substring(0, 8)}, session: ${sessionId})`)
    } catch {
      // Silent failure
      if (commitHash) processedCommits.delete(commitHash)
    }
  }

  // ── Phase 2: Read trigger on idle, inject capture prompt ─────────────────
  // Fires when the session goes idle (orchestrator not actively processing).
  // Reads the trigger file written by Phase 1 and performs the full capture
  // flow: lock, loop check, prompt injection, watermark.

  const onSessionIdle = async ({ event }: { event: any }) => {
    let sessionId = ""
    let commitHash = ""

    try {
      // 1. Event-type filter — only respond to session.idle
      if (event?.type !== "session.idle") return

      // 2. Extract session ID
      sessionId =
        event?.properties?.info?.id ||
        event?.properties?.sessionID ||
        event?.properties?.id
      if (!sessionId) return

      // 3. Read trigger file — skip if no pending trigger
      const trigger = readTrigger(directory)
      if (!trigger) return
      commitHash = trigger.hash

      // 3a. Verify trigger belongs to this session
      if (trigger.sessionId !== sessionId) {
        logWrite(directory, `Trigger skipped: different session (trigger: ${trigger.sessionId}, current: ${sessionId})`)
        clearTrigger(directory)
        return
      }

      // 4. Lock file check
      if (isSessionLocked(directory, sessionId)) {
        logWrite(directory, `Remember-session skipped: lock still fresh (session: ${sessionId})`)
        return
      }

      // 5. Fetch messages for loop prevention check
      let messages: any[] | undefined
      try {
        const { data: msgs } = await client.session.messages({
          path: { id: sessionId },
        })
        messages = msgs ?? []
      } catch {
        // Fail open
      }

      // 5a. Loop prevention
      if (hasRememberSessionTag(messages ?? [])) {
        clearTrigger(directory)
        logWrite(directory, `Remember-session skipped: tag already present (session: ${sessionId})`)
        return
      }

      // 6. Acquire lock
      acquireLock(directory, sessionId)
      logWrite(directory, `Lock acquired (session: ${sessionId}, commit: ${commitHash.substring(0, 8)})`)

      // 6a. Read watermark
      const watermarkTimestamp = readWatermark(directory, sessionId)

      // 6b. Build file list string
      const fileListStr = trigger.files.length > 0
        ? trigger.files.map((f: string) => `  - ${f}`).join("\n")
        : "  (no files listed)"

      // 7. Build capture prompt (inline)
      const capturePrompt = [
        `${REMEMBER_SESSION_TAG}`,
        "",
        "Invoke the `remember-session` skill, execute its steps exactly ONCE, then end your response.",
        "",
        "Capture everything new and worthwhile since the timestamp provided below,",
        "or from the beginning of the session if no timestamp is provided.",
        "",
        "A git commit just completed:",
        `- Hash: ${trigger.hash}`,
        `- Message: ${trigger.message}`,
        `- Author: ${trigger.author}`,
        `- Timestamp: ${trigger.timestamp}`,
        `- Files changed:`,
        fileListStr,
        "",
        `Last capture watermark: ${watermarkTimestamp || "none"}`,
        "",
        "Use the commit details above as additional context for what work was just committed.",
        "",
        "Do NOT emit `<skill>...</skill>` text markers.",
        "Do NOT re-invoke the skill tool a second time.",
        "",
        "SILENCE RULES (this is an automated post-commit capture — the user does not want commentary):",
        "- Emit ZERO narrative text. Tool calls only.",
        "- No status lines (\"Nothing to capture\", \"Captured X\").",
        "- No headers, no preambles, no recaps, no closing summary.",
        "- End the response immediately after the last tool call completes.",
      ].join("\n")

      // 8. Inject capture prompt
      try {
        await client.session.prompt({
          path: { id: sessionId },
          body: {
            parts: [{
              type: "text",
              text: capturePrompt,
              synthetic: true,
              metadata: { hidden: true, source: "remember-session-post-commit-plugin" },
            }],
          },
        })
        logWrite(directory, `Capture prompt injected (session: ${sessionId}, commit: ${commitHash.substring(0, 8)})`)
        logWrite(directory, "Remember-session post-commit capture completed")

        // 8a. Advance watermark
        writeWatermark(directory, sessionId)
      } catch (promptErr) {
        logWrite(directory, `Prompt injection failed: ${String(promptErr).substring(0, 200)}`)
      } finally {
        // 9. Cleanup
        clearTrigger(directory)
        releaseLock(directory, sessionId)
        processedCommits.delete(commitHash)
        logWrite(directory, "Remember-session post-commit finished")
      }
    } catch (err) {
      if (commitHash) processedCommits.delete(commitHash)
      logWrite(directory, "Remember-session post-commit exited with error (silent)")
    }
  }

  return {
    "tool.execute.after": onToolAfter,
    event: onSessionIdle,
  }
}
