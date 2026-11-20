#!/usr/bin/env python3
"""Rewrite `kubectl.clusters` between the array and keyed-object forms.

The array form gives one `name` to four different jobs (the AWS EKS cluster, the
kubeconfig cluster object, the `devbot-<name>` user and the `kctl-<name>` server
key), so an AWS cluster name and the name a human sees cannot differ. The object
form keys the catalogue by the AWS cluster name and keeps `name` as the visible
one.

The global config is user-owned and carries comments, so this rewrites the text
of the `clusters` value only and leaves everything around it byte for byte.
"""

import json
import os
import sys
import tempfile

from read_jsonc import load_jsonc

USAGE = "usage: migrate_kubectl_clusters.py [--down] <config> [<config>...]"


# ── JSONC scanning ────────────────────────────────────────────────────────────


def _skip_trivia(text, index):
    """Advance past whitespace and comments."""
    while index < len(text):
        if text[index] in " \t\r\n":
            index += 1
        elif text.startswith("//", index):
            newline = text.find("\n", index)
            index = len(text) if newline == -1 else newline + 1
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            index = len(text) if end == -1 else end + 2
        else:
            break
    return index


def _string_end(text, index):
    index += 1
    while index < len(text):
        if text[index] == "\\":
            index += 2
        elif text[index] == '"':
            return index + 1
        else:
            index += 1
    return index


def _value_end(text, index):
    """Index just past the value that starts at `index`."""
    if index >= len(text):
        return index
    if text[index] == '"':
        return _string_end(text, index)
    if text[index] in "[{":
        depth = 0
        while index < len(text):
            char = text[index]
            if char == '"':
                index = _string_end(text, index)
                continue
            if text.startswith("//", index) or text.startswith("/*", index):
                index = _skip_trivia(text, index)
                continue
            if char in "[{":
                depth += 1
            elif char in "]}":
                depth -= 1
                if depth == 0:
                    return index + 1
            index += 1
        return index
    while index < len(text) and text[index] not in ",}]":
        index += 1
    return index


def _members(text, open_index):
    """Yield (key, key_start, value_start, value_end) for an object's members."""
    index = _skip_trivia(text, open_index + 1)
    while index < len(text) and text[index] not in "}":
        if text[index] != '"':
            raise ValueError("expected a key at offset %d" % index)
        key_start = index
        key_end = _string_end(text, index)
        key = json.loads(text[key_start:key_end])
        colon = _skip_trivia(text, key_end)
        if colon >= len(text) or text[colon] != ":":
            raise ValueError("expected ':' at offset %d" % colon)
        value_start = _skip_trivia(text, colon + 1)
        value_end = _value_end(text, value_start)
        yield key, key_start, value_start, value_end
        index = _skip_trivia(text, value_end)
        if index < len(text) and text[index] == ",":
            index = _skip_trivia(text, index + 1)


def _first_object(text):
    index = _skip_trivia(text, 0)
    return index if index < len(text) and text[index] == "{" else None


def _member(text, open_index, name):
    try:
        for key, key_start, value_start, value_end in _members(text, open_index):
            if key == name:
                return key_start, value_start, value_end
    except ValueError:
        return None
    return None


def _indent_of(text, index):
    start = text.rfind("\n", 0, index) + 1
    return len(text[start:index]) - len(text[start:index].lstrip(" "))


# ── Rendering ─────────────────────────────────────────────────────────────────


def _render_object(entries, indent):
    if not entries:
        return "{}"
    pad = " " * (indent + 2)
    lines = []
    for key, entry in entries:
        if not entry:
            lines.append("%s%s: {}" % (pad, json.dumps(key)))
            continue
        body = ",\n".join(
            "%s  %s: %s" % (pad, json.dumps(name), json.dumps(value))
            for name, value in entry.items()
        )
        lines.append("%s%s: {\n%s\n%s}" % (pad, json.dumps(key), body, pad))
    return "{\n" + ",\n".join(lines) + "\n" + " " * indent + "}"


def _render_array(entries, indent):
    if not entries:
        return "[]"
    pad = " " * (indent + 2)
    body = ",\n".join(pad + json.dumps(entry) for entry in entries)
    return "[\n" + body + "\n" + " " * indent + "]"


# ── The two directions ────────────────────────────────────────────────────────


def _to_object(clusters):
    entries = []
    seen = set()
    for entry in clusters:
        if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
            raise ValueError("every cluster entry needs a string 'name'")
        key = entry["name"]
        if key in seen:
            raise ValueError("two cluster entries are both named %r" % key)
        seen.add(key)
        # The key is the old name, so keeping the field would be a second copy of
        # the same string. `context` and `region` stay as they were.
        entries.append((key, {k: v for k, v in entry.items() if k != "name"}))
    return entries


def _to_array(clusters):
    entries = []
    for key, entry in clusters.items():
        if not isinstance(entry, dict):
            raise ValueError("cluster %r is not an object" % key)
        # The array form has no label field, and the AWS cluster name is what
        # keeps the cluster reachable, so the key wins and the label is dropped.
        merged = {"name": key}
        merged.update({k: v for k, v in entry.items() if k != "name"})
        entries.append(merged)
    return entries


def _write(path, text):
    # Unique name: a concurrent writer must not lose its candidate when this one
    # fails to validate. The config may hold credentials, so keep its mode.
    directory = os.path.dirname(os.path.abspath(path))
    fd, temp = tempfile.mkstemp(
        dir=directory, prefix=os.path.basename(path) + ".", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        load_jsonc(temp)  # never replace the config with something unparseable
        os.chmod(temp, os.stat(path).st_mode)
        os.replace(temp, path)
    except Exception:
        try:
            os.unlink(temp)
        except OSError:
            pass
        raise


def migrate(path, down=False):
    """Rewrite one config in place. Returns True when the file changed."""
    data = load_jsonc(path)
    kubectl = data.get("kubectl")
    if not isinstance(kubectl, dict):
        return False
    clusters = kubectl.get("clusters")
    if down:
        if not isinstance(clusters, dict):
            return False
    elif not isinstance(clusters, list):
        return False

    # utf-8-sig, like read_jsonc: a BOM would otherwise sit ahead of the opening
    # brace, _first_object would find nothing, and the file would report unchanged.
    with open(path, encoding="utf-8-sig") as handle:
        text = handle.read()
    root = _first_object(text)
    if root is None:
        return False
    kubectl_member = _member(text, root, "kubectl")
    if kubectl_member is None or text[kubectl_member[1]] != "{":
        return False
    clusters_member = _member(text, kubectl_member[1], "clusters")
    if clusters_member is None:
        return False

    key_start, value_start, value_end = clusters_member
    indent = _indent_of(text, key_start)
    if down:
        rendered = _render_array(_to_array(clusters), indent)
    else:
        rendered = _render_object(_to_object(clusters), indent)

    updated = text[:value_start] + rendered + text[value_end:]
    if updated == text:
        return False
    _write(path, updated)
    return True


def main(argv):
    if len(argv) < 2:
        print(USAGE, file=sys.stderr)
        return 2
    down = "--down" in argv[1:]
    paths = [arg for arg in argv[1:] if arg != "--down"]
    if not paths:
        print(USAGE, file=sys.stderr)
        return 2
    failed = 0
    for path in paths:
        try:
            changed = migrate(path, down=down)
        except (OSError, ValueError) as exc:
            print("ERROR: %s: %s" % (path, exc), file=sys.stderr)
            failed = 1
            continue
        print("%s %s" % ("migrated" if changed else "unchanged", path))
    return failed


if __name__ == "__main__":
    sys.exit(main(sys.argv))
