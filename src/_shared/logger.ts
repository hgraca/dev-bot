// =============================================================================
// src/_shared/logger.ts
// Shared logging utility for dev-bot.
// Six severity levels: debug, info, notice, warning, error, fatal.
// Uses only Bun built-in APIs — zero dependencies.
//
// Exports:
//   createLogger(opts?) → Logger
//   logger             → pre-built singleton Logger (no client, no module)
//   formatMessage      → formats [ISO] [LEVEL] [module] msg\n
//   writeStderr        → writes to process.stderr with silent failure
//   writeLogFile       → appends to a file (creates dirs) with silent failure
//   injectPrompt       → injects message into chat session (error/fatal only)
//   LogLevel, Logger, LoggerOptions — types
//
// Destination rule: with a `logFile` option the file is the destination
// (stderr stays quiet — no TUI noise); without one, stderr is used.
// =============================================================================

export type LogLevel = 'debug' | 'info' | 'notice' | 'warning' | 'error' | 'fatal'

export interface LoggerOptions {
  /** Opaque OpenCode SDK client — caller owns the type */
  client?: unknown
  /** Session ID required for prompt injection */
  sessionId?: string
  /** Module name prefix in stderr output */
  module?: string
  /**
   * Log file path. When set, the file BECOMES the log destination: every log
   * line is appended to it (parent directories created on demand) and stderr
   * stays quiet, so log output never surfaces in the harness TUI. Prompt
   * injection for error/fatal still fires. Write failures are silently
   * ignored — logging must never break the hook. When unset, stderr is the
   * destination. Hook plugins pass <worktree>/.agents/logs/hooks.log
   * (audit-24 NOTE-2, audit-25 TUI-noise fix).
   */
  logFile?: string
}

export interface Logger {
  debug(msg: string): void
  info(msg: string): void
  notice(msg: string): void
  warn(msg: string): void
  error(msg: string): void
  fatal(msg: string): void
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Format a log line as  [<ISO-8601>] [<LEVEL>] [<module>] <msg>\n
 * Level is uppercased. The special-case 'warning' maps to [WARN].
 * Module tag is omitted when module is absent or empty.
 */
export function formatMessage(level: LogLevel, module: string | undefined, msg: string): string {
  const ts = new Date().toISOString()
  // Map 'warning' → 'WARN' to match expected output prefix
  const lvl = level === 'warning' ? 'WARN' : level.toUpperCase()
  if (module && module.length > 0) {
    return `[${ts}] [${lvl}] [${module}] ${msg}\n`
  }
  return `[${ts}] [${lvl}] ${msg}\n`
}

/**
 * Write text to stderr. Failures are silently ignored (no throw).
 * MUST NOT call any logger methods to avoid infinite recursion.
 */
export function writeStderr(text: string): void {
  try {
    process.stderr.write(text)
  } catch {
    // silently ignore write failures
  }
}

/**
 * Append a formatted log line to a file. Parent directories are created on
 * demand. Failures are silently ignored (no throw) — logging must never break
 * the caller. MUST NOT call any logger methods to avoid infinite recursion.
 */
export function writeLogFile(path: string, text: string): void {
  try {
    const { mkdirSync, appendFileSync } = require("node:fs") as typeof import("node:fs")
    const { dirname } = require("node:path") as typeof import("node:path")
    mkdirSync(dirname(path), { recursive: true })
    appendFileSync(path, text, "utf8")
  } catch {
    // silently ignore write failures
  }
}

/**
 * Inject a message into the chat session via client.session.prompt.
 * Only called for error/fatal levels when client and sessionId are available.
 * Failures are silently ignored (no throw).
 */
export function injectPrompt(client: unknown, sessionId: string, msg: string, level: LogLevel): void {
  try {
    // Cast through unknown → any to avoid requiring @opencode-ai/sdk types
    const c = client as { session: { prompt: (...args: unknown[]) => void } }
    c.session.prompt({
      path: { id: sessionId },
      body: {
        parts: [{
          type: "text",
          text: msg,
          synthetic: true,
          metadata: { hidden: false, source: "devbot-logger", level },
        }],
      },
    })
  } catch {
    // silently ignore injection failures
  }
}

// ── Factory ──────────────────────────────────────────────────────────────────

/**
 * Create a Logger instance with optional configuration.
 * When client and sessionId are provided, error/fatal levels also inject
 * a chat prompt in addition to writing to stderr.
 */
export function createLogger(opts?: LoggerOptions): Logger {
  const client = opts?.client
  const sessionId = opts?.sessionId
  const mod = opts?.module
  const logFile = opts?.logFile

  function makeMethod(level: LogLevel): (msg: string) => void {
    return (msg: string): void => {
      const text = formatMessage(level, mod, msg)
      // When a logFile is configured, the file is the log destination: stderr
      // stays quiet so log lines never surface in the harness TUI (audit-25:
      // plugin-load logger.info calls printed 2 lines before the TUI opened).
      // Without a logFile, stderr is the destination (backwards compatible).
      if (!logFile) {
        writeStderr(text)
      } else {
        writeLogFile(logFile, text)
      }
      // Only error/fatal inject chat prompt — and only when client+sessionId present
      if ((level === 'error' || level === 'fatal') && client && sessionId) {
        injectPrompt(client, sessionId, msg, level)
      }
    }
  }

  return {
    debug: makeMethod('debug'),
    info: makeMethod('info'),
    notice: makeMethod('notice'),
    warn: makeMethod('warning'),
    error: makeMethod('error'),
    fatal: makeMethod('fatal'),
  }
}

// ── Singleton ────────────────────────────────────────────────────────────────

/** Pre-built singleton logger — no client, no sessionId, no module tag. */
export const logger: Logger = createLogger()
