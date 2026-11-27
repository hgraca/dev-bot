import type { Plugin } from "@opencode-ai/plugin"
import { join } from "node:path"
import { createLogger, type Logger } from "../../../../_shared/logger.ts"
import {
  isCheckedStatus,
  lastAssistantMessage,
  markerForReport,
  textParts,
  waitEvidenceParts,
} from "../../lib/idle"
import { runValidator, writeMessageFile, type ValidatorResult } from "../../lib/validator"
import { herdrReportPlan, inHerdrPane, reportToHerdr, type HerdrPlan } from "../../lib/herdr-report"

export interface IdleDeps {
  validate?: (file: string) => Promise<ValidatorResult>
  writeMessage?: (message: any) => { file: string; cleanup(): void }
  report?: (plan: HerdrPlan) => Promise<boolean>
  log?: Logger
}

export function makeOnSessionIdleValidate(deps: IdleDeps = {}): Plugin {
  const validateMessage = deps.validate ?? runValidator
  const writeMessage = deps.writeMessage ?? writeMessageFile
  const report = deps.report ?? reportToHerdr

  return async ({ directory, worktree, client }) => {
    const root = worktree || directory
    const logger =
      deps.log ??
      createLogger({
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

    // A subagent shares the pane: not its turn end.
    async function isSubagent(sessionId: string): Promise<boolean> {
      const get = (client as any)?.session?.get
      if (typeof get !== "function") return false
      try {
        const info = (await get({ path: { id: sessionId } }))?.data
        return Boolean(info?.parentID)
      } catch {
        return true
      }
    }

    async function publish(sessionId: string, result: ValidatorResult): Promise<void> {
      if (!inHerdrPane(process.env)) return
      const plan = herdrReportPlan(markerForReport(result.status, result.stdout), process.env)
      if (!plan || (await isSubagent(sessionId))) return
      await report(plan)
    }

    async function validate(sessionId: string, message: any): Promise<void> {
      const messageId: string | undefined = message?.info?.id
      if (!messageId || checked.get(sessionId) === messageId) return

      let written: { file: string; cleanup(): void } | undefined
      try {
        inFlight.add(sessionId)
        // Text first, then the flattened tool parts the wait check reads.
        const parts = [...textParts(message), ...waitEvidenceParts(message)]
        written = writeMessage({ info: { role: "assistant" }, parts })
        const result = await validateMessage(written.file)
        if (result.status === 1) {
          logger.warn(
            `assistant message failed validation: ${result.stderr.trim() || result.stdout.trim() || "missing terminal marker"}`,
          )
        } else if (!isCheckedStatus(result.status)) {
          logger.warn(`validator exited ${result.status ?? "?"}: ${result.stderr.trim()}`)
          return // a failed invocation must stay retryable
        }
        checked.set(sessionId, messageId)
        await publish(sessionId, result)
      } catch (e) {
        logger.warn(`validator invocation failed: ${e instanceof Error ? e.message : String(e)}`)
      } finally {
        inFlight.delete(sessionId)
        written?.cleanup()
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
}

export const OnSessionIdleValidate = makeOnSessionIdleValidate()

export default OnSessionIdleValidate
