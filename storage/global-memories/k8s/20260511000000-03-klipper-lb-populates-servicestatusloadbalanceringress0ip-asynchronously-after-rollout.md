---
date: 2026-05-11
keywords: ["k8s", "kubectl"]
---

## klipper-lb populates `Service.status.loadBalancer.ingress[0].ip` asynchronously after rollout

After `kubectl rollout status deployment/X` returns success, the LoadBalancer Service may still have an empty `.status.loadBalancer.ingress[]` for 5-30s while k3s klipper-lb wires up the routing. An immediate `kubectl get svc … -o jsonpath='{.status.loadBalancer.ingress[0].ip}'` prints empty string on slow systems, making Makefile banners say `LoadBalancer: ` with no IP.
Fix: Gate the echo on a `kubectl wait --for=jsonpath='{.status.loadBalancer.ingress[0].ip}' svc/<name> -n <ns> --timeout=30s 2>/dev/null || true` line. Soft-fail (`|| true`) so the target doesn't break if klipper-lb is slow beyond 30s — the empty echo is a soft signal, not a hard failure. Pattern applied in `Makefile:otel-gateway-deploy` (commit `c21d4dd`).
