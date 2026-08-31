---
date: 2026-05-28
keywords: ["otel", "opentelemetry", "bearertokenauth", "extension"]
---

## bearertokenauth extension uses `filename:` mode for dynamic token sets

When multiple bearer tokens must be valid simultaneously (dual-token rotation), configure `bearertokenauth` with `filename:` instead of `token:`. The `filename:` mode reads all whitespace-delimited tokens from a file — each line's first word is accepted as valid; lines starting with `#` are treated as comments.

Key configuration:

```yaml
extensions:
    bearertokenauth:
        scheme: Bearer
        filename: /etc/otel/tokens/tokens.txt
```

On receivers, add `auth:` with `authenticator: bearertokenauth`. Add `bearertokenauth` to the service `extensions:` list. Requires `otel/opentelemetry-collector-contrib` image (not the core distroless image). Token file must be mounted via Secret volume; rollout restart needed after Secret update for kubelet to sync.
