// src/harnesses/opencode/hooks/mcp-sync.test.ts
// Runtime MCP sync tests (../mcp-sync-utils.ts).
// Only a transition between polls is user intent.

import { describe, expect, test } from "bun:test"
import {
  changedServers,
  configTarget,
  desiredEnabled,
  globalConfigCandidates,
  insertServer,
  planWrites,
  serverEnabledFrom,
  serverObjectFrom,
  setServerEnabled,
} from "../mcp-sync-utils"

const status = (s: string) => ({ status: s })

describe("desiredEnabled", () => {
  test("connected means the session runs it", () => {
    expect(desiredEnabled("connected")).toBe(true)
  })

  test("disabled means the user turned it off", () => {
    expect(desiredEnabled("disabled")).toBe(false)
  })

  test.each(["failed", "needs_auth", "needs_client_registration", "unknown"])(
    "%s is not user intent — no write",
    (s) => {
      expect(desiredEnabled(s)).toBeNull()
    },
  )
})

describe("changedServers", () => {
  test("the first poll is a baseline, never a change", () => {
    expect(changedServers(null, { atlassian: status("connected") })).toEqual([])
  })

  test("reports a server whose status differs", () => {
    expect(changedServers({ atlassian: status("disabled") }, { atlassian: status("connected") })).toEqual([
      "atlassian",
    ])
  })

  test("a server that appears after the baseline counts as a change", () => {
    expect(changedServers({}, { atlassian: status("connected") })).toEqual(["atlassian"])
  })

  test("reports nothing when the map is unchanged", () => {
    expect(changedServers({ atlassian: status("connected") }, { atlassian: status("connected") })).toEqual([])
  })

  test("a server that disappears is not a status change to act on", () => {
    expect(changedServers({ atlassian: status("connected") }, {})).toEqual([])
  })
})

describe("planWrites", () => {
  test("first poll writes nothing even when the config disagrees", () => {
    expect(planWrites(null, { atlassian: status("connected") }, { atlassian: false })).toEqual([])
  })

  test("runtime enable writes true", () => {
    expect(
      planWrites({ atlassian: status("disabled") }, { atlassian: status("connected") }, { atlassian: false }),
    ).toEqual([{ server: "atlassian", enabled: true }])
  })

  test("runtime disable writes false", () => {
    expect(
      planWrites({ atlassian: status("connected") }, { atlassian: status("disabled") }, { atlassian: true }),
    ).toEqual([{ server: "atlassian", enabled: false }])
  })

  test("a transition that matches the config already writes nothing", () => {
    expect(
      planWrites({ atlassian: status("disabled") }, { atlassian: status("connected") }, { atlassian: true }),
    ).toEqual([])
  })

  test("failed and needs_auth never write", () => {
    expect(
      planWrites({ s: status("connected") }, { s: status("failed") }, { s: true }),
    ).toEqual([])
    expect(
      planWrites({ n: status("disabled") }, { n: status("needs_auth") }, { n: false }),
    ).toEqual([])
  })

  test("a server absent from the config is left alone", () => {
    expect(planWrites({ ghost: status("disabled") }, { ghost: status("connected") }, {})).toEqual([])
  })
})

