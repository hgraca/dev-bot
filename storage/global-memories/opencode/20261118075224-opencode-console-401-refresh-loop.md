---
date: 2026-11-18
keywords: ["opencode", "console", "credential", "401", "provider"]
---

## An expired OpenCode Console credential logs a 401 every minute

The opencode 2.x background service refreshes the OpenCode Console provider config on a ~60 s timer. When the stored `OpenCode Console` API key is expired or revoked, every tick writes two WARN lines to `~/.local/share/opencode/log/opencode.log`: `failed to load shared value key="opencode-console:[…,credential:<id>,…]"` and `failed to load OpenCode provider config cause="…401 GET https://opencode.ai/console/api/v2/config"`. One install had 2678 occurrences over three days and no capability failure, because the configured models used other providers. The loop stops immediately after `opencode2 auth logout opencode <credential-id>` (the log records `credential removed`), and `opencode2 auth login opencode` restores the provider. Non-interactive logout requires both arguments — integration and credential id/label — or it fails with "Pass a credential ID or label when running without an interactive terminal".
