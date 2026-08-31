---
date: 2026-07-03
keywords: ["k8s", "kubernetes", "env", "secret", "gotcha"]
---

## Kubernetes env[].value does not support $(VAR) shell-style expansion

Shell-style variable expansion like `$(MYSQL_USER):$(MYSQL_PASSWORD)@tcp($(MYSQL_HOST):$(MYSQL_PORT))/` in a Kubernetes `env[].value` field is NOT expanded by Kubernetes. The literal string is passed to the container. This differs from Docker Compose which does expand such references. To reference values from secrets, use `env[].valueFrom.secretKeyRef` or construct the full string and store it as a single key in the secret.
