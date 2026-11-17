// =============================================================================
// src/harnesses/opencode-v2/hooks/pty/tui.ts
// The PTY monitor: a sidebar block listing this session's PTY sessions, and a
// session panel showing one of them live.
//
// Ported from the v1 `pty-monitor` (src/harnesses/opencode/pty-monitor), whose
// host API no longer exists on 2.3. What changed, and why:
//
//  - The sessions are read over `PtyRpc`, not over HTTP. v1 scraped a random
//    port posted into the transcript by the plugin's own command; here the two
//    parts are separate processes, and the RPC is their only channel.
//  - The list is filtered by `parentSessionId`, so the block shows the PTYs the
//    agent session in view spawned (that is what PR shekohex/opencode-pty#91
//    exists for) instead of every session in the process.
//  - The output opens in the `session.panel` slot rather than a dialog, so the
//    session view stays where it is — the host owns the panel's layout, focus
//    and fullscreen toggle.
//  - Elements are built with the imperative API, as the v1 part did: these
//    modules are `.ts`, and the host's Solid loader only transforms JSX in
//    `.tsx`.
// =============================================================================

import { Plugin } from "@opencode/plugin/tui"
import { createElement, createTextNode, insert, insertNode, setProp } from "@opentui/solid"
import { createSignal } from "solid-js"
import {
  clearActionLabel,
  dropSelection,
  filterByFamily,
  finishedSessions,
  formatDetail,
  formatDuration,
  headerLabel,
  needsConfirm,
  rowLabel,
  rowTone,
  runDurationMs,
  selectedSession,
  selectSession,
} from "./lib"
import { PtyRpc } from "./rpc"
import type { PtySessionInfo } from "./rpc"

/** The panel's name, set by `ui.panel.open` and checked by its own claim. */
const PANEL = "pty"
const LIST_POLL_MS = 2000
const READ_POLL_MS = 1000
const PANEL_TAIL = 300
/** The per-row remove control; a leading space keeps it off the label. */
const REMOVE_GLYPH = " \u2715"

type Renderable = any

function text(content: string): Renderable {
  const el = createElement("text")
  insertNode(el, createTextNode(String(content)))
  return el
}

/** A text element whose content tracks an accessor (reactive). */
function liveText(accessor: () => string): Renderable {
  const el = createElement("text")
  insert(el, () => String(accessor()))
  return el
}

function column(children: Renderable[]): Renderable {
  const box = createElement("box")
  setProp(box, "flexDirection", "column")
  for (const child of children) {
    if (child) insertNode(box, child)
  }
  return box
}

/** A column whose children follow an accessor (reactive list). */
function liveColumn(accessor: () => Renderable[]): Renderable {
  const box = createElement("box")
  setProp(box, "flexDirection", "column")
  insert(box, () => accessor())
  return box
}

