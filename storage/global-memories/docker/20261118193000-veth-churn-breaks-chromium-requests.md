---
date: 2026-11-18
keywords: ["docker", "veth", "ERR_NETWORK_CHANGED", "network isolation", "netlink"]
aliases: ["veth churn", "network change was detected", "container breaks browser"]
trigger-on: ["docker-run", "container-network-mode"]
---

## A container that never joins a bridge creates no veth — and veth churn aborts in-flight browser requests

Every `docker run` on the default bridge creates a `veth` pair, and each half coming up or going down is
a netlink link event. Chromium subscribes to `RTMGRP_LINK` (`net/base/address_tracker_linux.cc`), treats
a fully-up interface as a network change and aborts in-flight requests with `ERR_NETWORK_CHANGED`
("A network change was detected"). A tool that spawns one container per operation — a linter, a
transform engine, a per-file scanner — therefore churns the developer's network stack hard enough that
a page taking more than a second to load fails consistently while a fast page survives. That
asymmetry reads as "this one URL is blocked", which sends people chasing repo permissions, TLS
interception and VPN.

Fix it at the source, not in the browser: give every container that does not need the network
`--network none` (no bridge, no veth pair), and the one that legitimately does (an installer) `--network
host`, which also skips the bridge. Measured on one machine: a bridge-attached one-shot container = 2
`renamed from` kernel events, the same container with `--network none` = 0; a test suite that had
spawned containers per assertion dropped from 59–109 interface events per minute to 4 in a whole run.
Verify with `journalctl -k --since -5m | grep -c 'renamed from'` rather than trusting a green suite —
the churn is invisible to the tests it comes from.
