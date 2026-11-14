// src/harnesses/opencode-v2/tui/provider-ttft/server.ts
// Server part, deliberately empty — it exists so the package is project-scoped
// (listed in opencode.jsonc) rather than global, which is where a TUI part with
// no server part would have to live (cli.json).

import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "devbot-provider-ttft",
  setup() {},
})
