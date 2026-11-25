// src/harnesses/opencode-v2/hooks/herdr-pane-title/index.ts
// Server part, deliberately empty.
//
// V2 loads a plugin's TUI part from the plugin packages its server loads, so a
// package that must be project-scoped needs a server part to carry the `./tui`
// export beside it. Same reason as tui/tui-defaults/server.ts.

import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "devbot-herdr-pane-title",
  setup() {},
})
