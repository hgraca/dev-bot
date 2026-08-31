---
date: 2026-08-21
keywords: ["k8s", "nginx", "php-fpm", "preStop", "rolling-deploy"]
trigger-on: ["nginx-php-fpm-pod", "rolling-deploy-502", "prestop-graceful-shutdown"]
---

## nginx + PHP-FPM pod returns 502 during rolling deploys — pod drained mid-request

A two-container pod (nginx → PHP-FPM) returns 502 Bad Gateway during rolling deploys when the pod is deleted while still serving in-flight requests. With no `preStop` hook and only a TCP `readinessProbe`, the pod keeps accepting traffic until it dies; SIGTERM reaches nginx and PHP-FPM at once, PHP-FPM exits first, and nginx logs `recv() failed (104: Connection reset by peer) while reading response header from upstream` then returns 502. Fix: add a `preStop` sleep (e.g. 15s) to BOTH containers — not just nginx, or PHP-FPM still dies immediately while nginx keeps forwarding during the sleep — plus `terminationGracePeriodSeconds` longer than the sleep (e.g. 30). Optionally lower `maxSurge` to avoid a 2× pod spike during the roll. A span named after an nginx `@backend` named location with `responseStatusCode 502` is this exact symptom.
