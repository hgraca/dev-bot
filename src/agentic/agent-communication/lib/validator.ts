// src/agentic/agent-communication/lib/validator.ts
// The validator call every harness path shares,
// with its message file and bounded run.

import { execFile } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const MODULE_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..")
export const VALIDATOR = join(MODULE_ROOT, "tools/agent-communication.mcp.sh")
export const VALIDATOR_TIMEOUT_MS = 10_000

export interface ValidatorResult {
  status: number | null
  stdout: string
  stderr: string
}

/**
 * Run the validator without blocking the plugin event loop, bounded by a
 * timeout. Resolves to its exit status — number for a real exit, null when the
 * process could not run or timed out.
 */
export function runValidator(file: string): Promise<ValidatorResult> {
  return new Promise((resolve) => {
    execFile(
      "bash",
      [VALIDATOR, "--msg-file", file, "--require-wait"],
      { timeout: VALIDATOR_TIMEOUT_MS },
      (error, stdout, stderr) => {
        const code = (error as any)?.code
        const status = error ? (typeof code === "number" ? code : null) : 0
        resolve({ status, stdout: String(stdout || ""), stderr: String(stderr || "") })
      },
    )
  })
}

/** Write a message as the validator reads it, and remove the file afterwards. */
export function writeMessageFile(message: any): { file: string; cleanup(): void } {
  const dir = mkdtempSync(join(tmpdir(), "devbot-agent-communication-"))
  const file = join(dir, "message.json")
  writeFileSync(file, JSON.stringify(message), "utf8")
  return {
    file,
    cleanup: () => {
      try {
        rmSync(dir, { recursive: true, force: true })
      } catch {
        // best effort
      }
    },
  }
}
