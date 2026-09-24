#!/usr/bin/env python3
"""Tokenize-based occurrence scans for the refactor tool's Python plugin.

Reads {project, from, kind} as JSON on stdin and writes {"hits": [{file, line,
text}]} on stdout. `kind` selects what counts:

    strings (default) — the text inside a string literal: the dynamic references
                        a rename cannot reach (a dict key, a getattr() argument,
                        an f-string label). Reported for the caller, never
                        rewritten.
    names             — identifier occurrences of the name. Used after an apply
                        to confirm nothing was left behind.

Python's own tokenizer classifies the source, so a name in a comment is never
mistaken for a reference, and a name held in a string is never mistaken for an
identifier. Nothing here writes: the scan only reports.
"""

import io
import json
import os
import re
import sys
import tokenize

PROJECT_DIR = os.environ.get("REFACTOR_PROJECT_DIR", "/app")
_PREFIX_RE = re.compile(r"^[rRbBuUfF]{0,2}")


def _token_types(kind):
    """The token types `kind` scans, across Python versions.

    Python 3.12 splits an f-string into FSTRING_START/MIDDLE/END; earlier
    versions emit it as one STRING. Both carry the literal text being scanned.
    """
    if kind == "names":
        return {tokenize.NAME}

    types = {tokenize.STRING}
    middle = getattr(tokenize, "FSTRING_MIDDLE", None)
    if middle is not None:
        types.add(middle)
    return types


def _matches(token_string, name, kind):
    # A string hit is a substring (the name nested in a larger literal); a name
    # hit is the whole identifier, so `greeter` never counts for `greet`.
    return token_string == name if kind == "names" else name in token_string


def _literal_text(token_string):
    """The content of a string literal: prefix and surrounding quotes removed."""
    text = _PREFIX_RE.sub("", token_string)
    for quote in ('"""', "'''", '"', "'"):
        if text.startswith(quote) and text.endswith(quote) and len(text) >= 2 * len(quote):
            return text[len(quote) : -len(quote)].strip()
    return text.strip()


def _source_roots(project):
    # `app/` (Laravel) and `src/` (library) are alternatives; walking `.` too
    # would descend into whichever exists a second time and double every hit.
    roots = [name for name in ("src", "app") if os.path.isdir(os.path.join(project, name))]
    return roots or ["."]


def _hits_in(path, project, name, kind):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            source = handle.read()
    except OSError:
        return []

    hits = []
    token_types = _token_types(kind)
    try:
        for token in tokenize.generate_tokens(io.StringIO(source).readline):
            if token.type not in token_types or not _matches(token.string, name, kind):
                continue
            hits.append(
                {
                    "file": os.path.relpath(path, project),
                    "line": token.start[0],
                    "text": _literal_text(token.string) if kind != "names" else token.string,
                }
            )
    except (tokenize.TokenError, IndentationError, SyntaxError):
        # A file rope can still refactor may not tokenize (py2 syntax, a stray
        # fragment). Report what parsed rather than failing the whole scan.
        return hits
    return hits


def find_occurrences(project, name, kind):
    if not project or not os.path.isdir(project) or not name:
        return []

    hits = []
    for root_name in _source_roots(project):
        root = os.path.join(project, root_name)
        for dirpath, _dirs, files in os.walk(root):
            for filename in sorted(files):
                if filename.endswith(".py"):
                    hits.extend(_hits_in(os.path.join(dirpath, filename), project, name, kind))
    return hits


def main():
    request = json.loads(sys.stdin.read() or "{}")
    project = request.get("project") or PROJECT_DIR
    name = request.get("from") or ""
    kind = request.get("kind") or "strings"
    print(json.dumps({"hits": find_occurrences(project, name, kind)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
