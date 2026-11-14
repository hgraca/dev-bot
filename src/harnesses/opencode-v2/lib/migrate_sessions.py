#!/usr/bin/env python3
"""Copy OpenCode 1.x sessions into the 2.x store.

1.x writes ``session``/``message``/``part``; 2.x reads ``session_v2`` and
``session_message``. The two are parallel stores — nothing migrates them — so a
session created on one host is invisible to the other.

This copies every 1.x session into the 2.x tables, translating v1 messages and
their parts into the v2 message body:

    user message      -> {time, text, files}
    assistant message -> {time, agent, model, content[], finish, cost, tokens}

Parts map into ``content``: ``text``/``reasoning`` keep their text, a ``tool``
part becomes a completed tool entry carrying its input and output.

Useful forms:

  migrate_sessions.py <db>                 # add what is missing
  migrate_sessions.py <db> --reset         # drop migrated rows, re-copy them
  migrate_sessions.py <db> --reset --purge # wipe the 2.x store, re-copy 1.x
  migrate_sessions.py <db> --only-pinned   # copy just the pinned sessions

``--reset`` clears only rows whose ``version`` is 1.x — the ones this script
wrote — so sessions created natively on a 2.x host survive a re-run. ``--purge``
removes every 2.x row as well; it is the "start clean" switch and the only one
that can lose 2.x work.
"""

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time


def pinned_session_ids():
    """Session ids pinned in the TUI (~/.local/state/opencode/session.json)."""
    state = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    path = os.path.join(state, "opencode", "session.json")
    try:
        with open(path) as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return []
    return [value for value in (data.get("pinned") or []) if isinstance(value, str)]


def _project_id(con, directory):
    row = con.execute(
        "select project_id from project_directory where directory = ?", (directory,)
    ).fetchone()
    if row:
        return row[0]
    row = con.execute("select id from project where worktree = ?", (directory,)).fetchone()
    if row:
        return row[0]
    pid = hashlib.sha1(directory.encode()).hexdigest()
    now = int(time.time() * 1000)
    con.execute(
        "insert or ignore into project (id, worktree, vcs, sandboxes, time_created, time_updated) "
        "values (?, ?, ?, ?, ?, ?)",
        (pid, directory, "git", "[]", now, now),
    )
    con.execute(
        "insert or ignore into project_directory (project_id, directory, type, time_created) "
        "values (?, ?, ?, ?)",
        (pid, directory, "main", now),
    )
    return pid


def _tokens(value):
    value = value or {}
    cache = value.get("cache") or {}
    return {
        "input": value.get("input") or 0,
        "output": value.get("output") or 0,
        "reasoning": value.get("reasoning") or 0,
        "cache": {"read": cache.get("read") or 0, "write": cache.get("write") or 0},
    }


def _tool_content(part):
    state = part.get("state") or {}
    output = state.get("output")
    content = []
    if isinstance(output, str) and output:
        content.append({"type": "text", "text": output})
    return {
        "type": "tool",
        "id": part.get("callID") or part.get("id") or "",
        "name": part.get("tool") or "unknown",
        "executed": True,
        "time": {
            "created": part.get("_created"),
            "ran": part.get("_created"),
            "completed": part.get("_updated"),
        },
        "state": {
            "status": state.get("status") or "completed",
            "input": state.get("input") or {},
            "content": content,
            "metadata": state.get("metadata") or {},
        },
    }


