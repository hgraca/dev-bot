#!/usr/bin/env python3
# =============================================================================
# src/agentic/datasources/quarantine.py
# Per-datasource failure state, so a source the oracle rejects is retried on a
# backoff instead of on every poll.
#
# Without it a datasource that is down would be re-validated — one toolbox
# container run — every refresh cycle. With it, a rejected source is parked for
# a growing delay (fast retry right after a failure, up to a cap) and a
# successful validation clears its entry. A source toolbox reports as BLOCKED
# (MariaDB Error 1129) is parked longest and labelled, because only an operator
# action (`mariadb-admin flush-hosts`) can unblock it.
#
# State lives in storage/datasources/quarantine.json. Every function takes
# `now`, so backoff behaviour is tested without sleeping; the CLI is what the
# poller uses to decide whether a re-validation is due.
#
# Usage:
#     quarantine.py needs-revalidation <state-file> <interval-seconds>
#     -> exit 0 when a re-validation is due, 1 otherwise
# =============================================================================

import json
import os
import sys
import time
from typing import NoReturn, Optional

BASE_DELAY = 10.0
MAX_DELAY = 300.0
BLOCKED_DELAY = 1800.0

# MariaDB refuses a host with: "Host '…' is blocked because of many connection
# errors; unblock with 'mariadb-admin flush-hosts'." — Error 1129.
BLOCKED_MARKERS = ("1129", "is blocked because of many connection errors")


def fail(message: str) -> NoReturn:
    sys.stderr.write(f"ERROR: {message}\n")
    sys.exit(2)


def default_state_path(dev_bot_root: Optional[str] = None) -> str:
    root = dev_bot_root or os.environ.get("DEV_BOT_ROOT")
    if not root:
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    return os.path.join(root, "storage", "datasources", "quarantine.json")


def _empty() -> dict:
    return {"sources": {}, "validated_at": 0.0}


def load(path: str) -> dict:
    """The state, or a fresh one — a missing or unreadable file is not fatal."""
    if not path or not os.path.isfile(path):
        return _empty()
    try:
        with open(path, encoding="utf-8") as handle:
            state = json.load(handle)
    except (OSError, ValueError):
        return _empty()
    if not isinstance(state, dict):
        return _empty()
    if not isinstance(state.get("sources"), dict):
        state["sources"] = {}
    state.setdefault("validated_at", 0.0)
    return state


def save(path: str, state: dict) -> None:
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)


def is_blocked(reason: str) -> bool:
    text = (reason or "").lower()
    return any(marker in text for marker in BLOCKED_MARKERS)


def held(state: dict, name: str, now: float) -> bool:
    """True while the entry is still parked (its retry has not come due)."""
    entry = state["sources"].get(name)
    return bool(entry) and entry.get("next_retry", 0.0) > now


def held_names(state: dict, now: float) -> list:
    return sorted(name for name in state["sources"] if held(state, name, now))


def due_names(state: dict, now: float) -> list:
    """Entries whose retry delay has elapsed — they get re-offered."""
    return sorted(
        name
        for name, entry in state["sources"].items()
        if entry.get("next_retry", 0.0) <= now
    )


def record_failure(state: dict, name: str, reason: str, now: float) -> None:
    entry = state["sources"].get(name, {})
    fails = int(entry.get("fails", 0)) + 1
    blocked = is_blocked(reason)
    if blocked:
        delay = BLOCKED_DELAY
    else:
        delay = min(BASE_DELAY * (2 ** (fails - 1)), MAX_DELAY)
    state["sources"][name] = {
        "fails": fails,
        "next_retry": now + delay,
        "reason": reason or "",
        "blocked": blocked,
    }


def record_success(state: dict, name: str) -> bool:
    """Clear the entry. Returns True when one was cleared."""
    return state["sources"].pop(name, None) is not None


def needs_revalidation(state: dict, now: float, interval: float) -> bool:
    """Whether the poller should re-render.

    True when a parked source's retry has come due, or when the last
    validation is older than `interval` (so a source that died while published
    is eventually pruned).
    """
    if due_names(state, now):
        return True
    return (now - float(state.get("validated_at", 0.0))) >= interval


def main() -> int:
    argv = sys.argv[1:]
    if not argv or argv[0] != "needs-revalidation" or len(argv) < 3:
        fail("usage: quarantine.py needs-revalidation <state-file> <interval-seconds>")
    state = load(argv[1])
    try:
        interval = float(argv[2])
    except ValueError:
        fail(f"invalid interval: {argv[2]}")
    return 0 if needs_revalidation(state, time.time(), interval) else 1


if __name__ == "__main__":
    sys.exit(main())
