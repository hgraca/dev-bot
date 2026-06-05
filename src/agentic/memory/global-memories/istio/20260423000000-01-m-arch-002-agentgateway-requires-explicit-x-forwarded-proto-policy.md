---
date: 2026-04-23
keywords: ["istio"]
---

## M-ARCH-002: Agentgateway requires explicit X-Forwarded-Proto policy

Staging DNS switch to Agentgateway caused ERR_TOO_MANY_REDIRECTS on all HTTPS-enforcing services (Laravel, Core).
Unlike Istio (which set X-Forwarded-Proto via sidecar), Agentgateway does not set forwarded headers by default. An `AgentgatewayPolicy` with `traffic.transformation.request.set` targeting the Gateway is required. This must be part of the base Agentgateway installation in every environment — not an afterthought.
