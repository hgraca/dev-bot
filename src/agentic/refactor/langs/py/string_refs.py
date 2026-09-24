#!/usr/bin/env python3
"""String-reference scan for the refactor tool's Python plugin.

Reads {project, from} as JSON on stdin and writes {"hits": [{file, line, text}]}
on stdout, the same shape the PHP plugin's `string-refs` uses.

Every rename is blind to a name held in a string — a dict key, a getattr()
argument, an f-string label. Those are exactly the dynamic references rope's
symbol table cannot see, so they are surfaced for the caller to judge rather
than silently left behind. Nothing here writes: the scan only reports.

Python's own tokenizer classifies the source, so a name in a comment or in code
is never mistaken for a string reference.
"""

import io
import json
import os
import re
import sys
import tokenize

PROJECT_DIR = os.environ.get("REFACTOR_PROJECT_DIR", "/app")
_PREFIX_RE = re.compile(r"^[rRbBuUfF]{0,2}")


def _string_token_types():
    """Token types carrying literal string text, across Python versions.

    Python 3.12 splits an f-string into FSTRING_START/MIDDLE/END; earlier
    versions emit it as one STRING. Both carry the literal text being scanned.
    """
    types = {tokenize.STRING}
    middle = getattr(tokenize, "FSTRING_MIDDLE", None)
    if middle is not None:
        types.add(middle)
    return types


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


def _hits_in(path, name):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            source = handle.read()
    except OSError:
        return []

    hits = []
    string_types = _string_token_types()
    try:
        for token in tokenize.generate_tokens(io.StringIO(source).readline):
            if token.type not in string_types or name not in token.string:
                continue
            hits.append(
                {
                    "file": os.path.relpath(path, PROJECT_DIR),
                    "line": token.start[0],
                    "text": _literal_text(token.string),
                }
            )
    except (tokenize.TokenError, IndentationError, SyntaxError):
        # A file rope can still refactor may not tokenize (py2 syntax, a stray
        # fragment). Report what parsed rather than failing the whole scan.
        return hits
    return hits


def find_string_references(project, name):
    if not project or not os.path.isdir(project) or not name:
        return []

    hits = []
    for root_name in _source_roots(project):
        root = os.path.join(project, root_name)
        for dirpath, _dirs, files in os.walk(root):
            for filename in sorted(files):
                if filename.endswith(".py"):
                    hits.extend(_hits_in(os.path.join(dirpath, filename), name))
    return hits


def main():
    request = json.loads(sys.stdin.read() or "{}")
    project = request.get("project") or PROJECT_DIR
    name = request.get("from") or ""
    print(json.dumps({"hits": find_string_references(project, name)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
