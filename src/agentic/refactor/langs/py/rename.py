#!/usr/bin/env python3
"""rope driver for the refactor tool's Python plugin.

Reads a refactor request as JSON on stdin and writes a response as JSON on
stdout, in the same shape the PHP and TypeScript plugins use:
    {ok, engine, applied, summary, files, warnings}

rope is the Python refactoring library: its Rename builds a project-wide change
set from the symbol table, so one run covers the definition and its references.
Unlike the TypeScript compiler it is not fully type-aware, so the reference set is
symbol-table based — good for ordinary code, blind to dynamic construction.
"""

import json
import os
import re
import sys

PROJECT_DIR = os.environ.get("REFACTOR_PROJECT_DIR", "/app")
SOURCE_ROOTS = ("src", "app", ".")


def fail(message):
    sys.stderr.write("ERROR: " + message + "\n")
    sys.exit(1)


def definition_offset(text, name):
    """Offset of a definition of `name`, or None."""
    escaped = re.escape(name)
    for pattern in (
        r"(?:^|\n)\s*(?:async\s+)?(?:def|class)\s+(" + escaped + r")\b",
        r"(?:^|\n)\s*(" + escaped + r")\s*=",
    ):
        match = re.search(pattern, text)
        if match:
            return match.start(1)
    return None


def candidate_files(project_dir, file):
    if file:
        return [os.path.join(project_dir, file)]

    found = []
    for root in SOURCE_ROOTS:
        base = os.path.join(project_dir, root)
        if not os.path.isdir(base):
            continue
        for dirpath, _dirs, names in os.walk(base):
            for name in sorted(names):
                if name.endswith(".py"):
                    found.append(os.path.join(dirpath, name))
    return found


def changed_paths(changes, project_dir):
    paths = set()
    for change in getattr(changes, "changes", []):
        resource = getattr(change, "resource", None)
        if resource is not None:
            paths.add(os.path.relpath(resource.real_path, project_dir))
    return sorted(paths)


def main():
    request = json.loads(sys.stdin.read() or "{}")
    name_from = request.get("from") or ""
    name_to = request.get("to") or ""
    file = request.get("file") or None
    apply = bool(request.get("apply"))

    if not name_from or not name_to:
        fail("from and to are required")

    try:
        from rope.base.project import Project
        from rope.refactor.rename import Rename
    except ImportError as error:
        fail("rope is not available: %s (run: plugin.sh provision)" % error)

    target = None
    for path in candidate_files(PROJECT_DIR, file):
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        except OSError:
            continue
        if definition_offset(text, name_from) is not None:
            target = path
            break

    if target is None:
        fail("no definition of '%s' found" % name_from)

    # ropefolder=None: rope otherwise writes a .ropeproject/ directory into the
    # caller's project. That pollutes the tree, and since the driver runs in a
    # container the new paths would be root-owned on the host.
    project = Project(PROJECT_DIR, ropefolder=None)
    try:
        resource = project.get_file(os.path.relpath(target, PROJECT_DIR))
        with open(target, encoding="utf-8", errors="replace") as handle:
            offset = definition_offset(handle.read(), name_from)

        changes = Rename(project, resource, offset).get_changes(name_to)
        files = changed_paths(changes, PROJECT_DIR)
        if not files:
            files = [os.path.relpath(target, PROJECT_DIR)]

        if apply:
            changes.do()

        result = {
            "ok": True,
            "engine": "rope",
            "applied": apply,
            "summary": "%s %s -> %s in %d file(s)"
            % ("Renamed" if apply else "Would rename", name_from, name_to, len(files)),
            "files": files,
            "warnings": [],
        }
        sys.stdout.write(json.dumps(result) + "\n")
        return 0
    finally:
        project.close()


if __name__ == "__main__":
    sys.exit(main())
