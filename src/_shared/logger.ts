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
//   injectPrompt       → injects message into chat session (error/fatal only)
//   LogLevel, Logger, LoggerOptions — types
// =============================================================================

export type LogLevel = 'debug' | 'info' | 'notice' | 'warning' | 'error' | 'fatal'

export interface LoggerOptions {
  /** Opaque OpenCode SDK client — caller owns the type */
  client?: unknown
  /** Session ID required for prompt injection */
  sessionId?: string
  /** Module name prefix in stderr output */
  module?: string
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

  function makeMethod(level: LogLevel): (msg: string) => void {
    return (msg: string): void => {
      const text = formatMessage(level, mod, msg)
      writeStderr(text)
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
