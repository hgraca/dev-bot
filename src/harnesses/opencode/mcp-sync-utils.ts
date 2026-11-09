// src/harnesses/opencode/mcp-sync-utils.ts
// Pure helpers for the runtime sync; the plugin
// lives in hooks/. JSONC is edited by span.

import { join } from "node:path"

export type McpStatusLike = { status: string }
export type StatusMap = Record<string, McpStatusLike>
export type Write = { server: string; enabled: boolean }

/** The config value a status implies, or null when not intent. */
export function desiredEnabled(status: string): boolean | null {
  if (status === "connected") return true
  if (status === "disabled") return false
  return null
}

/** Servers whose status changed since the previous poll. */
export function changedServers(prev: StatusMap | null, next: StatusMap): string[] {
  // First poll seeds the baseline, not intent.
  if (prev === null) return []
  return Object.keys(next)
    .filter((name) => prev[name]?.status !== next[name].status)
    .sort()
}

/** Writes to apply, from transitions and the config's values. */
export function planWrites(
  prev: StatusMap | null,
  next: StatusMap,
  configured: Record<string, boolean | null>,
): Write[] {
  const writes: Write[] = []
  for (const server of changedServers(prev, next)) {
    const desired = desiredEnabled(next[server].status)
    if (desired === null) continue
    // Absent: never invent. Null means default on.
    if (!Object.prototype.hasOwnProperty.call(configured, server)) continue
    if ((configured[server] ?? true) === desired) continue
    writes.push({ server, enabled: desired })
  }
  return writes
}

/** The one file `project-for-path` reads. */
export function configTarget(root: string): string {
  return join(root, "opencode.jsonc")
}

/** Global config files, the source of a project override. */
export function globalConfigCandidates(home: string, xdgConfigHome?: string): string[] {
  const base = xdgConfigHome || join(home, ".config")
  return [join(base, "opencode", "opencode.jsonc"), join(base, "opencode", "opencode.json")]
}

export type Span = { start: number; end: number }

function skipTrivia(text: string, i: number): number {
  while (i < text.length) {
    const ch = text[i]
    if (ch === " " || ch === "\t" || ch === "\n" || ch === "\r" || ch === ",") {
      i += 1
      continue
    }
    if (text[i] === "/" && text[i + 1] === "/") {
      const nl = text.indexOf("\n", i)
      i = nl === -1 ? text.length : nl + 1
      continue
    }
    if (text[i] === "/" && text[i + 1] === "*") {
      const close = text.indexOf("*/", i + 2)
      i = close === -1 ? text.length : close + 2
      continue
    }
    break
  }
  return i
}

function skipString(text: string, i: number): number {
  let j = i + 1
  while (j < text.length) {
    if (text[j] === "\\") {
      j += 2
      continue
    }
    if (text[j] === '"') return j + 1
    j += 1
  }
  return j
}

function skipContainer(text: string, i: number): number {
  const open = text[i]
  const close = open === "{" ? "}" : "]"
  let depth = 0
  while (i < text.length) {
    const ch = text[i]
    if (ch === '"') {
      i = skipString(text, i)
      continue
    }
    if (ch === "/" && (text[i + 1] === "/" || text[i + 1] === "*")) {
      i = skipTrivia(text, i)
      continue
    }
    if (ch === open) depth += 1
    else if (ch === close) {
      depth -= 1
      if (depth === 0) return i + 1
    }
    i += 1
  }
  return i
}

function skipValue(text: string, i: number): number {
  const start = skipTrivia(text, i)
  const ch = text[start]
  if (ch === '"') return skipString(text, start)
  if (ch === "{" || ch === "[") return skipContainer(text, start)
  let j = start
  while (j < text.length && !",}] \t\r\n/".includes(text[j])) j += 1
  return j
}

function documentScope(text: string): Span | null {
  const start = skipTrivia(text, 0)
  if (text[start] !== "{") return null
  return { start, end: skipContainer(text, start) }
}

/** The value span of `key` in the object at `scope`. */
export function findMember(text: string, scope: Span, key: string): Span | null {
  if (text[scope.start] !== "{") return null
  let i = skipTrivia(text, scope.start + 1)
  while (i < scope.end - 1) {
    if (text[i] !== '"') return null
    const keyEnd = skipString(text, i)
    let found: string
    try {
      found = JSON.parse(text.slice(i, keyEnd))
    } catch {
      return null
    }
    i = skipTrivia(text, keyEnd)
    if (text[i] !== ":") return null
    const valueStart = skipTrivia(text, i + 1)
    const valueEnd = skipValue(text, valueStart)
    if (found === key) return { start: valueStart, end: valueEnd }
    i = skipTrivia(text, valueEnd)
    if (text[i] === ",") i = skipTrivia(text, i + 1)
  }
  return null
}

function mcpScope(text: string): Span | null {
  const doc = documentScope(text)
  if (!doc) return null
  const span = findMember(text, doc, "mcp")
  return span && text[span.start] === "{" ? span : null
}

/** The raw object text of a declared server, comments included. */
export function serverObjectFrom(text: string, server: string): string | null {
  const mcp = mcpScope(text)
  if (!mcp) return null
  const span = findMember(text, mcp, server)
  if (!span || text[span.start] !== "{") return null
  return text.slice(span.start, span.end)
}

