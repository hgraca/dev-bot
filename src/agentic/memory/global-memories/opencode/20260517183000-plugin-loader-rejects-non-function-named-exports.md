---
date: 2026-05-17
keywords: ["opencode", "plugin", "export", "loader"]
---

## opencode plugin loader rejects any non-function named export

opencode's plugin loader iterates `Object.values(mod)` for every export in a plugin file and calls an internal `eS()` check on each value. If any export value is not a function (e.g. a string constant, number, RegExp, or plain object without a `.server` function property), the loader throws `"Plugin export is not a function"` and the entire plugin fails to load. This means a plugin file must export ONLY the plugin factory function(s) — no helper constants, no utility exports. Move all non-function exports (constants, helpers, pure functions used by tests) to a separate `*-helpers.js` sibling file and import from there in both the plugin and the tests. Confirmed by reading the minified loader source in the opencode binary (`$x` function iterates `Object.values`, `eS` returns undefined for non-functions, `$x` throws on undefined).
