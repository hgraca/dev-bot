---
date: 2026-04-24
keywords: ["kafka", "consumer", "partition"]
---

## M-ARCH-002: PARTITION_EOF means "caught up", not "no more messages"

The original `consume()` returned `null` immediately on `PARTITION_EOF`. In a short-poll loop, this caused premature return — the consumer would stop waiting even though new messages could arrive within the timeout window.
`RD_KAFKA_RESP_ERR__PARTITION_EOF` signals that the consumer has read all currently available messages in the partition. It does NOT mean no more messages will arrive. In a polling loop, always continue polling on `PARTITION_EOF` until the total timeout expires.
