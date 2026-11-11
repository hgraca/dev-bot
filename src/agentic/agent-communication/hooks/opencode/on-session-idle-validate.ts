import type { Plugin } from "@opencode-ai/plugin"
import { execFile } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { createLogger } from "../../../../_shared/logger.ts"

const MODULE_ROOT = join(dirname(fileURLToPath(import.meta.url)), "../..")
const VALIDATOR = join(MODULE_ROOT, "tools/agent-communication.mcp.sh")
const VALIDATOR_TIMEOUT_MS = 10_000

/**
 * Run the validator without blocking the plugin event loop, bounded by a
 * timeout. Resolves to its exit status — number for a real exit, null when the
 * process could not run or timed out.
 */
function runValidator(file: string): Promise<{ status: number | null; stderr: string }> {
  return new Promise((resolve) => {
    execFile(
      "bash",
      [VALIDATOR, "--msg-file", file],
      { timeout: VALIDATOR_TIMEOUT_MS },
      (error, stdout, stderr) => {
        const code = (error as any)?.code
        const status = error ? (typeof code === "number" ? code : null) : 0
        resolve({ status, stderr: String(stderr || stdout || "") })
      },
    )
  })
}

/** The last assistant message in a session's message list, if any. */
export function lastAssistantMessage(messages: unknown): any | undefined {
  return [...(Array.isArray(messages) ? messages : [])]
    .reverse()
    .find((m: any) => m?.info?.role === "assistant")
}

/** The text parts of a message, shaped for the validator's message JSON. */
export function textParts(message: any): Array<{ type: "text"; text: string }> {
  return (Array.isArray(message?.parts) ? message.parts : [])
    .filter((p: any) => p?.type === "text")
    .map((p: any) => ({ type: "text", text: String(p.text ?? "") }))
}

/**
 * Whether a validator exit status is a real result (pass 0 or finding 1) that
 * marks the message as checked. Any other status — 2, or null on a spawn
 * failure — is a failed invocation and must stay retryable.
 */
export function isCheckedStatus(status: number | null | undefined): boolean {
  return status === 0 || status === 1
}

export const OnSessionIdleValidate: Plugin = async ({ directory, worktree, client }) => {
  const root = worktree || directory
  const logger = createLogger({
    client,
    module: "agent-communication",
    logFile: join(root, ".agents/logs/agent-communication.log"),
  })

  // sessionId -> the assistant message id already validated.
  const checked = new Map<string, string>()
  // sessionId -> a validation run is in flight right now.
  const inFlight = new Set<string>()
  // sessionId -> the newest message that arrived while a run was in flight.
  const pending = new Map<string, any>()

  async function validate(sessionId: string, message: any): Promise<void> {
    const messageId: string | undefined = message?.info?.id
    if (!messageId || checked.get(sessionId) === messageId) return

    let dir: string | undefined
    try {
      inFlight.add(sessionId)
      const parts = textParts(message)
      dir = mkdtempSync(join(tmpdir(), "devbot-agent-communication-"))
      const file = join(dir, "message.json")
      writeFileSync(file, JSON.stringify({ info: { role: "assistant" }, parts }), "utf8")
      const result = await runValidator(file)
      if (result.status === 1) {
        logger.warn(
          `assistant message failed validation: ${result.stderr.trim() || "missing terminal marker"}`,
        )
      } else if (!isCheckedStatus(result.status)) {
        logger.warn(`validator exited ${result.status ?? "?"}: ${result.stderr.trim()}`)
        return // a failed invocation must stay retryable
      }
      checked.set(sessionId, messageId)
    } catch (e) {
      logger.warn(`validator invocation failed: ${e instanceof Error ? e.message : String(e)}`)
    } finally {
      inFlight.delete(sessionId)
      if (dir) {
        try {
          rmSync(dir, { recursive: true, force: true })
        } catch {
          // best effort
        }
      }
      // Coalesce: a newer turn may have gone idle while this run was busy —
      // validate it now instead of dropping it.
      const queued = pending.get(sessionId)
      if (queued) {
        pending.delete(sessionId)
        await validate(sessionId, queued)
      }
    }
  }

  return {
    event: async ({ event }: { event: any }) => {
      if (event?.type !== "session.idle") return
      const sessionId =
        event?.properties?.sessionID || event?.properties?.info?.id || event?.properties?.id
      if (!sessionId) return

      let messages: any[] = []
      try {
        const data = (await client.session.messages({ path: { id: sessionId } }))?.data
        messages = Array.isArray(data) ? data : []
      } catch {
        return // messages unavailable — the next idle will retry
      }

      const last = lastAssistantMessage(messages)
      const messageId: string | undefined = last?.info?.id
      if (!last || !messageId) return
      if (checked.get(sessionId) === messageId) return
      if (inFlight.has(sessionId)) {
        pending.set(sessionId, last)
        return
      }
      await validate(sessionId, last)
    },
  }
}

export default OnSessionIdleValidate
