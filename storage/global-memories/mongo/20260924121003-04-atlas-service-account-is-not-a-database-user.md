---
date: 2026-09-24
keywords: ["mongo", "atlas", "authentication", "credentials"]
trigger-on: ["mongodb-connection-string", "atlas-auth-setup"]
---

## An Atlas Service Account cannot be used to read the database

A MongoDB Atlas **Service Account** is an OAuth 2.0 client-credential pair (`mdb_sa_id_…` public id, `mdb_sa_sk_…` secret key) for the **Atlas Administration API** — Bearer tokens for managing clusters, users and backups. It is not a database principal, so using it as `mongodb+srv://mdb_sa_id_…:mdb_sa_sk_…@cluster.mongodb.net/…` can never authenticate; SCRAM fails with `auth error: unable to authenticate using mechanism "SCRAM-SHA-1": (AuthenticationFailed)`.

The historical workaround — the Atlas **Data API**, with which an API key could read and write documents over HTTPS — reached end-of-life on 30 September 2025 and is no longer usable. Reading data requires a **database user** (SCRAM password, X.509, AWS IAM, or OIDC Workload Identity Federation); from outside AWS, a read-only SCRAM user scoped to the target database is the pragmatic choice. A service account remains the right tool to _provision_ that user (`atlas dbusers create`, which needs a Project Owner role) — it automates the setup, it does not carry the reads.

Diagnostic shortcut: an auth-stage failure (rather than a server-selection timeout) already proves SRV resolution, TCP and TLS succeeded, so the cluster's IP access list is not the problem.
