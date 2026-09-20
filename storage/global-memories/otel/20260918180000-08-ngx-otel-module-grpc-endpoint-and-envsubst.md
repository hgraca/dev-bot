---
date: 2026-09-18
keywords: ["otel", "nginx", "ngx_otel_module", "otlp", "envsubst"]
trigger-on: ["nginx-otel", "ngx_otel_module", "otel-exporter-endpoint"]
---

## ngx_otel_module needs the OTLP/gRPC endpoint, and nginx will not start if the envsubst vars are missing

nginx's official OpenTelemetry dynamic module exports over OTLP/gRPC, so its `otel_exporter { endpoint ...; }` must point at the collector's gRPC port (4317) — reusing the PHP SDK's http/protobuf endpoint (4318) aims nginx at the wrong protocol. Separately, when the config is delivered through `/etc/nginx/templates/`, the image entrypoint's envsubst substitutes only variables present in the environment: anything not injected stays as a literal `${OTEL_SERVICE_NAME}` and nginx fails to parse its configuration, crash-looping. Deployment manifests must therefore set those variables on the **nginx** container, not only on the PHP one.
