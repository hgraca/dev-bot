#!/usr/bin/env python3
"""Set module enablement flags in a JSONC config, preserving comments.

Usage:
  set_module_flags.py <config> [--if-absent] <name=false|true> [...]

Each pair writes the value under the top-level "modules" map:

  - an existing "<name>" property is rewritten in place, keeping whatever else
    is on the line (a trailing comment included);
  - a missing "<name>" is added to the map;
  - a missing "modules" map is created as the last top-level key.

The JSONC scanner is the reconciler's (`reconcile_global_config._object_props`),
not a second one: the same file shapes both tools accept keeps them from
drifting apart.

`--if-absent` writes only the keys the config does not name: a value the machine
already carries — its own choice — is reported PRESENT and left alone. The
migrations use it, so a release default never overrides an explicit setting.

The candidate is written to a temp file, parsed back, and checked to carry every
requested value before it replaces the config — so a config this cannot rewrite
safely is left exactly as it was, never half-edited.

Exit codes:
  0 — SET/UNCHANGED printed per key
  1 — error: bad usage, unreadable/unparseable file, or a rewrite that does not
      parse or does not hold the requested values
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from read_jsonc import load_jsonc  # noqa: E402
from reconcile_global_config import (  # noqa: E402
    _object_props,
    _skip_ws_comments,
)


def _indent_of(text, pos):
    """The indentation of the line containing pos."""
    line_start = text.rfind("\n", 0, pos) + 1
    prefix = text[line_start:pos]
    return prefix[: len(prefix) - len(prefix.lstrip())]


def _insert_member(text, props, obj_open, obj_close, member, parent_indent):
    """Add a member as the last property of the object spanning the braces.

    `props` are that object's members from the reconciler's scanner, so the
    separator lands after the last VALUE — never after a trailing `// comment`,
    where it would comment the new member out and the rewrite would not parse.
    """
    indent = parent_indent + "  "
    if not props:
        # `{}` or `{ }`: open it up, closing where the key's indentation puts it.
        return (
            text[: obj_open + 1]
            + "\n"
            + indent
            + member
            + "\n"
            + parent_indent
            + text[obj_close:]
        )

    last = props[-1]
    between = text[last["value_end"] : last["content_end"]]
    has_comma = between.lstrip().startswith(",")
    if has_comma:
        return text[: last["content_end"]] + "\n" + indent + member + text[last["content_end"] :]
    if last["comment"]:
        # `value // c` -> `value, // c` then the new member on its own line.
        return (
            text[: last["value_end"]]
            + ","
            + text[last["value_end"] : last["content_end"]]
            + "\n"
            + indent
            + member
            + text[last["content_end"] :]
        )
    return text[: last["content_end"]] + ",\n" + indent + member + text[last["content_end"] :]


def _set_flag(text, name, value):
    """Set modules.<name> = value. Returns (text, changed)."""
    literal = "true" if value else "false"
    root = _skip_ws_comments(text, 0)
    if root >= len(text) or text[root] != "{":
        raise ValueError("config is not a JSON object")

    root_indent = _indent_of(text, root)
    root_props, root_close = _object_props(text, root + 1)
    modules = next((p for p in root_props if p["key"] == "modules"), None)

    if modules is None:
        member = '"modules": {\n%s    "%s": %s\n%s}' % (
            root_indent,
            name,
            literal,
            root_indent + "  ",
        )
        return (
            _insert_member(
                text, root_props, root, root_close, member, root_indent
            ),
            True,
        )

    if text[modules["value_start"]] != "{":
        raise ValueError('"modules" is not an object')

    members, modules_close = _object_props(text, modules["value_start"] + 1)
    current = next((p for p in members if p["key"] == name), None)
    if current is not None:
        if text[current["value_start"] : current["value_end"]] == literal:
            return text, False
        return (
            text[: current["value_start"]]
            + literal
            + text[current["value_end"] :],
            True,
        )

    indent = _indent_of(text, modules["value_start"])
    return (
        _insert_member(
            text,
            members,
            modules["value_start"],
            modules_close,
            '"%s": %s' % (name, literal),
            indent,
        ),
        True,
    )


def _existing_flag(text, name):
    """The module's current raw value, or None when the config does not name it.

    "Present" means the key exists at all — a value that is not a boolean is
    still the machine's own setting, and a release default must not replace it.
    """
    root = _skip_ws_comments(text, 0)
    if root >= len(text) or text[root] != "{":
        raise ValueError("config is not a JSON object")
    root_props, _close = _object_props(text, root + 1)
    modules = next((p for p in root_props if p["key"] == "modules"), None)
    if modules is None or text[modules["value_start"]] != "{":
        return None
    members, _mclose = _object_props(text, modules["value_start"] + 1)
    current = next((p for p in members if p["key"] == name), None)
    if current is None:
        return None
    return text[current["value_start"] : current["value_end"]].strip()


def _parse_flags(argv):
    flags = []
    for arg in argv:
        if arg == "--if-absent":
            continue
        name, sep, raw = arg.partition("=")
        if not sep or not name or raw not in ("true", "false"):
            raise ValueError("expected <name>=true|false, got %r" % arg)
        flags.append((name, raw == "true"))
    return flags


def main():
    # The option may come before the config, as the migration calls it.
    if_absent = "--if-absent" in sys.argv[1:]
    args = [arg for arg in sys.argv[1:] if arg != "--if-absent"]
    if len(args) < 2:
        print(
            "Usage: %s [--if-absent] <config> <name=false|true> ..." % sys.argv[0],
            file=sys.stderr,
        )
        return 1

    # Write through a symlinked config: replacing the link would leave the real
    # file stale, and a dotfiles-tracked config is exactly the user who symlinks.
    path = os.path.realpath(args[0])
    try:
        flags = _parse_flags(args[1:])
    except ValueError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 1

    try:
        with open(path, encoding="utf-8-sig") as fh:
            text = fh.read()
    except OSError as exc:
        print("ERROR: cannot read %s: %s" % (path, exc), file=sys.stderr)
        return 1

    changed = []
    present = []
    try:
        for name, value in flags:
            if if_absent:
                current = _existing_flag(text, name)
                if current is not None:
                    present.append((name, current))
                    continue
            text, did = _set_flag(text, name, value)
            if did:
                changed.append(name)
    except ValueError as exc:
        print("ERROR: %s: %s" % (path, exc), file=sys.stderr)
        return 1

    if not changed:
        for name, value in flags:
            existing = dict(present).get(name)
            if existing is not None:
                print("PRESENT %s=%s" % (name, existing))
            else:
                print("UNCHANGED %s=%s" % (name, "true" if value else "false"))
        return 0

    # Write the candidate, prove it parses and carries every requested value,
    # and only then let it replace the config — never a half-edited file.
    try:
        mode = os.stat(path).st_mode & 0o7777
        fd, tmp = tempfile.mkstemp(
            dir=os.path.dirname(os.path.abspath(path)), prefix=".devbot-modules-"
        )
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.chmod(tmp, mode)
    except OSError as exc:
        print("ERROR: cannot write beside %s: %s" % (path, exc), file=sys.stderr)
        return 1

    try:
        parsed = load_jsonc(tmp)
        modules = parsed.get("modules")
        if not isinstance(modules, dict):
            raise ValueError("rewritten config has no modules map")
        kept = {name for name, _value in present}
        for name, value in flags:
            # A PRESENT key keeps the machine's value on purpose.
            if name in kept:
                continue
            if modules.get(name) is not value:
                raise ValueError(
                    "%s is %r after the rewrite, expected %r"
                    % (name, modules.get(name), "true" if value else "false")
                )
    except (OSError, ValueError) as exc:
        os.unlink(tmp)
        print("ERROR: %s: %s" % (path, exc), file=sys.stderr)
        return 1

    try:
        os.replace(tmp, path)
    except OSError as exc:
        os.unlink(tmp)
        print("ERROR: cannot replace %s: %s" % (path, exc), file=sys.stderr)
        return 1

    for name, value in flags:
        if name in changed:
            state = "SET"
        elif dict(present).get(name) is not None:
            state = "PRESENT"
        else:
            state = "UNCHANGED"
        print("%s %s=%s" % (state, name, "true" if value else "false"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
