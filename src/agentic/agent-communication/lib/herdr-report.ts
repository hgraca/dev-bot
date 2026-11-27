// src/agentic/agent-communication/lib/herdr-report.ts
// Display-only pane metadata: a token, never state.

import { execFile } from "node:child_process"

export interface HerdrPlan {
  command: string
  args: string[]
}

const REPORT_TIMEOUT_MS = 2_000

/** Whether this process runs inside a herdr pane. */
export function inHerdrPane(env: Record<string, string | undefined>): boolean {
  return env.HERDR_ENV === "1" && Boolean(env.HERDR_PANE_ID)
}

/**
 * The report command, or undefined outside a herdr pane.
 * An empty marker clears the token.
 */
export function herdrReportPlan(
  marker: string | undefined,
  env: Record<string, string | undefined>,
): HerdrPlan | undefined {
  const pane = env.HERDR_PANE_ID
  if (!inHerdrPane(env) || !pane) return undefined
  return {
    command: env.HERDR_BIN_PATH || "herdr",
    args: [
      "pane",
      "report-metadata",
      pane,
      "--source",
      "devbot",
      "--token",
      `devbot=${marker ?? ""}`,
    ],
  }
}

type Run = (command: string, args: string[]) => boolean | Promise<boolean>

/** A bounded run: a wedged herdr must not hold the idle pass open. */
export function herdrRun(timeoutMs = REPORT_TIMEOUT_MS): Run {
  return (command, args) =>
    new Promise((resolve) => {
      execFile(command, args, { timeout: timeoutMs }, (error) => resolve(!error))
    })
}

/** Best effort: a herdr hiccup must never affect the turn. */
export async function reportToHerdr(
  plan: HerdrPlan | undefined,
  execute: Run = herdrRun(),
): Promise<boolean> {
  if (!plan) return false
  try {
    return await execute(plan.command, plan.args)
  } catch {
    return false
  }
}
