// src/agentic/agent-communication/lib/idle.ts
// Pure decisions for the idle pass: the message
// that ended the turn, and the marker to publish.

/** The last assistant message, if any. */
export function lastAssistantMessage(messages: unknown): any | undefined {
  return [...(Array.isArray(messages) ? messages : [])]
    .reverse()
    .find((m: any) => m?.info?.role === "assistant")
}

/** A message's text parts, as the validator reads them. */
export function textParts(message: any): Array<{ type: "text"; text: string }> {
  return (Array.isArray(message?.parts) ? message.parts : [])
    .filter((p: any) => p?.type === "text")
    .map((p: any) => ({ type: "text", text: String(p.text ?? "") }))
}

/**
 * Tool parts flattened for the validator's wait check,
 * whose shape differs between harness generations.
 */
export function waitEvidenceParts(
  message: any,
): Array<{ type: "tool"; tool: string; status: string; background: boolean }> {
  return (Array.isArray(message?.parts) ? message.parts : [])
    .filter((p: any) => p?.type === "tool" && typeof p?.tool === "string")
    .map((p: any) => {
      const status = typeof p?.state === "string" ? p.state : String(p?.state?.status ?? "")
      const input = p?.state?.input ?? p?.input ?? {}
      return {
        type: "tool" as const,
        tool: String(p.tool),
        status,
        background: input?.background === true || input?.background === "true",
      }
    })
}

/**
 * A real result (0 pass, 1 finding) marks the message
 * checked; anything else stays retryable.
 */
export function isCheckedStatus(status: number | null | undefined): boolean {
  return status === 0 || status === 1
}

/** The marker the validator named on its pass line, if it named one. */
export function markerFromOutput(output: string): string | undefined {
  return /terminal marker found: ([A-Z_]+)/.exec(String(output ?? ""))?.[1]
}

/**
 * Only a pass names a marker; a finding (1) clears it,
 * and a failed invocation (2 / null) publishes nothing.
 */
export function markerForReport(
  status: number | null | undefined,
  stdout: string,
): string | undefined {
  return status === 0 ? markerFromOutput(stdout) : undefined
}
