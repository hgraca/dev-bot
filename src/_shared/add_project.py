#!/usr/bin/env python3
"""Idempotently add project paths to .devbot.global.jsonc::projects.

Usage:
  add_project.py <config_file> <project_path> [<project_path>...]

Exit codes:
  0 — every project was already registered (no-op)
  0 — at least one project was added
  1 — error (file missing, parse error, lock failure, etc.)

The script reads via read_jsonc (strips // and /* */ comments), adds the paths
that are missing, and writes back as JSON.

Two hardening rules, both required by `devbot init --all -j N`:
  - the read-modify-write runs under an exclusive flock on a sibling lock file,
    so concurrent invocations cannot lose each other's entry;
  - the write lands in a temp file beside the config and is moved into place
    with os.replace(), so no reader ever observes partially written JSON.

The lock file is never unlinked — removing it would let a later process lock a
fresh inode while an earlier one still holds the old inode.
"""

import fcntl
import json
import os
import sys
import tempfile


def load_jsonc(path):
    """Read a JSONC file, strip comments (reuse read_jsonc logic)."""
    with open(path) as f:
        raw = f.read()

    out = []
    i = 0
    while i < len(raw):
        if raw[i] == '"':
            j = i + 1
            while j < len(raw):
                if raw[j] == "\\":
                    j += 2
                elif raw[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            out.append(raw[i:j])
            i = j
            continue

        if raw[i : i + 2] == "//":
            j = raw.find("\n", i)
            if j == -1:
                break
            i = j
            continue

        if raw[i : i + 2] == "/*":
            j = raw.find("*/", i + 2)
            if j == -1:
                break
            i = j + 2
            continue

        out.append(raw[i])
        i += 1

    return json.loads("".join(out))


def lock_path(config_file):
    """A companion path for the lock, derived from the config it protects.

    Never the config itself: the config is replaced by os.replace(), which
    swaps the inode, so a lock held on the old inode would stop protecting the
    new one.

    Keyed by the canonical config path, not by DEV_BOT_ROOT: the registry can
    be redirected with DEV_BOT_GLOBAL_CONFIG, and two invocations carrying
    different roots would otherwise lock different files while writing the
    same config — exactly the lost update this lock exists to prevent.
    """
    return os.path.realpath(config_file) + ".lock"


def register(data, paths):
    """Add the missing paths in place; return those actually added."""
    known = {os.path.normpath(p) for p in data.setdefault("projects", [])}

    added = []
    for raw in paths:
        norm = os.path.normpath(os.path.abspath(raw))
        if norm in known:
            continue
        known.add(norm)
        added.append(norm)

    if added:
        data["projects"] = sorted(known, key=str.lower)

    return added


def main():
    if len(sys.argv) < 3:
        print(
            "Usage: add_project.py <config_file> <project_path> [<project_path>...]",
            file=sys.stderr,
        )
        sys.exit(1)

    config_file = sys.argv[1]

    if not os.path.isfile(config_file):
        print(f"Config file not found: {config_file}", file=sys.stderr)
        sys.exit(1)

    lock_file = lock_path(config_file)
    lock_dir = os.path.dirname(lock_file) or "."
    try:
        os.makedirs(lock_dir, exist_ok=True)
        lock = open(lock_file, "a")
    except OSError as e:
        print(f"Failed to open lock {lock_file}: {e}", file=sys.stderr)
        sys.exit(1)

    with lock:
        fcntl.flock(lock, fcntl.LOCK_EX)

        try:
            data = load_jsonc(config_file)
        except Exception as e:
            print(f"Failed to parse {config_file}: {e}", file=sys.stderr)
            sys.exit(1)

        added = register(data, sys.argv[2:])
        if not added:
            sys.exit(0)

        config_dir = os.path.dirname(os.path.abspath(config_file))
        # Keep the config's mode: mkstemp creates 0600, and replacing a 0644
        # registry with it would silently change who can read it.
        try:
            mode = os.stat(config_file).st_mode & 0o777
        except OSError:
            mode = 0o644
        try:
            fd, tmp = tempfile.mkstemp(
                dir=config_dir, prefix=".devbot.global.", suffix=".tmp"
            )
        except OSError as e:
            print(f"Failed to write {config_file}: {e}", file=sys.stderr)
            sys.exit(1)
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(data, f, indent=2)
                f.write("\n")
                f.flush()
                os.fsync(f.fileno())
            os.chmod(tmp, mode)
            os.replace(tmp, config_file)
        except BaseException:
            os.unlink(tmp)
            raise

    for norm in added:
        print(f"Registered project: {norm}", file=sys.stderr)


if __name__ == "__main__":
    main()
