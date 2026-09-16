// =============================================================================
// src/harnesses/opencode/pty-monitor/index.ts
// PTY monitor TUI plugin: lists opencode-pty sessions in the sidebar and shows
// a session's live output in a dialog.
//
// Design notes, each learned the hard way while spiking this feature:
//
//  - **Default-export an object `{ id, tui }`.** Named exports fail to load with
//    "Plugin export is not a function".
//  - **Build elements lazily, inside a render pass.** `createElement` resolves
//    its renderer from a Solid context, so constructing one outside a render
//    throws "No renderer found". Never precompute elements.
//  - **`sidebar_content` is additive** (with an `order`), so this panel sits
//    alongside the built-ins rather than replacing them.
//  - **Present output in a dialog**, not a route and not a mirror session: a
//    route replaces the entire view, and child-session views have no sidebar.
//  - **Take the LATEST posted URL.** The PTY server binds a random port on every
//    start, so an older message holds a dead origin.
//  - **`/buffer/plain` returns JSON** (`{ plain, byteLength }`), CRLF-terminated.
//  - **Fail loudly.** A silent no-op is indistinguishable from a bug, so every
//    failure path surfaces a status line and a toast.
//
// `opencode-pty` is a hard dependency: its HTTP API is the only window onto PTY
// sessions. Its server starts on demand, triggered by its own
// `pty-show-server-url` command, whose posted URL we scrape.
// =============================================================================

import { appendFileSync, mkdirSync, readdirSync, readFileSync, readlinkSync } from "node:fs"
import { createElement, createTextNode, insert, insertNode, setProp } from "@opentui/solid"
import { createSignal } from "solid-js"
import {
  decodeBuffer,
  formatDetail,
  isPtyHealth,
  latestServerUrl,
  parseListeningPorts,
  ROW_BULLET,
  rowLabel,
  rowTone,
  tail,
} from "./lib"

const POLL_MS = 2500
const TAIL_LINES = 300
const SLOT_ORDER = 450
const BOOTSTRAP_TITLE = "pty-monitor bootstrap"

/** Consecutive bootstrap failures before the poll stops retrying by itself. */
const MAX_BOOTSTRAP_FAILURES = 3

/**
 * Collapse state — persisted in kv, deliberately NOT scoped per process: it is a
 * user preference that should hold across every opencode instance. Defaults to
 * collapsed so the panel stays out of the way until asked for.
 *
 * The key is namespaced under `.sidebar.` because the original `pty-monitor.
 * collapsed` key still exists in kv holding `false` from when the default was
 * expanded — and a stored value always wins over a default, so the flipped
 * default would have silently done nothing. Versioning the key retires the old
 * value; kv has no delete API, so the stale entry simply goes inert.
 */
const KV_COLLAPSED = "pty-monitor.sidebar.collapsed"

/**
 * The resolved origin, cached in MEMORY rather than in kv.
 *
 * `api.kv` is shared by every opencode process while the PTY server is
 * per-process, and kv has no delete API — so a per-PID key would leave one stale
 * entry behind on every single opencode start, forever. In-memory is
 * per-process by construction and needs no cleanup.
 */
let cachedOrigin = null

// A TUI plugin has no console, so a small event log on disk is the only way to
// diagnose interaction problems. OFF BY DEFAULT: it appends unboundedly, and
// shipping a plugin that quietly grows a file in /tmp forever is not acceptable.
// Set PTY_MONITOR_DEBUG=1 to turn it on when diagnosing.
const LOG_DIR = "/tmp/opencode"
const LOG = LOG_DIR + "/pty-monitor.log"
const DEBUG_ENABLED =
  typeof process !== "undefined" &&
  process.env &&
  process.env.PTY_MONITOR_DEBUG !== undefined &&
  process.env.PTY_MONITOR_DEBUG !== "" &&
  process.env.PTY_MONITOR_DEBUG !== "0"

function debug(event, detail) {
  if (!DEBUG_ENABLED) return
  try {
    mkdirSync(LOG_DIR, { recursive: true })
    appendFileSync(LOG, new Date().toISOString() + " " + event + " " + (detail ? JSON.stringify(detail) : "") + "\n")
  } catch (_) {
    /* logging must never break the plugin */
  }
}

// ── host helpers (no elements) ────────────────────────────────────────────────