describe("setServerEnabled", () => {
  const base = `{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    // hosted server
    "atlassian": {
      "type": "remote",
      "url": "https://mcp.atlassian.com/v2/mcp",
      "enabled": false
    }
  }
}`

  test("flips an existing flag without touching comments or layout", () => {
    const out = setServerEnabled(base, "atlassian", true)
    expect(out.changed).toBe(true)
    expect(out.text).toContain("// hosted server")
    expect(out.text).toContain('"enabled": true')
    expect(out.text).not.toContain('"enabled": false')
    // Only the literal changed.
    expect(out.text.replace('"enabled": true', '"enabled": false')).toBe(base)
  })

  test("is a no-op when the flag already holds the value", () => {
    expect(setServerEnabled(base, "atlassian", false)).toEqual({ text: base, changed: false })
  })

  test("inserts the flag into a multi-line server that lacks it", () => {
    const text = `{
  "mcp": {
    "atlassian": {
      "type": "remote",
      "url": "https://example.test/mcp"
    }
  }
}`
    const out = setServerEnabled(text, "atlassian", true)
    expect(out.changed).toBe(true)
    expect(out.text).toContain('"enabled": true,')
    // The member lands inside the server object.
    const mcp = serverObjectFrom(out.text, "atlassian")
    expect(mcp).toContain('"enabled": true')
  })

  test("inserts the flag into a single-line server", () => {
    const text = `{"mcp":{"atlassian":{"type":"remote","url":"https://example.test/mcp"}}}`
    const out = setServerEnabled(text, "atlassian", false)
    expect(out.changed).toBe(true)
    expect(serverObjectFrom(out.text, "atlassian")).toBe(
      '{"enabled":false,"type":"remote","url":"https://example.test/mcp"}',
    )
  })

  test("fills an empty server object", () => {
    const text = `{"mcp":{"atlassian":{}}}`
    const out = setServerEnabled(text, "atlassian", true)
    expect(serverObjectFrom(out.text, "atlassian")).toBe('{"enabled":true}')
  })

  test("ignores a server name appearing in a comment or a string", () => {
    const text = `{
  // "atlassian": { "enabled": true }
  "mcp": {
    "atlassian": { "url": "https://x.test/\\"atlassian\\"", "enabled": false },
    "other": { "enabled": true }
  }
}`
    const out = setServerEnabled(text, "atlassian", true)
    expect(serverObjectFrom(out.text, "atlassian")).toContain('"enabled": true')
    expect(serverObjectFrom(out.text, "other")).toContain('"enabled": true')
    expect(out.text).toContain("// \"atlassian\": { \"enabled\": true }")
  })

  test("braces and quotes inside strings do not derail the scan", () => {
    const text = `{
  "mcp": {
    "weird": { "url": "https://x.test/{a}/\\"b\\"", "enabled": false }
  }
}`
    const out = setServerEnabled(text, "weird", true)
    expect(out.changed).toBe(true)
    expect(serverObjectFrom(out.text, "weird")).toContain('"url": "https://x.test/{a}/\\"b\\""')
  })

  test("leaves the document alone when there is no mcp section", () => {
    const text = `{ "model": "x/y" }`
    expect(setServerEnabled(text, "atlassian", true)).toEqual({ text, changed: false })
  })

  test("leaves the document alone when the server is not declared", () => {
    const text = `{ "mcp": { "other": { "enabled": true } } }`
    expect(setServerEnabled(text, "atlassian", true)).toEqual({ text, changed: false })
  })

  test("ignores an enabled key on a sibling server", () => {
    const text = `{"mcp":{"a":{"enabled":false},"b":{"enabled":false}}}`
    const out = setServerEnabled(text, "b", true)
    expect(serverObjectFrom(out.text, "a")).toContain('"enabled":false')
    expect(serverObjectFrom(out.text, "b")).toContain('"enabled":true')
  })

  test("preserves a comment inside an otherwise empty server object", () => {
    const text = `{"mcp":{"a":{ // keep this note\n}}}`
    const out = setServerEnabled(text, "a", true)
    expect(out.text).toContain("// keep this note")
    expect(serverObjectFrom(out.text, "a")).toContain('"enabled": true')
  })
})

describe("serverObjectFrom", () => {
  test("returns the raw object text, comments included", () => {
    const text = `{
  "mcp": {
    "a": {
      // keep me
      "type": "remote"
    }
  }
}`
    expect(serverObjectFrom(text, "a")).toContain("// keep me")
    expect(serverObjectFrom(text, "a")?.trim().startsWith("{")).toBe(true)
  })

  test("returns null when absent", () => {
    expect(serverObjectFrom(`{"mcp":{}}`, "a")).toBeNull()
  })
})