def _build_message(role, data, parts, created, fallback_model=None):
    texts = [p.get("text", "") for p in parts if p.get("type") == "text"]
    if role == "user":
        return "user", {
            "time": {"created": created},
            "text": "\n".join(t for t in texts if t),
            "files": [],
        }

    content = []
    finish = None
    cost = 0.0
    tokens = _tokens(None)
    for part in parts:
        kind = part.get("type")
        if kind == "text":
            content.append({"type": "text", "text": part.get("text", "")})
        elif kind == "reasoning":
            # v2 requires `native` and `time` on a reasoning entry; omitting
            # either fails the whole message's decode.
            content.append(
                {
                    "type": "reasoning",
                    "text": part.get("text", ""),
                    "native": {"reasoningField": "reasoning_content"},
                    "time": {
                        "created": part.get("_created"),
                        "completed": part.get("_updated"),
                    },
                }
            )
        elif kind == "tool":
            # v2's tool-entry schema varies by state (completed, error, pending)
            # and a single mismatched entry makes the whole session unopenable.
            # Only the completed shape is known to decode, so every tool is
            # replayed as a readable text line instead: the name, the status,
            # what it was asked to do, and the start of its output.
            state = part.get("state") or {}
            status = state.get("status") or "completed"
            detail = state.get("error") or state.get("output") or ""
            requested = state.get("input") or {}
            if isinstance(requested, dict):
                requested = requested.get("command") or requested.get("filePath") or requested
            content.append(
                {
                    "type": "text",
                    "text": "[tool %s: %s] %s%s"
                    % (
                        part.get("tool") or "unknown",
                        status,
                        str(requested)[:300],
                        (" -> " + str(detail)[:1200]) if detail else "",
                    ),
                }
            )
        elif kind == "step-finish":
            finish = part.get("reason") or finish
            cost += part.get("cost") or 0
            tokens = _tokens(part.get("tokens") or tokens)

    model = data.get("model") or {}
    body = {
        "time": {"created": created, "completed": created},
        "agent": data.get("agent") or data.get("mode") or "devbot",
        "content": content,
        # `finish` is a required enum on a 2.x assistant message; a 1.x message
        # with no step-finish part has none, and null fails the decode.
        "finish": finish or "stop",
        "rawFinish": finish or "stop",
        "cost": cost,
        "tokens": tokens,
    }
    # A 2.x model carries `variant` only when one was chosen: writing
    # `variant: null` fails the message's schema and the session will not
    # decode. An incomplete model is omitted rather than written empty.
    # `model` is REQUIRED on a 2.x assistant message: without it the message
    # fails to decode and the whole session becomes unopenable. Most 1.x
    # messages carry no model of their own, so fall back to the session's.
    chosen = {
        "id": model.get("modelID") or model.get("id") or "",
        "providerID": model.get("providerID") or "",
    }
    if model.get("variant"):
        chosen["variant"] = model["variant"]
    if not (chosen["id"] and chosen["providerID"]):
        chosen = dict(fallback_model or {"id": "unknown", "providerID": "unknown"})
    if not (chosen.get("id") and chosen.get("providerID")):
        chosen = {"id": "unknown", "providerID": "unknown"}
    body["model"] = chosen
    return "assistant", body


def clear(con, purge=False, only_ids=None, directory=None):
    """Delete migrated rows, or every 2.x row when `purge` is set."""
    if purge:
        # A purge is always total: "start clean", whatever the selection is.
        ids = [r[0] for r in con.execute("select id from session_v2")]
    else:
        ids = [r[0] for r in con.execute("select id from session_v2 where version like '1.%'")]
        if only_ids is not None:
            ids = [value for value in ids if value in only_ids]
        if directory is not None:
            # A directory-scoped reset replaces only what that copy rewrites;
            # clearing every migrated row would erase other projects' sessions.
            in_dir = {
                r[0]
                for r in con.execute("select id from session where directory = ?", (directory,))
            }
            ids = [value for value in ids if value in in_dir]

    removed = 0
    for start in range(0, len(ids), 500):
        chunk = ids[start:start + 500]
        marks = ",".join("?" for _ in chunk)
        con.execute(f"delete from session_part where session_id in ({marks})", chunk)
        con.execute(f"delete from session_message where session_id in ({marks})", chunk)
        removed += con.execute(f"delete from session_v2 where id in ({marks})", chunk).rowcount
    # No commit here: main() owns the transaction so --dry-run can undo the
    # clear as well as the copy. A committed clear made the dry run destructive.
    return removed