/** Every text-bearing part of a session's messages, oldest first. */
function messageTexts(api, sessionID) {
  const out = []
  let messages = []
  try {
    messages = api.state.session.messages(sessionID) || []
  } catch (_) {
    return out
  }
  for (const m of messages) {
    let parts = m && m.parts
    if (!parts && m && m.id) {
      try {
        parts = api.state.part(m.id)
      } catch (_) {
        parts = null
      }
    }
    for (const p of parts || []) {
      const body = p && (p.text || (p.state && p.state.output))
      if (typeof body === "string") out.push(body)
    }
  }
  return out
}

// Liveness of a *known* origin. Checks the payload, not merely res.ok, so it
// agrees with the discovery path about what the PTY server looks like — an
// unrelated service that happens to answer 200 must not be mistaken for it.
async function isHealthy(origin) {
  try {
    const res = await fetch(origin + "/health")
    if (!res.ok) return false
    return isPtyHealth(await res.json())
  } catch (_) {
    return false
  }
}

/** Candidate origins for this process's listeners. */
function candidateHosts() {
  const configured =
    typeof process !== "undefined" && process.env ? process.env.PTY_WEB_HOSTNAME : undefined
  if (configured) {
    // opencode-pty binds PTY_WEB_HOSTNAME when set, so honour it rather than
    // guessing loopback. IPv6 literals need brackets in a URL.
    return [configured.includes(":") ? "[" + configured + "]" : configured]
  }
  return ["[::1]", "127.0.0.1"]
}

/** Socket inodes owned by this process, from /proc/self/fd. Linux only. */
function ownSocketInodes() {
  const inodes = new Set()
  try {
    for (const fd of readdirSync("/proc/self/fd")) {
      try {
        const match = readlinkSync("/proc/self/fd/" + fd).match(/^socket:\[(\d+)\]$/)
        if (match) inodes.add(match[1])
      } catch (_) {
        /* fd vanished mid-scan */
      }
    }
  } catch (_) {
    /* no /proc — not Linux */
  }
  return inodes
}

function readProc(path) {
  try {
    return readFileSync(path, "utf8")
  } catch (_) {
    return ""
  }
}

/**
 * Find the PTY server by inspecting this process's own listening sockets.
 *
 * Preferred over asking the plugin, because the plugin's only way to reveal its
 * URL is `pty-show-server-url`, and that command's entire job is posting the URL
 * as a message into the session — visible clutter on every restart. The port is
 * read straight from /proc instead, and the server is identified by probing
 * `/health` (a loopback port may belong to something else entirely: CUPS answers
 * on [::1]:631 on the machine this was built on).
 *
 * Linux only; returns null elsewhere so the caller can fall back to the scrape.
 */
async function discoverViaOwnSockets() {
  const inodes = ownSocketInodes()
  if (inodes.size === 0) return null
  const ports = parseListeningPorts(
    readProc("/proc/self/net/tcp6"),
    readProc("/proc/self/net/tcp"),
    inodes,
  )
  if (!ports.length) return null
  for (const port of ports) {
    for (const host of candidateHosts()) {
      const origin = "http://" + host + ":" + port
      try {
        const res = await fetch(origin + "/health")
        if (!res.ok) continue
        if (isPtyHealth(await res.json())) return origin
      } catch (_) {
        /* not the PTY server */
      }
    }
  }
  return null
}

/**
 * Start the PTY server without leaving a trace in the user's session.
 *
 * The server is only ever created as a side effect of one of opencode-pty's two
 * commands: `pty-show-server-url` (which POSTS THE URL AS A CHAT MESSAGE) or
 * `pty-open-background-spy` (which opens a browser). Neither is acceptable to
 * fire into the user's own transcript, and the server cannot be started any
 * other way.
 *
 * So the message-posting command is run inside a THROWAWAY session: the URL lands
 * there instead, the origin is picked up (from /proc where available, otherwise
 * by scraping that private session), and the session is deleted. The server
 * survives — it is a plugin-level object, not per-session — so the panel then
 * works and the user's chat stays clean.
 */
async function bootstrapOrigin(api) {
  let scratchID = null
  try {
    const created = await api.client.session.create({ title: BOOTSTRAP_TITLE })
    const data = created && (created.data ? created.data : created)
    scratchID = data && (data.id || (data.info && data.info.id))
    if (!scratchID) {
      debug("bootstrap.failed", { reason: "session.create returned no id" })
      return null
    }
  } catch (e) {
    debug("bootstrap.failed", { step: "create", error: String(e) })
    return null
  }

  try {
    await api.client.session.command({
      sessionID: scratchID,
      command: "pty-show-server-url",
      arguments: "",
    })
  } catch (e) {
    debug("bootstrap.command.failed", { error: String(e) })
  }

  let origin = null
  for (let attempt = 0; attempt < 20 && !origin; attempt++) {
    await new Promise((r) => setTimeout(r, 300))
    origin = await discoverViaOwnSockets()
    if (!origin) origin = latestServerUrl(messageTexts(api, scratchID))
    if (origin && !(await isHealthy(origin))) origin = null
  }

  try {
    await api.client.session.delete({ sessionID: scratchID })
  } catch (e) {
    debug("bootstrap.cleanup.failed", { scratchID, error: String(e) })
  }

  debug("bootstrap.done", { origin, scratchID })
  return origin
}