/** A server's `enabled` value: null omitted, undefined undeclared. */
export function serverEnabledFrom(text: string, server: string): boolean | null | undefined {
  const mcp = mcpScope(text)
  if (!mcp) return undefined
  const span = findMember(text, mcp, server)
  if (!span || text[span.start] !== "{") return undefined
  const flag = findMember(text, span, "enabled")
  if (!flag) return null
  const raw = text.slice(flag.start, flag.end).trim()
  return raw === "true" ? true : raw === "false" ? false : undefined
}

function lineIndent(text: string, at: number): string {
  const lineStart = text.lastIndexOf("\n", at - 1) + 1
  return /^[ \t]*/.exec(text.slice(lineStart, at))?.[0] ?? ""
}

/** Set (or add) `enabled` inside the object at `obj`, surgically. */
function setEnabledInObject(text: string, obj: Span, enabled: boolean): { text: string; changed: boolean } {
  const flag = findMember(text, obj, "enabled")
  if (flag) {
    const current = text.slice(flag.start, flag.end).trim()
    if (current === String(enabled)) return { text, changed: false }
    return {
      text: text.slice(0, flag.start) + String(enabled) + text.slice(flag.end),
      changed: true,
    }
  }

  const first = skipTrivia(text, obj.start + 1)
  if (first >= obj.end - 1) {
    // No member: insert before `}`, keep comments.
    const inner = text.slice(obj.start + 1, obj.end - 1)
    const member = inner.includes("\n")
      ? `\n${lineIndent(text, obj.start) + "  "}"enabled": ${String(enabled)}\n${lineIndent(text, obj.end - 1)}`
      : `"enabled":${String(enabled)}`
    return { text: text.slice(0, obj.end - 1) + member + text.slice(obj.end - 1), changed: true }
  }

  const multiline = text.slice(obj.start + 1, first).includes("\n")
  const member = multiline
    ? `\n${lineIndent(text, first)}"enabled": ${String(enabled)},`
    : `"enabled":${String(enabled)},`
  return {
    text: text.slice(0, obj.start + 1) + member + text.slice(obj.start + 1),
    changed: true,
  }
}

/** Flip a declared server's flag. Unknown server: no change. */
export function setServerEnabled(
  text: string,
  server: string,
  enabled: boolean,
): { text: string; changed: boolean } {
  const mcp = mcpScope(text)
  if (!mcp) return { text, changed: false }
  const obj = findMember(text, mcp, server)
  if (!obj || text[obj.start] !== "{") return { text, changed: false }
  return setEnabledInObject(text, obj, enabled)
}

/** Insert a server object (raw text) and set its flag. */
export function insertServer(
  text: string,
  server: string,
  rawObject: string,
  enabled: boolean,
): { text: string; changed: boolean } {
  const existing = setServerEnabled(text, server, enabled)
  if (existing.changed || serverObjectFrom(text, server) !== null) return existing

  const rawScope = documentScope(rawObject)
  if (!rawScope) return { text, changed: false }
  const applied = setEnabledInObject(rawObject, rawScope, enabled)
  const body = applied.text.slice(rawScope.start)
  const trimmed = body.slice(0, skipContainer(body, 0))

  const mcp = mcpScope(text)
  if (!mcp) return insertMcpSection(text, server, trimmed)

  const first = skipTrivia(text, mcp.start + 1)
  if (first >= mcp.end - 1) {
    // No member: insert before `}`, keep comments.
    const inner = text.slice(mcp.start + 1, mcp.end - 1)
    const member = inner.includes("\n")
      ? `\n${lineIndent(text, mcp.start) + "  "}"${server}": ${trimmed}\n${lineIndent(text, mcp.end - 1)}`
      : `"${server}": ${trimmed}`
    return { text: text.slice(0, mcp.end - 1) + member + text.slice(mcp.end - 1), changed: true }
  }
  const multiline = text.slice(mcp.start + 1, first).includes("\n")
  const member = multiline ? `\n${lineIndent(text, first)}"${server}": ${trimmed},` : `"${server}":${trimmed},`
  return {
    text: text.slice(0, mcp.start + 1) + member + text.slice(mcp.start + 1),
    changed: true,
  }
}

function insertMcpSection(text: string, server: string, serverText: string): { text: string; changed: boolean } {
  const doc = documentScope(text)
  if (!doc) return { text, changed: false }
  // Not an object: never duplicate the key.
  if (findMember(text, doc, "mcp")) return { text, changed: false }
  // After `{`: a trailing comment eats a comma.
  const at = doc.start + 1
  const first = skipTrivia(text, at)
  const empty = first >= doc.end - 1
  const indent = empty ? "" : lineIndent(text, first)
  const multiline = !empty && text.slice(at, first).includes("\n")
  const body = empty
    ? `"mcp": {"${server}": ${serverText}}`
    : multiline
      ? `\n${indent}"mcp": {\n${indent}  "${server}": ${serverText}\n${indent}},`
      : `"mcp":{"${server}":${serverText}},`
  return { text: text.slice(0, at) + body + text.slice(at), changed: true }
}
