---
date: 2026-09-18
keywords: ["mariadb", "max_connect_errors", "aborted_connects", "health-probe"]
trigger-on: ["mariadb-connection-probe", "database-reachability-check", "max-connect-errors"]
---

## A bare TCP connect-and-close counts toward max_connect_errors and can block a host

A reachability check that opens a TCP socket to the MariaDB/MySQL port and closes it without completing the handshake increments the server's `Aborted_connects` counter for that client host. MariaDB/MySQL tracks those per host, and once a host exceeds `max_connect_errors` (default **100**) it refuses every further connection from it with **Error 1129 `Host '...' is blocked because of many connection errors; unblock with 'mariadb-admin flush-hosts'`**. Measured directly: 20 bare `socket.create_connection((host, port)).close()` calls moved `Aborted_connects` from 5838 to 5858 — exactly +20, with `max_connect_errors = 100`.

The trap is that a polling loop blocks its own host. At a 10-second interval roughly 100 dials accumulate in under 17 minutes, and once blocked the TCP connect **still succeeds** (the server accepts, then errors during the handshake), so a naive probe keeps reporting "reachable" while every real query fails — a self-sustaining loop that never self-heals. The block also does not expire: it clears only with `FLUSH HOSTS` or a server restart, both server-side actions you may not be able to take.

Two rules follow. Probe with a real protocol handshake (a client connection plus `SELECT 1`), never a socket open/close — that keeps the counters clean and correctly detects 1129, bad credentials and max_connections. And never dial a host you have already decided not to use: validate configuration and credential completeness *before* probing, so a deliberately disabled datasource is never contacted. Note that connections from `localhost` are exempt from the block, which is why the same polling pattern can run for weeks locally (5838 aborted connects and still serving) and only break against a remote server.
