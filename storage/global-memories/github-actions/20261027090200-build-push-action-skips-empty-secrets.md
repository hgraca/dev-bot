---
date: 2026-10-27
keywords: ["github-actions", "build-push-action", "buildkit", "secrets"]
trigger-on: ["docker-build-push-action-secrets", "optional-buildkit-secret"]
---

## docker/build-push-action skips an empty `id=` secret instead of mounting it

The action parses each line of its `secrets:` input with `parseSecretKvp`, which throws on a zero-length value, so `NOVA_USERNAME=${{ secrets.NOVA_USERNAME }}` with an unset secret is logged as a warning and omitted — no mount is created. A Dockerfile declaring `RUN --mount=type=secret,id=NOVA_USERNAME,required=true` then fails at the mount: a clean failure, but one that surfaces as a build error rather than a configuration error. Emit optional secrets conditionally so callers without them see no warning and no empty value: `${{ secrets.X != '' && format('X={0}', secrets.X) || '' }}` — the action's input list drops the resulting blank lines.
