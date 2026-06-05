import type { Plugin } from "@opencode-ai/plugin"
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "fs"
import { basename, dirname, join } from "path"
import { createLogger } from "../../../../_shared/logger.ts"

const LOCK_TTL_MS = 2 * 60 * 1000
const COUNTER_TTL_MS = 30 * 60 * 1000
const DEFAULT_MAX_ATTEMPTS = 5
const COOLDOWN_BASE_MS = 5_000

const RECOVERY_TEXT =
  "[devbot-AutoRecover] The previous response was interrupted by a transient " +
  "provider error (mid-stream connection failure). Resume the task you were " +
  "working on from where it left off. Do not restart from scratch and do not " +
  "explain the error — continue silently with the next concrete step."

const TRANSIENT_RE =
  /(MidStreamFallbackError|APIConnectionError|OpenAIException|ECONNRESET|ETIMEDOUT|socket hang up|stream (?:closed|aborted)|fetch failed|503 |502 |504 |overloaded|assistant message prefill|must end with a user message|SSE read timed out)/i

function worktreeSlug(worktree?: string, directory?: string): string {
  const raw = basename(worktree || directory || "default")
  return raw.replace(/[^a-z0-9_-]/gi, "-").toLowerCase()
}

function readDevbotDir(directory: string): string {
  const cfgPath = join(directory, ".devbot.project.jsonc")
  if (!existsSync(cfgPath)) return ".agents"
  try {
    const raw = readFileSync(cfgPath, "utf8")
    const stripped = raw.replace(/^\s*\/\/.*$/gm, "")
    return JSON.parse(stripped)?.devbot_dir ?? ".agents"
  } catch { return ".agents" }
}

function readMaxAttempts(directory: string): number {
  const cfgPath = join(directory, ".devbot.project.jsonc")
  if (!existsSync(cfgPath)) return DEFAULT_MAX_ATTEMPTS
  try {
    const raw = readFileSync(cfgPath, "utf8")
    const stripped = raw.replace(/^\s*\/\/.*$/gm, "")
    return JSON.parse(stripped)?.auto_recover?.max_attempts ?? DEFAULT_MAX_ATTEMPTS
  } catch { return DEFAULT_MAX_ATTEMPTS }
}

export const OnSessionErrorAutoRecover: Plugin = async ({ directory, worktree, client }) => {
  const logger = createLogger({ client, module: "auto-recover" })
  return {
    event: async ({ event }: { event: any }) => {
      if (event.type !== "session.error") return

      const sessionId = event?.properties?.sessionID || event?.properties?.info?.id || event?.properties?.id
      const sessionLogger = createLogger({ client, sessionId, module: "auto-recover" })
      if (!sessionId) return

      const errMsg: string = event?.properties?.error?.message || event?.properties?.error?.data?.message || event?.properties?.message || ""
      if (!TRANSIENT_RE.test(errMsg)) return

      const slug = worktreeSlug(worktree, directory)
      const dbDir = readDevbotDir(directory)
      const lockFile = join(directory, `${dbDir}/memory/thinking/.auto-recover-lock-${slug}`)
      const counterFile = join(directory, `${dbDir}/memory/thinking/.auto-recover-attempts-${slug}.json`)

      // Lock check
      if (existsSync(lockFile)) {
        try {
          const lock = JSON.parse(readFileSync(lockFile, "utf8"))
          if (Date.now() - new Date(lock.started).getTime() < LOCK_TTL_MS) return
        } catch (e) { sessionLogger.debug(`auto-recover lock file parse failed: ${e instanceof Error ? e.message : String(e)} — falling through`) }
      }

      // Counter check
      const max = readMaxAttempts(directory)
      let counter: Record<string, any> = {}
      if (existsSync(counterFile)) {
        try { counter = JSON.parse(readFileSync(counterFile, "utf8")) } catch (e) { sessionLogger.debug(`auto-recover counter file parse failed: ${e instanceof Error ? e.message : String(e)}`) }
      }
      const entry = counter[sessionId] ?? { count: 0, lastAt: 0 }

      if (entry.count >= max) return

      const sinceLast = Date.now() - entry.lastAt
      if (entry.lastAt > 0 && sinceLast < COOLDOWN_BASE_MS * Math.pow(2, entry.count)) return

      // Acquire lock and bump counter
      mkdirSync(dirname(lockFile), { recursive: true })
      writeFileSync(lockFile, JSON.stringify({ started: new Date().toISOString(), sessionId, attempt: entry.count + 1 }), "utf8")
      counter[sessionId] = { count: entry.count + 1, lastAt: Date.now() }
      mkdirSync(dirname(counterFile), { recursive: true })
      writeFileSync(counterFile, JSON.stringify(counter), "utf8")

      // Send prompt
      try {
        await new Promise((r) => setTimeout(r, 1500))
        await client.session.prompt({
          path: {id: sessionId},
          body: {
            parts: [{
              type: "text",
              text: RECOVERY_TEXT,
              synthetic: true,
              metadata: {
                hidden: true,
                source: "auto-recover-plugin",
                attempt: entry.count + 1,
                maxAttempts: max,
                errorPreview: errMsg.slice(0, 200)
              }
            }]
          },
        })
      } catch (e) { sessionLogger.error(`auto-recover prompt injection failed: ${e instanceof Error ? e.message : String(e)}`) }

      // Release lock
      try { unlinkSync(lockFile) } catch { /* ignore */ }
    },
  }
}
