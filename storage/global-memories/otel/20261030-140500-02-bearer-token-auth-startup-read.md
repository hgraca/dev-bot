---
date: 2026-10-30
keywords: ["otel", "bearertokenauth", "authenticator", "otlp", "gateway"]
aliases: ["bearer token extension reads the file once", "receiver auth key is singular"]
trigger-on: ["otelcol-receiver-auth"]
---

## Enabling bearer-token auth on an OTel collector: singular key, and a restart to reload

Three things bite when adding `bearertokenauth` to an OTel collector:

1. **The server-side key is singular.** A receiver takes `auth: { authenticator: <id> }` — *not*
   `authenticators:`. The plural form fails validation with `'confighttp.AuthConfig' has invalid keys:
   authenticators`, and since the collector validates at startup the pod crashloops rather than
   degrading. Validate before applying:
   `docker run --rm -v <dir>:/etc/otel:ro otel/opentelemetry-collector-contrib:<tag> validate --config=/etc/otel/config.yaml`
   — same image tag as the deployment, exit 0 and silence on success.

2. **The component is `bearertokenauth`.** `bearertokenauthextension` is the module name, not the
   component id; confirm in the actual build with
   `kubectl exec deploy/<c> -- /otelcol-contrib components | grep -i bearer`.

3. **The token file is read at startup only.** With `filename:` mode the extension logs
   `refresh token {"filename": …}` once during start-up and does not watch the file, so adding or
   revoking a token in the backing Secret has **no effect until the pod restarts** — a revoked token
   keeps working from memory, and a newly added one keeps being rejected. Always follow a token change
   with `rollout restart` and then re-verify.

Also worth knowing: a Traefik-style route matcher that only checks the header is *present*
(`HeaderRegexp(Authorization, .+)`) authenticates nothing — the collector is where the token must be
validated, and enforcing there also covers LoadBalancer ports that never traverse the ingress.