def migrate(con, directory=None, dry_run=False, only_ids=None):
    where = "where directory = ?" if directory else ""
    args = (directory,) if directory else ()
    sessions = con.execute(
        f"select id, directory, time_created, time_updated, model from session {where}", args
    ).fetchall()

    if only_ids is not None:
        sessions = [row for row in sessions if row[0] in only_ids]

    already = {r[0] for r in con.execute("select id from session_v2")}
    migrated = skipped = messages = 0

    for sid, sdir, created, updated, raw_model in sessions:
        if sid in already:
            skipped += 1
            continue

        con.execute(
            """
            insert into session_v2 (
              id, project_id, workspace_id, parent_id, fork_session_id, fork_boundary,
              slug, directory, path, title, version, share_url,
              summary_additions, summary_deletions, summary_files, summary_diffs,
              metadata, cost, tokens_input, tokens_output, tokens_reasoning,
              tokens_cache_read, tokens_cache_write, revert, permission, agent, model,
              time_created, time_updated, time_compacting, time_archived,
              time_suspended, resume_attempts, time_idle, time_viewed, idle_outcome, time_busy
            )
            select
              id, ?, workspace_id, parent_id, null, null,
              slug, directory, path, title, version, share_url,
              summary_additions, summary_deletions, summary_files, summary_diffs,
              metadata, cost, tokens_input, tokens_output, tokens_reasoning,
              tokens_cache_read, tokens_cache_write, revert, permission, agent, model,
              time_created, time_updated, time_compacting, time_archived,
              null, 0, null, null, null, null
            from session where id = ?
            """,
            (_project_id(con, sdir), sid),
        )
        migrated += 1

        try:
            session_model = json.loads(raw_model) if raw_model else None
        except (TypeError, ValueError):
            session_model = None
        if not (isinstance(session_model, dict) and session_model.get("providerID")):
            session_model = None

        rows = con.execute(
            "select id, time_created, time_updated, data from message "
            "where session_id = ? order by time_created, id",
            (sid,),
        ).fetchall()
        for seq, (mid, mcreated, mupdated, raw) in enumerate(rows):
            try:
                data = json.loads(raw)
            except (TypeError, ValueError):
                continue
            parts = []
            for praw, ptc, ptu in con.execute(
                "select data, time_created, time_updated from part "
                "where message_id = ? order by time_created, id",
                (mid,),
            ):
                try:
                    part = json.loads(praw)
                except (TypeError, ValueError):
                    continue
                # v2 content entries carry their own timestamps.
                part["_created"] = ptc or mcreated
                part["_updated"] = ptu or mcreated
                parts.append(part)
            kind, body = _build_message(
                data.get("role") or "assistant", data, parts, mcreated, session_model
            )
            con.execute(
                "insert or replace into session_message "
                "(id, session_id, type, seq, time_created, time_updated, data) "
                "values (?, ?, ?, ?, ?, ?, ?)",
                (mid, sid, kind, seq, mcreated, mupdated, json.dumps(body)),
            )
            messages += 1

    if dry_run:
        con.rollback()
    else:
        con.commit()
    return migrated, skipped, messages


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("db")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--directory")
    parser.add_argument("--reset", action="store_true", help="clear migrated 1.x rows first")
    parser.add_argument("--purge", action="store_true", help="clear every 2.x row first")
    parser.add_argument(
        "--only-pinned",
        action="store_true",
        help="copy only the sessions pinned in the TUI",
    )
    args = parser.parse_args(argv)
    if args.purge:
        args.reset = True

    only_ids = set(pinned_session_ids()) if args.only_pinned else None
    if args.only_pinned and not only_ids:
        print("no pinned sessions found — nothing to do")
        return 0
    if args.only_pinned:
        print(f"pinned sessions: {len(only_ids)}")

    con = sqlite3.connect(args.db)
    try:
        if args.reset:
            removed = clear(
                con,
                purge=args.purge,
                only_ids=only_ids,
                directory=None if args.purge else args.directory,
            )
            verb = "purged" if args.purge else "cleared"
            if args.dry_run:
                print(f"would have {verb} {removed} session(s)")
            else:
                print(f"{verb} {removed} session(s)")
        migrated, skipped, messages = migrate(con, args.directory, args.dry_run, only_ids)
    finally:
        con.close()

    verb = "would migrate" if args.dry_run else "migrated"
    print(f"{verb} {migrated} session(s), {messages} message(s); skipped {skipped} already present")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
