// src/harnesses/opencode-v2/tui/tui-defaults/tui.ts
// TUI part: runs at TUI startup, before any view mounts, and seeds dev-bot's
// tool-details default so a fresh install opens with tool details hidden.
//
// The write goes to the same reactive kv store opencode's own toggle uses, so
// the value applies to the running session immediately and survives restarts.
// An existing choice is never overridden — the seed only fires while the key is
// absent. See lib.ts for the rule.

import { seedToolDetailsDefault, type TuiPluginApi } from "./lib"

const tui = async (api: TuiPluginApi) => {
  seedToolDetailsDefault(api.kv)
}

export default { id: "tui-defaults", tui }
