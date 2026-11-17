// =============================================================================
// src/harnesses/opencode-v2/hooks/pty/rpc.ts
// The contract between the PTY server part and its TUI part.
//
// The two parts run in different processes and share no memory, so the sidebar
// reads the session list through this RPC — registered by index.ts, called by
// tui.ts. Both parts import this module, which is why it is an `exports["./rpc"]`
// part of the plugin package: that is the export the host looks for.
//
// Deliberately import-free: the TUI process provides `@opencode/plugin/tui` to a
// plugin module and nothing else, so a schema helper imported here would fail to
// resolve there. `Rpc.define` is an identity function, and a plain JSON Schema
// object is a valid definition, so the contract needs no import at all.
// =============================================================================

export type PtyStatus = "running" | "exited" | "killed"

/** One PTY session, as a client sees it.
 *
 *  Matches the v1 monitor's info shape (title, command, workdir, status, pid,
 *  exitCode, createdAt, exitAt, lineCount) plus `parentSessionId`, so a client
 *  can attribute a session to the agent session that spawned it and filter by
 *  it — the change proposed upstream in shekohex/opencode-pty#91.
 *
 *  There is no `args`: the tools take one command line, so splitting it back
 *  into argv would invent a shape the session never had. */
export interface PtySessionInfo {
  id: string
  title: string
  command: string
  workdir: string
  status: PtyStatus
  pid: number
  exitCode: number | null
  /** ISO timestamp of the child's exit, null while it runs. */
  exitAt: string | null
  /** ISO timestamp of the spawn. */
  createdAt: string
  lineCount: number
  parentSessionId: string
}

/** A window onto a session's output buffer, for the panel. */
export interface PtyReadResult {
  id: string
  status: PtyStatus
  exitCode: number | null
  /** Lines in the buffer, before the tail window is applied. */
  total: number
  lines: string[]
}

const sessionInfoSchema = {
  type: "object",
  properties: {
    id: { type: "string" },
    title: { type: "string" },
    command: { type: "string" },
    workdir: { type: "string" },
    status: { type: "string", enum: ["running", "exited", "killed"] },
    pid: { type: "number" },
    exitCode: { type: ["number", "null"] },
    exitAt: { type: ["string", "null"] },
    createdAt: { type: "string" },
    lineCount: { type: "number" },
    parentSessionId: { type: "string" },
  },
  required: [
    "id",
    "title",
    "command",
    "workdir",
    "status",
    "pid",
    "exitCode",
    "exitAt",
    "createdAt",
    "lineCount",
    "parentSessionId",
  ],
  additionalProperties: false,
} as const

const readResultSchema = {
  type: "object",
  properties: {
    id: { type: "string" },
    status: { type: "string", enum: ["running", "exited", "killed"] },
    exitCode: { type: ["number", "null"] },
    total: { type: "number" },
    lines: { type: "array", items: { type: "string" } },
  },
  required: ["id", "status", "exitCode", "total", "lines"],
  additionalProperties: false,
} as const

/** The PTY RPC. `id` is the registry key the server registers under and the
 *  client calls by, so it must not change without a coordinated release. */
export const PtyRpc = {
  id: "devbot-pty",
  methods: {
    list: {
      input: {
        type: "object",
        properties: {
          /** Only sessions this agent session spawned; omit for every session.
           *  Spelled like the field it matches, so a client that reads the info
           *  shape can filter with the same name. */
          parentSessionId: { type: "string" },
        },
        additionalProperties: false,
      },
      output: { type: "array", items: sessionInfoSchema },
    },
    read: {
      input: {
        type: "object",
        properties: {
          id: { type: "string" },
          /** How many trailing lines to return (default 200). */
          lines: { type: "number" },
        },
        required: ["id"],
        additionalProperties: false,
      },
      output: readResultSchema,
    },
    /** Stop a session, and drop its record when `cleanup` is set.
     *
     *  The sidebar's dismissal controls act through this: a user cannot reach
     *  the agent's `pty_kill` tool, and without a client-side way to remove a
     *  session the list would keep rows nobody can clear. */
    kill: {
      input: {
        type: "object",
        properties: {
          id: { type: "string" },
          cleanup: { type: "boolean" },
        },
        required: ["id"],
        additionalProperties: false,
      },
      output: {
        type: "object",
        properties: {
          id: { type: "string" },
          message: { type: "string" },
        },
        required: ["id", "message"],
        additionalProperties: false,
      },
    },
  },
  events: {},
} as const
