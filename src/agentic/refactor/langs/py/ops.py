#!/usr/bin/env python3
"""rope driver for the refactor tool's Python plugin.

Reads a refactor request as JSON on stdin and writes a response as JSON on
stdout, in the same shape the PHP and TypeScript plugins use:
    {ok, engine, applied, summary, files, warnings}

rope is the Python refactoring library. Each op builds a project-wide change set
— from the symbol table for a rename, from a line range for an extract — and
applies it only when the request asks. Unlike the TypeScript compiler rope is
not fully type-aware, so a rename's reference set is symbol-table based: good
for ordinary code, blind to dynamic construction.
"""

import ast
import json
import os
import re
import sys

PROJECT_DIR = os.environ.get("REFACTOR_PROJECT_DIR", "/app")


def fail(message):
    sys.stderr.write("ERROR: " + message + "\n")
    sys.exit(1)


# ── targeting ──────────────────────────────────────────────────────────────────


def definition_offsets(text, name):
    """Offset of every definition of `name` in `text`.

    `def`/`class` may be indented (methods); a bare assignment must not be, or a
    function-local `name = ...` would count as a module-level definition.
    """
    escaped = re.escape(name)
    offsets = []
    for pattern in (
        r"(?:^|\n)\s*(?:async\s+)?(?:def|class)\s*(" + escaped + r")\b",
        r"(?:^|\n)(" + escaped + r")\s*=",
    ):
        offsets.extend(match.start(1) for match in re.finditer(pattern, text))
    return sorted(set(offsets))


def candidate_files(project_dir, file):
    if file:
        return [os.path.join(project_dir, file)]

    # `app/` (Laravel) and `src/` (library) are alternatives; walking `.` as
    # well would find every definition under them a second time.
    roots = [
        name for name in ("src", "app") if os.path.isdir(os.path.join(project_dir, name))
    ]
    found = []
    for root in roots or ["."]:
        base = os.path.join(project_dir, root)
        for dirpath, _dirs, names in os.walk(base):
            for name in sorted(names):
                if name.endswith(".py"):
                    found.append(os.path.join(dirpath, name))
    return found


