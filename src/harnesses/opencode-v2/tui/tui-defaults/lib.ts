// =============================================================================
// src/harnesses/opencode/tui-defaults/lib.ts
// The pure logic behind dev-bot's TUI defaults, kept out of the plugin wiring so
// it can be tested without a host. The wiring (index.ts) is a single call.
// =============================================================================

/**
 * The kv key opencode reads tool-details visibility from. Its built-in default
 * is `true` (details shown). Kept beside the logic so the plugin and its tests
 * cannot drift from the key opencode actually uses.
 */
export const TOOL_DETAILS_KEY = "tool_details_visibility"

/**
 * The slice of `api.kv` this plugin needs. Structural, so a fake stands in for
 * the host in tests.
 */
export interface Kv {
  get(key: string, fallback?: unknown): unknown
  set(key: string, value: unknown): void
}

/** The slice of the TUI plugin API this plugin uses. */
export interface TuiPluginApi {
  kv: Kv
}

/**
 * Seed dev-bot's "tool details hidden" default, but only when the user has not
 * configured one: a key already present in kv — `true` or `false` — is an
 * explicit choice and is left untouched. Returns whether it wrote.
 */
export function seedToolDetailsDefault(kv: Kv): boolean {
  if (kv.get(TOOL_DETAILS_KEY) !== undefined) return false
  kv.set(TOOL_DETAILS_KEY, false)
  return true
}