export default Plugin.define({
  id: "devbot.pty",
  setup(ctx) {
    const [all, setAll] = createSignal<PtySessionInfo[]>([])
    const [failing, setFailing] = createSignal(false)
    /** The session whose output the panel shows, per agent session. */
    const [selected, setSelected] = createSignal<Record<string, string>>({})
    const [buffer, setBuffer] = createSignal<{ id: string; lines: string[]; total: number }>({
      id: "",
      lines: [],
      total: 0,
    })

    // The RPC is location-scoped: a call without one lands on whatever location
    // the server treats as default, which is not necessarily the directory this
    // TUI is attached to.
    const callOptions = () => {
      try {
        const location = ctx.location ?? ctx.data.location.default()
        return location ? { location } : undefined
      } catch {
        return undefined
      }
    }

    /** The host's list of descendant sessions for a session; empty when it
     *  cannot answer, which then scopes the block to the session itself. */
    const familyOf = (sessionID: string): string[] => {
      try {
        const family = ctx.data.session.family(sessionID)
        return Array.isArray(family) ? family.filter((id: unknown) => typeof id === "string") : []
      } catch {
        return []
      }
    }

    const refreshList = async () => {
      try {
        const list = await ctx.client.rpc(PtyRpc).list({}, callOptions())
        setAll(Array.isArray(list) ? (list as PtySessionInfo[]) : [])
        setFailing(false)
      } catch {
        // A server restart breaks the client for a moment; keep the last rows
        // and let the header say the list is not live.
        setFailing(true)
      }
    }

    const refreshOutput = async () => {
      const panel = ctx.ui.panel.current()
      if (!panel) return
      const id = selectedSession(selected(), panel.sessionID)
      if (!id) return
      try {
        const result: any = await ctx.client.rpc(PtyRpc).read(
          { id, lines: PANEL_TAIL },
          callOptions(),
        )
        setBuffer({ id, lines: result?.lines ?? [], total: result?.total ?? 0 })
      } catch {
        // The session was killed and cleaned while the panel was open: the row
        // is gone from the list, and the panel keeps its last output.
      }
    }

    const openPanel = (parentSessionID: string, id: string) => {
      setSelected(selectSession(selected(), parentSessionID, id))
      setBuffer({ id, lines: [], total: 0 })
      ctx.ui.panel.open(PANEL)
    }

    const forget = (viewerSessionID: string, removedId: string) => {
      const wasOpen = selectedSession(selected(), viewerSessionID) === removedId
      setSelected(dropSelection(selected(), viewerSessionID, removedId))
      if (!wasOpen) return
      // The panel has nothing left to show; leaving it open on an empty id
      // reads as a broken view.
      ctx.ui.panel.close()
      setBuffer({ id: "", lines: [], total: 0 })
    }

    const errorText = (error: unknown): string =>
      error instanceof Error ? error.message : String(error)

    /** Stop a session and drop its record — the user's only way in, since the
     *  agent's `pty_kill` tool is not reachable from the TUI. */
    const removeSession = async (viewerSessionID: string, info: PtySessionInfo) => {
      try {
        await ctx.client.rpc(PtyRpc).kill({ id: info.id, cleanup: true }, callOptions())
      } catch (error) {
        ctx.ui.toast.show({
          variant: "error",
          title: "PTY",
          message: `Could not remove ${info.title}: ${errorText(error)}`,
        })
        return
      }
      forget(viewerSessionID, info.id)
      ctx.ui.toast.show({ variant: "info", title: "PTY", message: `Removed ${info.title}` })
      await refreshList()
    }

    /** A running session is a live process, so it is confirmed first; a
     *  finished one is only a record and goes at once. */
    const confirmRemove = async (viewerSessionID: string, info: PtySessionInfo) => {
      if (!needsConfirm(info)) {
        await removeSession(viewerSessionID, info)
        return
      }
      const answer = await ctx.ui.dialog.confirm({
        title: "Remove PTY session",
        message: `Kill the running session "${info.title}" and remove it?`,
        label: { confirm: "Kill and remove", cancel: "Keep" },
      })
      if (answer !== true) return
      await removeSession(viewerSessionID, info)
    }

    /** Drop every finished row this block shows. Never touches a live session,
     *  so it needs no confirmation. */
    const clearFinished = async (list: PtySessionInfo[], viewerSessionID: string) => {
      const targets = finishedSessions(list)
      if (targets.length === 0) return

      const results = await Promise.all(
        targets.map((info) =>
          ctx.client.rpc(PtyRpc).kill({ id: info.id, cleanup: true }, callOptions()).then(
            () => true,
            () => false,
          ),
        ),
      )
      // Only what actually went is forgotten: a target whose cleanup failed is
      // still listed, and must not lose the panel it was open in.
      targets.forEach((info, i) => {
        if (results[i]) forget(viewerSessionID, info.id)
      })
      const failed = results.filter((ok) => !ok).length
      if (failed > 0) {
        ctx.ui.toast.show({
          variant: "error",
          title: "PTY",
          message: `Could not remove ${failed} of ${targets.length} finished sessions`,
        })
      }
      await refreshList()
    }

    const toneColor = (tone: "success" | "error" | "muted"): string | undefined => {
      const text = (ctx.theme as any)?.text ?? {}
      if (tone === "success") return text.feedback?.success?.base ?? text.base
      if (tone === "error") return text.feedback?.error?.base ?? text.base
      return text.muted
    }

    const rowFor = (info: PtySessionInfo, parentSessionID: string): Renderable => {
      const row = createElement("box")
      setProp(row, "flexDirection", "row")

      const bullet = createElement("text")
      const color = toneColor(rowTone(info))
      if (color) setProp(bullet, "fg", color)
      insertNode(bullet, createTextNode("\u2022 "))

      const label = createElement("text")
      setProp(label, "flexGrow", 1)
      if (ctx.theme?.text?.base) setProp(label, "fg", ctx.theme.text.base)
      insertNode(label, createTextNode(rowLabel(info)))

      // The glyph must swallow BOTH mouse events: the row opens the panel on
      // mouse up, so without this the removal would also open what it removed.
      const remove = createElement("text")
      const muted = toneColor("muted")
      if (muted) setProp(remove, "fg", muted)
      insertNode(remove, createTextNode(REMOVE_GLYPH))
      setProp(remove, "onMouseDown", (event: any) => event?.stopPropagation?.())
      setProp(remove, "onMouseUp", (event: any) => {
        event?.stopPropagation?.()
        void confirmRemove(parentSessionID, info)
      })

      insertNode(row, bullet)
      insertNode(row, label)
      insertNode(row, remove)
      setProp(row, "onMouseUp", () => openPanel(parentSessionID, info.id))
      return row
    }

    const headerFor = (list: PtySessionInfo[], viewerSessionID: string): Renderable => {
      const row = createElement("box")
      setProp(row, "flexDirection", "row")
      const label = liveText(() => {
        if (failing()) return "PTY unavailable"
        return headerLabel({
          count: list.length,
          running: list.filter((s) => s.status === "running").length,
        })
      })
      const color = toneColor(failing() ? "error" : "muted")
      if (color) setProp(label, "fg", color)
      // Grow so the clear action is pushed to the block's right edge.
      setProp(label, "flexGrow", 1)
      insertNode(row, label)

      const clear = createElement("text")
      const muted = toneColor("muted")
      if (muted) setProp(clear, "fg", muted)
      // Empty when nothing is finished: a zero-width element presents no hit
      // target, so the header never offers an action that would delete nothing.
      insertNode(clear, createTextNode(clearActionLabel(list) ?? ""))
      setProp(clear, "onMouseUp", (event: any) => {
        event?.stopPropagation?.()
        void clearFinished(list, viewerSessionID)
      })
      insertNode(row, clear)
      return row
    }

    const unregisterSidebar = ctx.ui.slot({
      append: "sidebar.content",
      render: (input: { sessionID: string }) => {
        // The session in view plus its subagents: a PTY a subagent spawned
        // carries the subagent's id, and hiding those would hide most of them.
        const mine = () =>
          filterByFamily(all(), [input.sessionID, ...familyOf(input.sessionID)])
        return liveColumn(() => {
          const list = mine()
          // Idle means no rows at all: an empty block would still cost a line
          // in the sidebar of every session that never spawns a PTY.
          if (list.length === 0 && !failing()) return []
          return [headerFor(list, input.sessionID), ...list.map((info) => rowFor(info, input.sessionID))]
        })
      },
    })

    const unregisterPanel = ctx.ui.slot({
      append: "session.panel",
      render: (input: { name: string; sessionID: string }) => {
        const frame = createElement("box")
        setProp(frame, "flexDirection", "column")
        setProp(frame, "width", "100%")
        setProp(frame, "flexGrow", 1)
        if (input.name !== PANEL) {
          // Another plugin's panel is open; this claim contributes nothing.
          setProp(frame, "visible", false)
          return frame
        }

        const currentId = () => selectedSession(selected(), input.sessionID)
        const current = () => all().find((s) => s.id === currentId())

        const header = column([
          liveText(() => {
            const info = current()
            if (!info) return currentId() || "no PTY session selected"
            const elapsed = runDurationMs(info, Date.now())
            const run = elapsed === null ? "" : `  ${formatDuration(elapsed)}`
            return [info.id, info.status, `pid ${info.pid}`, `${info.lineCount} lines`].join("  ") + run
          }),
          liveText(() => {
            const info = current()
            return info ? formatDetail(info).split("\n").slice(-1)[0] : ""
          }),
        ])

        const scroller = createElement("scrollbox")
        setProp(scroller, "width", "100%")
        setProp(scroller, "flexGrow", 1)
        setProp(scroller, "scrollY", true)
        // Pinned to the newest output: this watches a live process.
        setProp(scroller, "stickyScroll", true)
        setProp(scroller, "stickyStart", "bottom")
        // The server already windows the buffer, so this renders what it got.
        const body = createElement("text")
        insert(body, () => (buffer().id === currentId() ? buffer().lines : []).join("\n"))
        insertNode(scroller, body)

        insertNode(frame, header)
        insertNode(frame, scroller)
        return frame
      },
    })

    const listTimer = setInterval(() => void refreshList(), LIST_POLL_MS)
    const readTimer = setInterval(() => void refreshOutput(), READ_POLL_MS)
    void refreshList()

    return () => {
      clearInterval(listTimer)
      clearInterval(readTimer)
      unregisterSidebar?.()
      unregisterPanel?.()
    }
  },
})