def read_source(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def _target_file(request):
    file = request.get("file") or None
    if not file:
        fail("op '%s' requires --file" % (request.get("op") or ""))
    return os.path.join(PROJECT_DIR, file)


def _position(value):
    """A 'LINE' or 'LINE:COL' selection point (1-based), as (line, col|None)."""
    parts = str(value).split(":", 1)
    try:
        line = int(parts[0])
    except (TypeError, ValueError):
        fail("a selection point must be LINE or LINE:COL, got %r" % value)
    col = None
    if len(parts) == 2:
        try:
            col = int(parts[1])
        except (TypeError, ValueError):
            fail("a selection column must be a number, got %r" % value)
        if col < 1:
            fail("a selection column is 1-based, got %d" % col)
    return line, col


def selection_offsets(text, start, end):
    """Character offsets for a LINE[:COL] selection.

    `end` without a column reads to the end of its line (newline excluded),
    which is what a whole-statement extract expects.
    """
    lines = text.splitlines(keepends=True)
    line_starts = [0]
    for line in lines:
        line_starts.append(line_starts[-1] + len(line))

    start_line, start_col = _position(start)
    end_line, end_col = _position(end)
    if not (1 <= start_line <= end_line <= len(lines)):
        fail(
            "line range %d-%d is outside the file (%d lines)"
            % (start_line, end_line, len(lines))
        )

    offset = line_starts[start_line - 1] + (start_col - 1 if start_col else 0)
    if end_col is None:
        end_offset = line_starts[end_line - 1] + len(lines[end_line - 1].rstrip("\r\n"))
    else:
        # End columns are inclusive, so the exclusive offset is the column itself.
        end_offset = line_starts[end_line - 1] + end_col
    if end_offset <= offset:
        fail("empty selection: end must come after start")
    return offset, end_offset


# ── ops ────────────────────────────────────────────────────────────────────────


def _definitions(request, name):
    """The single (path, offset, line) definition of `name`, or fail().

    Several matches are ambiguous — editing an arbitrary one silently would
    touch the wrong symbol, so the caller is told to pick with --file.
    """
    candidates = []
    for path in candidate_files(PROJECT_DIR, request.get("file") or None):
        try:
            text = read_source(path)
        except OSError:
            continue
        for offset in definition_offsets(text, name):
            candidates.append((path, offset, text.count("\n", 0, offset) + 1))

    if not candidates:
        fail("no definition of '%s' found" % name)
    if len(candidates) > 1:
        listing = "\n".join(
            "  %s:%d" % (os.path.relpath(path, PROJECT_DIR), line)
            for path, _offset, line in candidates
        )
        fail(
            "'%s' is defined in %d places — pass --file to pick one:\n%s"
            % (name, len(candidates), listing)
        )
    return candidates[0]


def _rename(project, request, Rename):
    name_from = request.get("from") or ""
    name_to = request.get("to") or ""
    if not name_from or not name_to:
        fail("from and to are required")

    target, offset, _line = _definitions(request, name_from)
    resource = project.get_file(os.path.relpath(target, PROJECT_DIR))
    return Rename(project, resource, offset).get_changes(name_to)


def _inline(project, request, create_inline):
    name = request.get("from") or ""
    if not name:
        fail("from is required")

    target, offset, _line = _definitions(request, name)
    resource = project.get_file(os.path.relpath(target, PROJECT_DIR))
    return create_inline(project, resource, offset).get_changes()


def _self_attribute_offsets(text, name):
    """(offset, owning-class line) for every `self.<name>` access in `text`."""
    line_starts = [0]
    for line in text.splitlines(keepends=True):
        line_starts.append(line_starts[-1] + len(line))

    tree = ast.parse(text)
    classes = [node for node in ast.walk(tree) if isinstance(node, ast.ClassDef)]
    found = []
    for node in ast.walk(tree):
        if not (isinstance(node, ast.Attribute) and node.attr == name):
            continue
        if not (isinstance(node.value, ast.Name) and node.value.id == "self"):
            continue
        # rope wants the offset of the attribute word itself, not of `self`.
        offset = line_starts[node.end_lineno - 1] + node.end_col_offset - len(name)
        owner = next(
            (cls.lineno for cls in classes if cls.lineno <= node.lineno <= cls.end_lineno),
            None,
        )
        found.append((offset, owner))
    return found


def _encapsulate(project, request, EncapsulateField):
    from rope.base.exceptions import RefactoringError

    name = request.get("from") or ""
    if not name:
        fail("from is required")

    path = _target_file(request)
    try:
        text = read_source(path)
    except OSError as error:
        fail("cannot read %s: %s" % (request.get("file"), error))

    # Located by its `self.<name>` access, not the bare word: a parameter, local
    # or comment that shares the name is then never mistaken for the attribute.
    try:
        found = _self_attribute_offsets(text, name)
    except SyntaxError as error:
        fail("cannot parse %s: %s" % (request.get("file"), error))

    if not found:
        fail("no 'self.%s' attribute found in %s" % (name, request.get("file")))
    owners = {owner for _offset, owner in found if owner is not None}
    if len(owners) > 1:
        fail(
            "'%s' is an attribute of %d classes in %s — narrow it to one"
            % (name, len(owners), request.get("file"))
        )

    resource = project.get_file(os.path.relpath(path, PROJECT_DIR))
    try:
        return EncapsulateField(project, resource, found[0][0]).get_changes()
    except RefactoringError as error:
        # rope refuses an offset that is not a class attribute; surface it as an
        # ERROR: line rather than a traceback.
        fail(str(error))


def _parameter_index(request):
    """The 0-based parameter position rope wants, from the 1-based --index."""
    try:
        index = int(request.get("index") or 0)
    except (TypeError, ValueError):
        fail("--index must be a number")
    if index < 1:
        fail("--index is 1-based")
    return index - 1


def _signature_target(project, request):
    name = request.get("from") or ""
    if not name:
        fail("from is required")
    target, offset, _line = _definitions(request, name)
    return project.get_file(os.path.relpath(target, PROJECT_DIR)), offset


def _add_argument(project, request, ChangeSignature, ArgumentAdder):
    param = request.get("to") or ""
    if not param:
        fail("to (the parameter name) is required")
    resource, offset = _signature_target(project, request)
    changer = ArgumentAdder(
        _parameter_index(request), param, request.get("default") or None
    )
    return ChangeSignature(project, resource, offset).get_changes([changer])


def _remove_argument(project, request, ChangeSignature, ArgumentRemover):
    resource, offset = _signature_target(project, request)
    changer = ArgumentRemover(_parameter_index(request))
    return ChangeSignature(project, resource, offset).get_changes([changer])


def _move_module(project, request, MoveModule):
    source = request.get("file") or ""
    dest = request.get("to") or ""
    if not source or not dest:
        fail("file and to (the destination folder) are required")

    source_resource = project.get_file(source)
    if not source_resource.exists():
        fail("no such file: %s" % source)
    dest_resource = project.get_folder(dest)
    # rope's get_folder() returns a Folder that may not exist, and is_folder() is
    # always True — exists() is the real test, or move deletes the module.
    if not dest_resource.exists() or not dest_resource.is_folder():
        fail("no such destination folder: %s" % dest)

    return MoveModule(project, source_resource).get_changes(dest_resource)


def _remove_unused_imports(project, request):
    from rope.base.change import ChangeContents, ChangeSet
    from rope.refactor.importutils import ImportTools

    path = _target_file(request)
    resource = project.get_file(os.path.relpath(path, PROJECT_DIR))
    if not resource.exists():
        fail("no such file: %s" % request.get("file"))

    # Only `unused`: sort/duplicates/selfs stay off so the change is exactly the
    # removal of names rope can prove unreferenced in this module.
    new_source = ImportTools(project).organize_imports(
        project.get_pymodule(resource),
        unused=True,
        duplicates=False,
        selfs=False,
        sort=False,
    )

    changes = ChangeSet("Remove unused imports from %s" % request.get("file"))
    if new_source != resource.read():
        changes.add_change(ChangeContents(resource, new_source))
    return changes


def _privatise(project, request, Rename):
    name = request.get("from") or ""
    if not name:
        fail("from is required")
    if name.startswith("_"):
        fail("'%s' is already private" % name)

    target, offset, _line = _definitions(request, name)
    resource = project.get_file(os.path.relpath(target, PROJECT_DIR))
    changes = Rename(project, resource, offset).get_changes("_" + name)

    # The rename's own change set is the project-wide reference set: if it reaches
    # another file, the name is used outside its module and must stay public.
    module = os.path.relpath(target, PROJECT_DIR)
    outside = sorted(
        path
        for path in changed_paths(changes, PROJECT_DIR)
        if path != module
    )
    if outside:
        fail(
            "'%s' is used outside its module — cannot privatise:\n%s"
            % (name, "\n".join("  " + path for path in outside))
        )
    return changes


def _extract(project, request, extractor):
    name_to = request.get("to") or ""
    if not name_to:
        fail("to is required")

    path = _target_file(request)
    try:
        text = read_source(path)
    except OSError as error:
        fail("cannot read %s: %s" % (request.get("file"), error))

    start, end = selection_offsets(text, request.get("start") or 0, request.get("end") or 0)
    resource = project.get_file(os.path.relpath(path, PROJECT_DIR))
    return extractor(project, resource, start, end).get_changes(name_to)


def build_changes(project, request):
    """The ChangeSet the request describes; fails on an unknown op."""
    op = request.get("op") or ""
    if op == "rename-symbol":
        from rope.refactor.rename import Rename

        return _rename(project, request, Rename)
    if op == "extract-method":
        from rope.refactor.extract import ExtractMethod

        return _extract(project, request, ExtractMethod)
    if op == "extract-variable":
        from rope.refactor.extract import ExtractVariable

        return _extract(project, request, ExtractVariable)
    if op == "inline":
        from rope.refactor.inline import create_inline

        return _inline(project, request, create_inline)
    if op == "encapsulate-field":
        from rope.refactor.encapsulate_field import EncapsulateField

        return _encapsulate(project, request, EncapsulateField)
    if op == "add-argument":
        from rope.refactor.change_signature import ArgumentAdder, ChangeSignature

        return _add_argument(project, request, ChangeSignature, ArgumentAdder)
    if op == "remove-argument":
        from rope.refactor.change_signature import ArgumentRemover, ChangeSignature

        return _remove_argument(project, request, ChangeSignature, ArgumentRemover)
    if op == "move-module":
        from rope.refactor.move import MoveModule

        return _move_module(project, request, MoveModule)
    if op == "remove-unused-imports":
        return _remove_unused_imports(project, request)
    if op == "privatise":
        from rope.refactor.rename import Rename

        return _privatise(project, request, Rename)
    fail("py plugin: unsupported op: %s" % op)


# ── reporting ──────────────────────────────────────────────────────────────────


def changed_paths(changes, project_dir):
    paths = set()
    for change in getattr(changes, "changes", []):
        resource = getattr(change, "resource", None)
        if resource is not None:
            paths.add(os.path.relpath(resource.real_path, project_dir))
    return sorted(paths)


def summarize(op, request, files, apply):
    old = request.get("from") or ""
    new = request.get("to") or ""
    if op == "rename-symbol":
        verb = "Renamed" if apply else "Would rename"
        return "%s %s -> %s in %d file(s)" % (verb, old, new, len(files))
    if op == "inline":
        verb = "Inlined" if apply else "Would inline"
        return "%s %s in %d file(s)" % (verb, old, len(files))
    if op == "encapsulate-field":
        verb = "Encapsulated" if apply else "Would encapsulate"
        return "%s %s in %d file(s)" % (verb, old, len(files))
    if op in ("add-argument", "remove-argument"):
        verb = "Changed" if apply else "Would change"
        return "%s the signature of %s in %d file(s)" % (verb, old, len(files))
    if op == "move-module":
        verb = "Moved" if apply else "Would move"
        return "%s %s to %s in %d file(s)" % (
            verb,
            request.get("file") or "",
            new,
            len(files),
        )
    if op == "remove-unused-imports":
        verb = "Removed unused imports" if apply else "Would remove unused imports"
        return "%s in %d file(s)" % (verb, len(files))
    if op == "privatise":
        verb = "Privatised" if apply else "Would privatise"
        return "%s %s in %d file(s)" % (verb, old, len(files))
    verb = "Extracted" if apply else "Would extract"
    return "%s %s in %d file(s)" % (verb, new, len(files))


def main():
    request = json.loads(sys.stdin.read() or "{}")
    op = request.get("op") or ""
    apply = bool(request.get("apply"))

    from rope.base.project import Project

    # ropefolder=None: rope otherwise writes a .ropeproject/ directory into the
    # caller's project. That pollutes the tree, and since the driver runs in a
    # container the new paths would be root-owned on the host.
    project = Project(PROJECT_DIR, ropefolder=None)
    try:
        changes = build_changes(project, request)
        files = changed_paths(changes, PROJECT_DIR)
        # A rename that changed nothing still names its target; a cleanup that
        # found nothing must not claim a file.
        if not files and op == "rename-symbol" and request.get("file"):
            files = [request["file"]]
        # A move must report where the module landed, not the path it left.
        if op == "move-module":
            source = request.get("file") or ""
            moved = os.path.join(request.get("to") or "", os.path.basename(source))
            files = sorted([path for path in files if path != source] + [moved])

        if apply:
            changes.do()

        result = {
            "ok": True,
            "engine": "rope",
            "applied": apply,
            "summary": summarize(op, request, files, apply),
            "files": files,
            "warnings": [],
        }
        sys.stdout.write(json.dumps(result) + "\n")
        return 0
    finally:
        project.close()


if __name__ == "__main__":
    sys.exit(main())
