// src/harnesses/opencode-v2/tui/tui-defaults/server.ts
// Server part, deliberately empty.
//
// V2 loads a plugin's TUI part from the plugins its server loads, so a package
// that wants to be project-scoped (listed in opencode.jsonc rather than the
// global cli.json) needs a server part to carry it.

import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "devbot-tui-defaults",
  setup() {},
})
