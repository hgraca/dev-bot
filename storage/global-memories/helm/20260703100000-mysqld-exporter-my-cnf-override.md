---
date: 2026-07-03
keywords: ["helm", "mysqld-exporter", "mysql", "my.cnf", "DATA_SOURCE_NAME", "gotcha"]
---

## prometheus-mysql-exporter chart generates my.cnf that overrides DATA_SOURCE_NAME

The `prometheus-mysql-exporter` Helm chart generates a `my.cnf` config file from the `mysql.*` values block (host, user, pass, port). The mysqld_exporter binary reads this config file, which takes priority over the `DATA_SOURCE_NAME` environment variable. Setting `DATA_SOURCE_NAME` via `extraEnvs` has no effect unless the generated `my.cnf` is correct. Use the chart's `mysql` block to set host/user/port, and `mysql.existingPasswordSecret` to reference a password from a Kubernetes secret. The `extraEnvs` approach silently fails because the exporter connects to whatever the `my.cnf` says (defaults to localhost).
