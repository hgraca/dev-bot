---
date: 2026-10-29
keywords: ["signoz", "cold-storage", "clickhouse", "s3", "retention"]
aliases: ["awss3 exporter", "offload to S3", "infinite retention", "tiered storage", "cold tier"]
---

## SigNoz cold storage is a ClickHouse tiered volume, not the OTel `awss3` exporter

Two different features get called "S3 retention in SigNoz" and they behave nothing
alike. **ClickHouse cold storage** (self-host, `clickhouse.coldStorage`) creates a
ClickHouse storage policy named `tiered` — `default` disk plus an `s3` (or `gcs`)
volume — and SigNoz then rewrites each managed table's TTL as
`<delete expr>, <time col> + INTERVAL n SECOND TO VOLUME 's3'`, so old parts move to
object storage and remain fully queryable in the SigNoz UI. It is implemented in
`pkg/query-service/app/clickhouseReader/reader.go`: `setTTLLogs`, `setTTLTraces` and
`setTTLMetrics` all read `params.ColdStorageVolume` / `params.ToColdStorageDuration`,
and every emitted ALTER carries `SETTINGS materialize_ttl_after_modify=0` (the same
guard needed to avoid leaving a wedged `MATERIALIZE TTL` mutation). As of chart
0.143.0 **all three signals support it**, including `samples_v4`,
`samples_v4_agg_5m/30m`, `exp_hist` and every `time_series_v4*` table — do not infer
signal coverage from the presence of a `_retention_days_cold` column, which only the
column-driven logs tables carry.

The **OTel Collector `awss3` exporter** is unrelated: it fans telemetry out to S3 as
compressed `otlp_json` objects which are invisible to the SigNoz UI and need Athena
(or similar) to query. The public docs page "Infinite Retention of OpenTelemetry Data
in AWS S3" documents that exporter, so searching the docs for "cold storage" lands on
the wrong mechanism.

Practical consequences: the chart templates the policy but does not wire the volume
*name* into the SigNoz deployment — `ColdStorageVolume` is an API parameter, so the
volume name has to be supplied through the retention API/UI, and a plain
`coldStorage.enabled: true` is not sufficient on its own. Query cost is dominated by
object-storage egress rather than storage: a co-located S3-compatible store (e.g. an
object-storage bucket in the same datacentre/location) is an order of magnitude
cheaper per TB-read than cross-cloud AWS egress. The policy also sets
`prefer_not_to_merge: 1`, so cold parts are never merged — many small objects, more
GETs, slower wide-range scans — and the chart configures no local object-storage
cache, so repeated cold queries re-download every time.
