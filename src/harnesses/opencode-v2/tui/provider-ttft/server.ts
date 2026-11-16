// src/harnesses/opencode-v2/tui/provider-ttft/server.ts
// Server half of the TTFT sidebar row.
//
// The row lives in tui.ts. A local plugin directory is discovered as a package,
// and a package needs a server part to be registered at all, so this one is
// deliberately inert.

import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "devbot-provider-ttft",
  setup() {},
})
