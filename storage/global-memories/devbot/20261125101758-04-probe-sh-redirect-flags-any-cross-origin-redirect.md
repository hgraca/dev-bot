---
date: 2026-11-25
keywords: ["devbot", "pentest", "probe", "open-redirect"]
aliases: ["false positive", "redirect check"]
---

## probe.sh reports any cross-origin redirect as an open redirect

## probe.sh reports any cross-origin redirect as an open redirect

The external-pentest skill's `scripts/probe.sh redirect <base>` sends `?redirect=<payload>` and fails
whenever the final URL's origin differs from the base's — it never checks that the payload actually
reached the `Location` header. Any application that legitimately redirects an unauthenticated visitor
to a login portal on a different host therefore produces a false `FAIL`, which reads as a
high-severity open redirect.

Confirm or refute by inspecting the `Location` value directly: if the payload string (`attacker.invalid`)
is absent, the parameter was ignored and the check is a pass.

```bash
curl -sk -D - -o /dev/null -- "$BASE?redirect=/\attacker.invalid" | grep -i '^location'
```

In the 2026-11-25 positioning-activities run the trigger was a shared-network DNS collision, not a
redirect defect at all: a sibling project answered the hostname and redirected to its own portal.
Treat a redirect FAIL as a hypothesis until the `Location` is read.
