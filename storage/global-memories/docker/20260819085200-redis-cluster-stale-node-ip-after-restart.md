---
date: 2026-08-19
keywords: ["docker", "redis", "cluster", "cluster-announce-ip", "nodes.conf"]
trigger-on: ["redis-cluster-stale-ip", "redis-cluster-restart", "phpredis-cluster"]
---

## Redis single-node cluster keeps a stale node IP after a Docker restart

The dev stack runs Redis as a single-node cluster (shared compose; `cluster-announce-ip` is set to the container IP at init). On container restart Redis gets a new IP, but the persisted `nodes.conf` retains the OLD IP, so `CLUSTER SLOTS` returns a stale node address and PhpRedis fails with `RedisClusterException: Unable to send command at a specific node` on `Redis::flushdb()`. The `redis-init` service skips re-init when `cluster_slots_assigned:16384` is already set, so it does not repair the stale IP. Fix: `redis-cli CLUSTER RESET HARD`, then `CONFIG SET cluster-announce-ip $(getent hosts redis | cut -d' ' -f1)`, then re-add slots — `CLUSTER ADDSLOTS $(seq 0 5461 | tr '\n' ' ')` (and the two remaining ranges); `CLUSTER ADDSLOTSRANGE` is Redis 7+ and unavailable in the 6.2 image used here.