/**
 * Resolve the PTY server origin, cheapest and quietest first:
 *
 *  1. cached, while it still answers
 *  2. this process's own listening sockets (no side effects at all)
 *  3. bootstrap through a throwaway session (starts it if nothing is running)
 *
 * A cached origin that stops answering is re-resolved, because the server is
 * bound a new random port every time it starts.
 */
async function resolveOrigin(api) {
  if (cachedOrigin && (await isHealthy(cachedOrigin))) return cachedOrigin

  const viaOs = await discoverViaOwnSockets()
  if (viaOs) {
    debug("origin.os-discovery", { origin: viaOs })
    cachedOrigin = viaOs
    return viaOs
  }

  const viaBootstrap = await bootstrapOrigin(api)
  if (viaBootstrap) cachedOrigin = viaBootstrap
  return viaBootstrap
}

async function listSessions(origin) {
  const res = await fetch(origin + "/api/sessions")
  const body = await res.json()
  const arr = Array.isArray(body) ? body : body && body.sessions
  return Array.isArray(arr) ? arr : []
}

async function readBuffer(origin, id) {
  const res = await fetch(origin + "/api/sessions/" + id + "/buffer/plain")
  return decodeBuffer(await res.json())
}

// ── element helpers — call ONLY inside a render pass ──────────────────────────

function text(content) {
  const el = createElement("text")
  insertNode(el, createTextNode(String(content)))
  return el
}

/** A text element whose content tracks an accessor (reactive). */
function textLive(accessor) {
  const el = createElement("text")
  insert(el, () => String(accessor()))
  return el
}

function column(children) {
  const box = createElement("box")
  setProp(box, "flexDirection", "column")
  for (const child of children) {
    if (child) insertNode(box, child)
  }
  return box
}

/** A column whose children follow an accessor (reactive list). */
function columnLive(accessor) {
  const box = createElement("box")
  setProp(box, "flexDirection", "column")
  insert(box, () => accessor())
  return box
}

/**
 * A scrollable holder for the output.
 *
 * A scrollbox only scrolls if it has a BOUNDED height, so one is supplied in
 * rows. `stickyScroll` + `stickyStart: "bottom"` keep the view pinned to the
 * newest output, which is what you want when watching a live process — the
 * same idiom opencode-user-timeline uses for its list.
 */
function scrollboxFor(child, rows) {
  const box = createElement("scrollbox")
  setProp(box, "width", "100%")
  setProp(box, "height", rows)
  setProp(box, "scrollY", true)
  setProp(box, "stickyScroll", true)
  setProp(box, "stickyStart", "bottom")
  insertNode(box, child)
  return box
}

// ── plugin ────────────────────────────────────────────────────────────────────

