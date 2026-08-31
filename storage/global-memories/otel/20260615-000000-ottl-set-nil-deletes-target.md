---
date: 2026-06-15
keywords: ["otel", "ottl", "transform processor", "nil guard", "set"]
---

## OTTL set() with nil source deletes target attribute — always use nil guard

In OTTL (OpenTelemetry Transformation Language), `set(target, source)` when `source` evaluates to nil sets `target` to nil, which effectively **removes** the attribute from telemetry. This is non-obvious — developers familiar with shell scripting or YAML expect a nil source to be a no-op. Always guard conditional attribute copies with `where source != nil`: e.g., `set(resource.attributes["service.namespace"], resource.attributes["k8s.namespace.name"]) where resource.attributes["k8s.namespace.name"] != nil`. Without the guard, telemetry where the source attribute is absent (e.g., collector self-telemetry) would lose the target attribute entirely. Verified against OTTL README at https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/pkg/ottl/README.md — the `== nil` check is the recommended pattern for "set only if attribute exists."
