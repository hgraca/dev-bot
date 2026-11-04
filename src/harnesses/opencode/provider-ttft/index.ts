// Default-export `{ id, tui }`; named ones fail.
// Build in the slot — no renderer outside one.

import { createElement, createTextNode, insert, insertNode, setProp } from "@opentui/solid"
import { createSignal } from "solid-js"
import { formatTtft, recordAssistantMessage, takeFirstDelta, withTtft } from "./lib"

// The order-100 row the context block used.
const SLOT_ORDER = 100

const tui = async (api) => {
  const [bySession, setBySession] = createSignal(new Map())
  const pending = new Map()

  api.event.on("message.updated", (event) => {
    recordAssistantMessage(pending, event.properties?.info)
  })

  api.event.on("message.part.delta", (event) => {
    const messageID = event.properties?.messageID
    const sessionID = event.properties?.sessionID
    if (!messageID || !sessionID) return
    // Deltas have no timestamp — stamp arrival.
    const elapsed = takeFirstDelta(pending, messageID, Date.now())
    if (elapsed !== undefined) setBySession((prev) => withTtft(prev, sessionID, elapsed))
  })

  api.slots.register({
    order: SLOT_ORDER,
    slots: {
      sidebar_content(_ctx, props) {
        const palette = (api.theme && api.theme.current) || {}
        const row = createElement("box")
        setProp(row, "flexDirection", "row")
        setProp(row, "gap", 1)

        const label = createElement("text")
        insertNode(label, createTextNode("TTFT"))
        if (palette.text) setProp(label, "fg", palette.text)

        const value = createElement("text")
        insert(value, () => {
          const ms = bySession().get(props.session_id)
          return ms === undefined ? "-" : formatTtft(ms)
        })
        if (palette.textMuted) setProp(value, "fg", palette.textMuted)

        insertNode(row, label)
        insertNode(row, value)
        return row
      },
    },
  })
}

export default { id: "provider-ttft", tui }
