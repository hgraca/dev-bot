---
date: 2026-11-18
keywords: ["devbot", "format-md", "formatter", "extension", "guard"]
---

# Formatter tools must validate the file extension in file mode

The `format-md` / `format-json` / `format-yml` hooks match their extension strictly (`.md`, `.json|.jsonc`, `.yml|.yaml`), but the MCP tools and `--check` accepted any path and ran prettier on it. A direct `format-md` call on a `.bats` probe reformatted the file in place and reported `1 changed` — a silent corruption path the hook matcher cannot cover, because hooks are not the only entry point.

## The fix

File mode now refuses a path whose suffix the tool does not own and counts it as an error; directory mode already filtered. The three tools were fixed together because the bug was one class, not one module. Each refusal is pinned by a BATS test that asserts the file is byte-identical afterwards.

## Rule

When adding a formatter tool, validate in both places: the hook matcher and the tool entry point. A `--check` gate must also fail on a wrong extension rather than reporting a false green.
