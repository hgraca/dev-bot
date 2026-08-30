#!/usr/bin/env python3
# =============================================================================
# src/harnesses/claudecode/hooks/on-hooks.py
# Generic claudecode hook dispatcher — reads every module's hooks.json manifest
# and routes claudecode hook input to the declared commands.
#
# Usage (invoked from .claude/settings.local.json):
#   python3 src/harnesses/claudecode/hooks/on-hooks.py <phase>
#
# Phases:
#   pre-tool   → PreToolUse (Bash)          → command.before
#   post-file  → PostToolUse (Edit|Write)   → file.edited
#   post-bash  → PostToolUse (Bash)         → command.after
#   stop       → Stop                       → session.idle
#   startup    → SessionStart               → session.created
# =============================================================================

import datetime
import json
import os
import re
import subprocess
import sys

DEV_BOT_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..", ".."))


def load_manifests():
    base = os.path.join(DEV_BOT_ROOT, "src", "agentic")
    hooks = []
    if not os.path.isdir(base):
        return hooks
    for d in sorted(os.listdir(base)):
        mf = os.path.join(base, d, "hooks.json")
        if not os.path.isfile(mf):
            continue
        try:
            data = json.load(open(mf))
        except Exception:
            continue
        for hook in data.get("hooks", []):
            hook["_module"] = os.path.join(base, d)
            hooks.append(hook)
    return hooks


def resolve(run, ctx):
    return [re.sub(r"\{(\w[\w-]*)\}", lambda m: ctx.get(m.group(1), ""), p) for p in run]


def quiet(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run_and_log(cmd, cwd, log_path, hook_id):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
        text = (r.stdout or "").strip()
        if text:
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
            with open(log_path, "a") as f:
                f.write(f"[{ts}] {hook_id}\n{text}\n\n")
    except Exception:
        pass


def run_file_edits(file_path, worktree):
    for hook in load_manifests():
        if hook.get("event") != "file.edited" or not hook.get("run"):
            continue
        match = hook.get("match", {})
        if "file" in match and not re.search(match["file"], file_path):
            continue
        if "content" in match:
            try:
                head = open(file_path).read(4096)
                if not re.search(match["content"], head):
                    continue
            except Exception:
                continue
        cmd = resolve(hook["run"], {"module": hook["_module"], "worktree": worktree, "file": file_path})
        log_path = hook.get("log")
        if log_path:
            run_and_log(cmd, worktree, os.path.join(worktree, log_path), hook["id"])
        else:
            quiet(cmd, worktree)


def main():
    phase = sys.argv[1] if len(sys.argv) > 1 else ""
    data = json.load(sys.stdin)
    worktree = data.get("cwd") or os.getcwd()

    if phase == "pre-tool":
        command = (data.get("tool_input") or {}).get("command") or ""
        tool_name = (data.get("tool_name") or "")
        for hook in load_manifests():
            if hook.get("event") != "command.before" or not hook.get("run"):
                continue
            # Match filtering (same semantics as run_file_edits): a hook scoped
            # to specific tools (e.g. guards' match.tool: ["bash","shell"]) must
            # not fire for every tool. Without this, a future second
            # command.before hook would silently run on every tool call.
            # Case-insensitive: Claude Code reports tool_name as "Bash" while
            # the manifest declares lowercase "bash".
            match = hook.get("match", {})
            if "tool" in match:
                allowed = {t.lower() for t in match["tool"]}
                if tool_name.lower() not in allowed:
                    continue
            ctx = {
                "module": hook["_module"],
                "worktree": worktree,
                "command": command,
                "agent": "",
                "global-config": os.path.join(DEV_BOT_ROOT, ".devbot.global.jsonc"),
                "project-config": os.path.join(worktree, ".devbot.project.jsonc"),
            }
            cmd = resolve(hook["run"], ctx)
            r = subprocess.run(cmd, cwd=worktree, capture_output=True, text=True)
            if hook.get("blocking"):
                try:
                    parsed = json.loads(r.stdout or "{}")
                    if parsed.get("blocked"):
                        # Claude Code's PreToolUse hook contract: the legacy
                        # top-level "decision" field is not recognized (only
                        # approve/block, and the current schema uses
                        # hookSpecificOutput.permissionDecision) — a plain
                        # {"decision":"deny"} is silently IGNORED and the
                        # command runs. Emit the current schema so guards
                        # actually block.
                        print(json.dumps({
                            "hookSpecificOutput": {
                                "hookEventName": "PreToolUse",
                                "permissionDecision": "deny",
                                "permissionDecisionReason": "Command blocked by guard rule: " + (parsed.get("message") or "guard rule"),
                            },
                        }))
                        return
                except Exception:
                    pass

    elif phase == "post-file":
        file_path = (data.get("tool_input") or {}).get("file_path") or ""
        if file_path:
            run_file_edits(file_path, worktree)

    elif phase == "post-bash":
        command = (data.get("tool_input") or {}).get("command") or ""
        exit_code = (data.get("tool_output") or {}).get("exit_code")
        if isinstance(exit_code, (int, float)) and exit_code != 0:
            return
        try:
            hash_ = subprocess.check_output(
                ["git", "-C", worktree, "log", "-1", "--format=%H"],
                text=True, stderr=subprocess.DEVNULL,
            ).strip()
        except Exception:
            hash_ = ""
        for hook in load_manifests():
            if hook.get("event") != "command.after" or not hook.get("run"):
                continue
            match = hook.get("match", {})
            if "command" in match and not re.search(match["command"], command):
                continue
            quiet(resolve(hook["run"], {"module": hook["_module"], "worktree": worktree, "command": command, "hash": hash_}), worktree)

    elif phase == "stop":
        session_id = data.get("session_id") or "default"
        for hook in load_manifests():
            if hook.get("event") != "session.idle" or not hook.get("run"):
                continue
            quiet(resolve(hook["run"], {"module": hook["_module"], "worktree": worktree, "session-id": session_id}), worktree)

    elif phase == "startup":
        for hook in load_manifests():
            if hook.get("event") != "session.created" or not hook.get("run"):
                continue
            quiet(resolve(hook["run"], {"module": hook["_module"], "worktree": worktree}), worktree)


if __name__ == "__main__":
    main()