describe("insertServer", () => {
  test("adds a server copied from elsewhere with the flag applied", () => {
    const project = `{
  "mcp": {
    "other": { "enabled": true }
  }
}`
    const out = insertServer(project, "atlassian", `{ "type": "remote", "url": "https://x.test/mpc", "enabled": false }`, true)
    expect(out.changed).toBe(true)
    expect(serverObjectFrom(out.text, "atlassian")).toContain('"url": "https://x.test/mpc"')
    expect(serverObjectFrom(out.text, "atlassian")).toContain('"enabled": true')
    expect(serverObjectFrom(out.text, "other")).toContain('"enabled": true')
  })

  test("preserves {env:VAR} tokens verbatim", () => {
    const out = insertServer(`{"mcp":{}}`, "sent", `{"headers":{"Authorization":"Sentry-Bearer {env:TOKEN}"}}`, true)
    expect(out.text).toContain("{env:TOKEN}")
  })

  test("delegates to setServerEnabled when the server already exists", () => {
    const text = `{"mcp":{"a":{"enabled":false}}}`
    const out = insertServer(text, "a", `{"enabled":false}`, true)
    expect(serverObjectFrom(out.text, "a")).toContain('"enabled":true')
  })

  test("creates the mcp section when absent", () => {
    const out = insertServer(`{\n  "model": "x/y"\n}`, "a", `{"type":"remote"}`, true)
    expect(out.changed).toBe(true)
    expect(serverObjectFrom(out.text, "a")).toContain('"type":"remote"')
    expect(serverObjectFrom(out.text, "a")).toContain('"enabled":true')
  })

  // Strict JSON (opencode.json): no trailing comma.
  test("keeps strict JSON when the mcp section is empty", () => {
    const out = insertServer(`{"mcp":{}}`, "a", `{"type":"remote"}`, true)
    expect(() => JSON.parse(out.text)).not.toThrow()
  })

  test("keeps strict JSON when it must create the mcp section", () => {
    const single = insertServer(`{"model":"x/y"}`, "a", `{"type":"remote"}`, true)
    expect(() => JSON.parse(single.text)).not.toThrow()
    const multi = insertServer(`{\n  "model": "x/y"\n}`, "a", `{"type":"remote"}`, true)
    expect(() => JSON.parse(multi.text)).not.toThrow()
  })

  test("a trailing comment does not defeat creating the mcp section", () => {
    const out = insertServer(`{\n  "model": "x/y" // note\n}`, "a", `{"type":"remote"}`, true)
    expect(out.changed).toBe(true)
    expect(out.text).toContain("// note")
    expect(serverObjectFrom(out.text, "a")).toContain('"type":"remote"')
  })

  test("preserves a comment inside an otherwise empty mcp section", () => {
    const out = insertServer(`{"mcp":{ // servers go here\n}}`, "a", `{"type":"remote"}`, true)
    expect(out.text).toContain("// servers go here")
    expect(serverObjectFrom(out.text, "a")).toContain('"type":"remote"')
  })

  test("refuses to duplicate an mcp key that is not an object", () => {
    const text = `{"mcp":[]}`
    expect(insertServer(text, "a", `{"type":"remote"}`, true)).toEqual({ text, changed: false })
  })

  // Override copies the global file verbatim.
  test("copies a comment-bearing global definition into the target", () => {
    const raw = `{
    // hosted by the vendor
    "type": "remote",
    "url": "https://x.test/mcp"
  }`
    const out = insertServer(`{"mcp":{}}`, "atlassian", raw, true)
    expect(serverObjectFrom(out.text, "atlassian")).toContain("// hosted by the vendor")
    expect(serverObjectFrom(out.text, "atlassian")).toContain('"enabled": true')
  })
})

describe("configTarget", () => {
  test("is the file project-for-path reads", () => {
    expect(configTarget("/p")).toBe("/p/opencode.jsonc")
  })
})

describe("globalConfigCandidates", () => {
  test("uses XDG_CONFIG_HOME when set", () => {
    expect(globalConfigCandidates("/home/u", "/xdg")).toEqual([
      "/xdg/opencode/opencode.jsonc",
      "/xdg/opencode/opencode.json",
    ])
  })

  test("falls back to ~/.config", () => {
    expect(globalConfigCandidates("/home/u")).toEqual([
      "/home/u/.config/opencode/opencode.jsonc",
      "/home/u/.config/opencode/opencode.json",
    ])
  })
})

describe("serverEnabledFrom", () => {
  test("reads a declared boolean flag", () => {
    expect(serverEnabledFrom(`{"mcp":{"a":{"enabled":false}}}`, "a")).toBe(false)
    expect(serverEnabledFrom(`{"mcp":{"a":{"enabled":true}}}`, "a")).toBe(true)
  })

  test("distinguishes omitted (default on) from undeclared", () => {
    expect(serverEnabledFrom(`{"mcp":{"a":{"type":"remote"}}}`, "a")).toBeNull()
    expect(serverEnabledFrom(`{"mcp":{}}`, "a")).toBeUndefined()
    expect(serverEnabledFrom(`{"model":"x"}`, "a")).toBeUndefined()
  })

  test("rejects a non-boolean flag rather than guessing", () => {
    expect(serverEnabledFrom(`{"mcp":{"a":{"enabled":"false"}}}`, "a")).toBeUndefined()
  })

  test("sees past comment trivia", () => {
    expect(serverEnabledFrom(`{"mcp":{"a":{/*x*/"enabled":false}}}`, "a")).toBe(false)
  })

  test("ignores an enabled flag on a sibling server", () => {
    expect(serverEnabledFrom(`{"mcp":{"a":{"enabled":true},"b":{"type":"remote"}}}`, "b")).toBeNull()
  })
})
