---
date: 2026-09-22
keywords: ["redis", "phpredis", "redis-cluster", "laravel"]
trigger-on: ["redis-cluster-unreachable", "laravel-redis-cluster-config"]
---

## An unreachable RedisCluster reports `getaddrinfo for ''` — not an empty host in your config

When the Redis service is down, every `Redis::*` call through Laravel surfaces as `RedisCluster::flushdb(): php_network_getaddresses: getaddrinfo for  failed: Name or service not known` — phpredis renders failed cluster seed discovery with an **empty host string**, so the error looks like a config bug (a host option that resolved to `''`) rather than a reachability failure. Chase reachability first (`docker ps | grep redis`, `redis-cli -h <host> ping`); in this case `shared-redis-1` was simply not running and the identical config passed the moment it started. Two nested traps: (1) the same error text appears in `setUp()` of an unrelated test file, so it reads as "my change broke the suite" — it is emitted before any test body runs; (2) a config where `database.redis.options.cluster` names a cluster key that does not exist under `clusters` is *harmless* in modern Laravel — `RedisManager::resolve($name)` selects the cluster by **connection name** (`clusters.default` for the default connection), and `PhpRedisConnector::createRedisClusterInstance()` uses that option only as the phpredis cluster *name*, never for host lookup. Do not "fix" the config shape on the strength of this error.
