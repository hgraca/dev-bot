---
date: 2026-10-30
keywords: ["k8s", "traefik", "ingressroute", "matcher", "headersregexp"]
aliases: ["header matcher removed in traefik v3", "unknown matcher voids the rule"]
trigger-on: ["traefik-ingressroute-matcher"]
---

## Traefik v3 removed HeadersRegexp; an unknown matcher voids the whole rule silently

Traefik v3 dropped the plural `Headers` / `HeadersRegexp` matchers, replacing them with the singular
`Header` / `HeaderRegexp`. A v2-era rule such as
`Host(`x`) && HeadersRegexp(`Authorization`, `.+`)` does not error at apply time — it applies
successfully and **simply never matches**, so requests fall through to whatever lower-priority route
shares that host (or to a 404). The failure looks like an auth or routing bug, not a config error, and
`kubectl get ingressroute` still prints the rule verbatim, so it reads as correct.

How this presented: an OTLP route that should have required a bearer header instead routed every
request — header present or not — to a deliberate 401 fixture, and the giveaway was the `server: nginx`
response header identifying the wrong backend. Confirming the version (`kubectl get deploy traefik -o
jsonpath='{..image}'` → `rancher/mirrored-library-traefik:3.6.13`) is what settled it.

Check every `HeadersRegexp` / `Headers` matcher when a cluster has been upgraded to Traefik v3, and
prefer asserting a probe's *backend* (response headers, or a distinctive body) over its status code —
a 401 from the wrong service looks identical to a 401 from the right one.