const tui = async (api) => {
  const [sessions, setSessions] = createSignal([])
  const [status, setStatus] = createSignal("starting…")
  // Restored from kv so the panel remembers its state across restarts, matching
  // how the built-in sidebar items (MCP, File Tree, Todo) behave.
  const [collapsed, setCollapsed] = createSignal(Boolean(api.kv.get(KV_COLLAPSED, true)))

  let origin = null
  let disposed = false
  let rootTimer = null
  let refreshing = false
  let bootstrapFailures = 0

  const refresh = async () => {
    if (disposed) return
    // Guard against overlap: a bootstrap can take ~6s while the poll ticks every
    // 2.5s, so without this a host where the server never comes up would run
    // several create-session/delete-session cycles at once, forever.
    if (refreshing) return
    refreshing = true
    try {
      // Checked BEFORE the attempt, so "backed off" actually means no further
      // create-session/delete-session cycles until the user retries.
      if (!origin && bootstrapFailures >= MAX_BOOTSTRAP_FAILURES) {
        setStatus("server unavailable — /pty-monitor to retry")
        return
      }
      if (!origin) origin = await resolveOrigin(api)
      if (!origin) {
        bootstrapFailures++
        debug("refresh.bootstrap-failed", { bootstrapFailures })
        setStatus(
          bootstrapFailures >= MAX_BOOTSTRAP_FAILURES
            ? "server unavailable — /pty-monitor to retry"
            : "starting server…",
        )
        setSessions([])
        return
      }
      bootstrapFailures = 0
      const list = await listSessions(origin)
      setSessions(list)
      setStatus(list.length === 1 ? "1 session" : list.length + " sessions")
    } catch (_) {
      // Force re-discovery next tick: the server may have restarted on a new port.
      origin = null
      setStatus("server unreachable")
      setSessions([])
    } finally {
      refreshing = false
    }
  }

  const openOutput = async (session) => {
    if (!origin) {
      api.ui.toast({ variant: "warning", title: "pty-monitor", message: "PTY server unavailable" })
      return
    }
    // Captured for the lifetime of this dialog. `origin` is shared state and
    // refresh() nulls it on a transient failure — reading the shared variable
    // here would then report a buffer-read failure for a session that is fine.
    const dialogOrigin = origin
    const [buf, setBuf] = createSignal("loading…")
    let timer = null
    const load = async () => {
      try {
        setBuf(await readBuffer(dialogOrigin, session.id))
      } catch (_) {
        setBuf("(failed to read buffer — the session may have been cleaned up)")
      }
    }
    await load()
    // The host dismisses the dialog on a mouse-up on its overlay, but ignores
    // that release when a text selection was active on the preceding mouse-down
    // (so you can drag-select without the dialog vanishing) — which is what made
    // closing take two outside clicks. Clearing any stale selection first means
    // the very next click finds nothing to protect and closes on the first one.
    try {
      if (api.renderer && typeof api.renderer.clearSelection === "function") {
        api.renderer.clearSelection()
      }
    } catch (_) {
      /* best effort — clearing is an optimisation, not a requirement */
    }
    // The host renders the dialog as a full-screen overlay with
    // `alignItems:center` (horizontal only) and `paddingTop = terminalHeight/4`,
    // so the dialog's top edge is pinned a QUARTER of the screen down and it
    // grows downward from there. For its midpoint to land on the screen's
    // midpoint its total height must therefore be exactly HALF the screen: any
    // row beyond that pushes the bottom down without lifting the top. Width is
    // capped independently at 116 columns by size "xlarge", so HEIGHT is the
    // only shape lever available — and it is spent here filling downward to the
    // screen edge (the tallest the host will show), which trades away the
    // centring that a half-screen box would give.
    const screenRows =
      api.renderer && typeof api.renderer.height === "number" ? api.renderer.height : 40
    const cols = api.renderer && typeof api.renderer.width === "number" ? api.renderer.width : 80
    const topOffset = Math.floor(screenRows / 4)
    // Header (4 lines incl. the hint + its 2-row border), the output frame's
    // border (2), and the host's own chrome are all subtracted so the box cannot
    // run past the screen edge.
    const rows = Math.max(6, screenRows - topOffset - 12)
    debug("dialog.metrics", { screenRows, cols, topOffset, rows })
    const palette = api.theme && api.theme.current ? api.theme.current : {}

    const dialogHeaderFor = () => {
      // A tinted bar, matching how the built-ins band their section headers. The
      // hint lives INSIDE the band so the whole header reads as one block, and
      // the bar carries the same border as the output frame below it.
      const bar = createElement("box")
      setProp(bar, "flexDirection", "column")
      setProp(bar, "width", "100%")
      setProp(bar, "border", true)
      setProp(bar, "borderStyle", "single")
      if (palette.border) setProp(bar, "borderColor", palette.border)
      if (palette.backgroundElement) setProp(bar, "backgroundColor", palette.backgroundElement)
      insertNode(bar, text("⟡ " + (session.title || session.id)))
      insertNode(bar, text(formatDetail(session)))
      insertNode(bar, text("esc to close"))
      return bar
    }

    const framedOutput = () => {
      // A small inner border around the output area, so the scrollable region is
      // visually distinct from the surrounding dialog.
      const frame = createElement("box")
      setProp(frame, "width", "100%")
      setProp(frame, "border", true)
      setProp(frame, "borderStyle", "single")
      if (palette.border) setProp(frame, "borderColor", palette.border)
      insertNode(frame, scrollboxFor(textLive(() => tail(buf(), TAIL_LINES)), rows))
      return frame
    }

    api.ui.dialog.replace(
      () => column([dialogHeaderFor(), framedOutput()]),
      () => {
        debug("dialog.closed", { id: session.id })
        if (timer) clearInterval(timer)
        timer = null
      },
    )
    // setSize must come AFTER replace: replace resets the size as part of
    // pushing the entry, so calling it before is silently overridden.
    // Size is a WIDTH (xlarge = 116 cols), so pick it from the terminal width —
    // the same thresholds opencode's own plugin manager uses, otherwise the
    // dialog is wider than a narrow terminal.
    api.ui.dialog.setSize(cols >= 128 ? "xlarge" : cols >= 96 ? "large" : "medium")
    debug("dialog.opened", { id: session.id, size: api.ui.dialog.size, cols })
    timer = setInterval(load, POLL_MS)
  }

  const rowFor = (session) => {
    // Bullet and label are SEPARATE text elements in a row box, because `fg` is
    // only proven to work on text elements (opencode-tabs colours its labels
    // that way). Nesting a `span` inside a `text` and colouring the span — my
    // first attempt — silently rendered uncoloured.
    const row = createElement("box")
    setProp(row, "flexDirection", "row")
    const palette = (api.theme && api.theme.current) || {}
    const tone = rowTone(session)
    const toneColor =
      tone === "success" ? palette.success : tone === "error" ? palette.error : palette.textMuted
    const bullet = createElement("text")
    if (toneColor) setProp(bullet, "fg", toneColor)
    insertNode(bullet, createTextNode(ROW_BULLET))
    insertNode(row, bullet)
    const label = createElement("text")
    if (palette.text) setProp(label, "fg", palette.text)
    insertNode(label, createTextNode(rowLabel(session)))
    insertNode(row, label)
    // Diagnose the mousedown-vs-mouseup ordering (see activate below).
    setProp(row, "onMouseDown", () => debug("row.mousedown", { id: session.id }))
    setProp(row, "onMouseUp", () => activate(session))
    return row
  }

  // Open the dialog on mouse UP, deferred one tick.
  //
  // Opening on mouse DOWN meant the dialog's click-outside dismissal then saw
  // the still-pending mouseup/click land outside the brand-new modal and closed
  // it in the same gesture. Waiting for mouseup and letting the trailing click
  // event pass before opening avoids that entirely.
  const activate = (session) => {
    debug("row.mouseup", { id: session.id })
    setTimeout(() => {
      debug("row.open", { id: session.id })
      openOutput(session).catch((e) => {
        // A click that silently does nothing is indistinguishable from a broken
        // panel, so say so out loud rather than only to the debug log.
        debug("row.open.failed", { error: String(e) })
        try {
          api.ui.toast({
            variant: "error",
            title: "pty-monitor",
            message: "Could not open " + (session.title || session.id) + ": " + String(e),
          })
        } catch (_) {
          /* toast is best-effort */
        }
      })
    }, 0)
  }

  // A collapsible header, matching the built-in sidebar items (MCP, File Tree,
  // Todo): chevron glyph, click to toggle, state persisted in kv. The count
  // stays visible while collapsed so the panel is still informative.
  const headerFor = () => {
    const el = createElement("text")
    insert(el, () => (collapsed() ? "\u25B6" : "\u25BC") + " PTY  " + status())
    setProp(el, "onMouseDown", () => {
      const next = !collapsed()
      setCollapsed(next)
      api.kv.set(KV_COLLAPSED, next)
    })
    return el
  }

  // ── sidebar panel ─────────────────────────────────────────────────────────
  api.slots.register({
    order: SLOT_ORDER,
    slots: {
      sidebar_content() {
        return column([
          headerFor(),
          columnLive(() => {
            if (collapsed()) return []
            const list = sessions()
            if (!list.length) return [text("   (none)")]
            return list.map((s) => rowFor(s))
          }),
        ])
      },
    },
  })

  // ── a command so the panel can be refreshed without waiting ───────────────
  api.command.register(() => [
    {
      title: "PTY monitor: refresh",
      value: "pty-monitor-refresh",
      description: "Re-scan the PTY server for sessions",
      slash: { name: "pty-monitor" },
      onSelect: () => {
        // Explicit user retry: clear both the cached origin and the backoff.
        origin = null
        bootstrapFailures = 0
        refresh().catch(() => {})
      },
    },
  ])

  api.lifecycle.onDispose(() => {
    disposed = true
    if (rootTimer) clearInterval(rootTimer)
    rootTimer = null
  })

  await refresh()
  rootTimer = setInterval(() => {
    refresh().catch(() => {})
  }, POLL_MS)
}

export default { id: "pty-monitor", tui }
