---
date: 2026-08-24
keywords: ["k8s", "nginx", "php-fpm", "native-sidecar", "startup-gating"]
trigger-on: ["nginx-php-fpm-pod", "php-fpm-native-sidecar", "php-fpm-startup-gating"]
---

## Gate nginx on php-fpm readiness via native sidecar

To stop 502s during pod _startup_ (distinct from the rolling-deploy preStop/grace fix), run php-fpm as a K8s native sidecar: declare it in `initContainers` with `restartPolicy: Always` (K8s ≥1.29) and give it a `startupProbe: tcpSocket: {port: 9000}` (period 5, failureThreshold 60). nginx becomes the only regular container and its old `startupProbe` becomes a `readinessProbe` (httpGet app path, e.g. `/ping`/`/up`). Because the main containers don't start until the sidecar's startupProbe passes, the kubelet never probes the app before PHP-FPM is listening. Add a deep `livenessProbe` exec FastCGI handshake (`php -r 'fsockopen 127.0.0.1:9000 ...'`) to catch a hung FPM that tcpSocket misses. Note this shifts container indices (php-fpm = initContainer 0, nginx = container 0), so any index-based kustomize/JSON patches must be re-targeted. Companion to the preStop+grace fix; both are needed for a fully 502-free nginx/php-fpm pod.
