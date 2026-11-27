#!/usr/bin/env python3
# ---
# description: Rebuild the last assistant turn of a Claude Code transcript as a validator message
# ---
# =============================================================================
# src/agentic/agent-communication/tools/claudecode-idle.py
# Claude Code writes one JSONL record per content block, repeating the message
# id (src/harnesses/claudecode/stats.py documents the shape), so the last turn
# is every record sharing the last assistant message id — not the last line.
#
# Transcripts grow for the life of a session, so the file is read from its end:
# a bounded window that widens until the whole selected turn is inside it.
# =============================================================================

import argparse
import json
import os
import sys

WINDOW_BYTES = 256 * 1024
# A turn larger than this is pathological; stop widening and accept it.
MAX_WINDOW_BYTES = 8 * 1024 * 1024


def _records(path, window):
    """Assistant records inside the trailing window, oldest first.

    Returns the records and whether the window started mid-file, which is how
    a scan knows a turn may continue before what it read.
    """
    size = os.path.getsize(path)
    start = max(0, size - window)
    with open(path, "rb") as fh:
        fh.seek(start)
        chunk = fh.read()
    if start > 0:
        # The first line is a fragment of a record outside the window.
        newline = chunk.find(b"\n")
        chunk = chunk[newline + 1 :] if newline != -1 else b""

    out = []
    for line in chunk.splitlines():
        if not line.strip():
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if not isinstance(record, dict):
            continue
        message = record.get("message") if isinstance(record.get("message"), dict) else {}
        role = message.get("role") or record.get("type") or ""
        if role == "assistant":
            out.append(message)
    return out, start > 0


def last_turn(path):
    size = os.path.getsize(path)
    window = min(WINDOW_BYTES, size)
    while True:
        records, truncated = _records(path, window)
        if records:
            message_id = records[-1].get("id")
            # The selected turn is truncated while the window's oldest record
            # belongs to it: widen rather than publish a partial turn. An
            # id-less turn is a single record and cannot be widened for, so
            # the scan stops instead of re-reading the file on every Stop.
            if (
                not truncated
                or message_id is None
                or records[0].get("id") != message_id
            ):
                break
        # Nothing left to read: a partial turn is not published, and the cap
        # must end the scan rather than spin on a window that cannot grow.
        if window >= size or window >= MAX_WINDOW_BYTES:
            return None
        window = min(window * 2, size, MAX_WINDOW_BYTES)

    message = records[-1]
    message_id = message.get("id")
    # Without an id the turn is a single record; with one, every record sharing
    # it belongs to the same turn.
    turn = [m for m in records if m.get("id") == message_id] if message_id else [message]

    texts, tools = [], []
    for record in turn:
        for block in record.get("content") or []:
            if not isinstance(block, dict):
                continue
            kind = block.get("type")
            if kind == "text":
                texts.append(str(block.get("text") or ""))
            elif kind == "tool_use":
                args = block.get("input") if isinstance(block.get("input"), dict) else {}
                # The validator's wait check knows `bash`/`shell`, not `Bash`.
                tools.append(
                    {
                        "type": "tool",
                        "tool": str(block.get("name") or "").lower(),
                        "background": bool(args.get("background") or args.get("run_in_background")),
                        "state": {"status": "completed", "input": args},
                    }
                )
    parts = [{"type": "text", "text": "\n".join(texts)}] + tools
    return {"info": {"role": "assistant"}, "parts": parts}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--transcript", required=True)
    args = parser.parse_args()

    message = last_turn(args.transcript)
    if not message:
        return 0
    text = message["parts"][0]["text"]
    if not text and not any(p["type"] == "tool" for p in message["parts"]):
        return 0
    json.dump(message, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
