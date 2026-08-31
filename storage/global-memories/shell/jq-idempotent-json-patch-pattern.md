---
date: 2026-05-16
keywords: ["shell", "jq", "json", "idempotent", "init"]
---

# jq Idempotent JSON Config Patch Pattern

## Pattern

When an init script needs to conditionally add a key to an existing JSON config file:

1. Guard `jq` availability: `command -v jq &>/dev/null` — skip gracefully if absent.
2. Validate JSON before reading: `jq empty file 2>/dev/null` — warn and skip if malformed.
3. Check if key already present: `jq -e 'has("key")' file >/dev/null 2>&1`
4. Patch via temp file (never `jq -i` — not portable): `jq '. + {"key": value}' file > tmp && mv tmp file`
5. Clean up temp file on any exit path: `trap 'rm -f "${tmp}"' RETURN`

## Hardened example (codebase-index init.sh)

```bash
if ! command -v jq &>/dev/null; then
  info "jq not found — skipping injection (install jq to enable)"
else
  if [[ -f "${CONFIG}" ]]; then
    if ! jq empty "${CONFIG}" 2>/dev/null; then
      warn "config is malformed — skipping injection"
    elif jq -e 'has("include")' "${CONFIG}" >/dev/null 2>&1; then
      skip "already has include"; exit 0
    fi
    # fall through to patch
  else
    cp template.json "${CONFIG}"
  fi

  _inject() {
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f "${tmp}"' RETURN
    jq '. + {"include": ["src/**/*.ts"]}' "${CONFIG}" > "${tmp}" && mv "${tmp}" "${CONFIG}"
  }
  _inject
fi
```

## When to apply

- Init scripts that write JSON config and need to enrich it based on project structure.
- Any idempotent JSON patching where key presence determines whether to act.

## Gotchas

- `jq -i` is NOT portable across platforms — always write to temp file and `mv`.
- Use `jq -e` (exit non-zero on false/null) for boolean checks.
- Under `set -euo pipefail`, missing `jq` causes silent abort — always guard with `command -v`.
- Malformed JSON causes `jq -e 'has(...)'` to exit non-zero, aborting the script silently — validate with `jq empty` first.
- Temp file leaks on `jq` failure unless `trap 'rm -f "${tmp}"' RETURN` is set immediately after `mktemp`.

## Related

- [[20260516163000-graphify-graph-edge-structure-gotcha]]
