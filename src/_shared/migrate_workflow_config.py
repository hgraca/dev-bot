#!/usr/bin/env python3
"""Migrate the retired `worktrees` config key to `workflow`.

`devbot update` runs this after a release that replaced the boolean `worktrees`
key with the `workflow` name. The mapping preserves intent: `true` selected the
worktrees workflow, `false` opted out of it and now selects `trunk`.

Every project registered in the global config is migrated, plus the global
config itself. A file without the key is skipped, so the tool is idempotent.

The file is tokenized, not matched with a regex: comments and string contents
are skipped, and only the text span of the real top-level property is rewritten
— its key becomes `workflow` and its boolean becomes the workflow name, while
everything between them (including a comment before the value) and everything
else in the file is preserved. The result is parsed and checked before an
atomic swap, so a config is never left unparseable.

A file that carries both keys is left untouched and reported as an error — the
migration cannot tell which one the user meant.

Usage:
  migrate_workflow_config.py [--down] <global_config>

`--down` reverses the migration: the `workflow` name becomes the boolean
`worktrees` again (`worktrees` -> true, `trunk` -> false).

Output (stdout), one line per migrated file:
  MIGRATED: <path> worktrees=<true|false> -> workflow=<worktrees|trunk>

Exit codes:
  0 — migrated, or nothing to migrate
  1 — a config could not be read, or a file needed a manual fix
"""

import json
import os
import shutil
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from read_jsonc import load_jsonc  # noqa: E402

WORKFLOW_FOR = {"true": "worktrees", "false": "trunk"}
WORKTREES_FOR = {"worktrees": "true", "trunk": "false"}

_TRIVIA = " \t\r\n"


def _tokens(text):
    """Significant JSONC tokens as (kind, start, end, depth).

    Comments and the inside of strings never produce tokens, so a property name
    quoted in either cannot be mistaken for a real one. `depth` is the brace /
    bracket nesting at the token.
    """
    tokens = []
    i, n = 0, len(text)
    depth = 0
    while i < n:
        ch = text[i]
        if ch in _TRIVIA:
            i += 1
        elif text.startswith("//", i):
            newline = text.find("\n", i)
            i = n if newline == -1 else newline
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
        elif ch == '"':
            start = i
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                elif text[i] == '"':
                    i += 1
                    break
                else:
                    i += 1
            tokens.append(("string", start, i, depth))
        elif ch in "{[":
            tokens.append(("open", i, i + 1, depth))
            depth += 1
            i += 1
        elif ch in "}]":
            depth -= 1
            tokens.append(("close", i, i + 1, depth))
            i += 1
        elif ch == ":":
            tokens.append(("colon", i, i + 1, depth))
            i += 1
        elif ch == ",":
            tokens.append(("comma", i, i + 1, depth))
            i += 1
        elif text.startswith("true", i) or text.startswith("false", i):
            word = "true" if text.startswith("true", i) else "false"
            tokens.append(("boolean", i, i + len(word), depth))
            i += len(word)
        else:
            i += 1
    return tokens


def _top_level_keys(tokens, text, name):
    """(key_start, key_end, colon_index) for each top-level property named `name`."""
    found = []
    for index, (kind, start, end, depth) in enumerate(tokens):
        if kind != "string" or depth != 1 or index + 2 >= len(tokens):
            continue
        try:
            decoded = json.loads(text[start:end])
        except ValueError:
            continue
        if decoded != name:
            continue
        colon_kind, _, _, colon_depth = tokens[index + 1]
        if colon_kind != "colon" or colon_depth != 1:
            continue
        found.append((start, end, index))
    return found


def _boolean_value(tokens, key):
    """(start, end) of the boolean value that follows a key, or None."""
    kind, start, end, depth = tokens[key[2] + 2]
    if kind != "boolean" or depth != 1:
        return None
    return (start, end)


def _string_value(tokens, key):
    """(start, end) of the string value that follows a key, or None."""
    kind, start, end, depth = tokens[key[2] + 2]
    if kind != "string" or depth != 1:
        return None
    return (start, end)


def _migrate_file(path, errors):
    """Migrate one config file. Returns the report line, or None when skipped."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            original = handle.read()
    except OSError as exc:
        # An unreadable config may still hold `worktrees: false`; succeeding
        # here would let the reconciler replace it and silently flip the
        # project to the default workflow.
        errors.append(f"{path}: {exc} — fix its permissions and re-run")
        return None

    tokens = _tokens(original)
    retired = _top_level_keys(tokens, original, "worktrees")
    current = _top_level_keys(tokens, original, "workflow")

    if current and retired:
        errors.append(f'{path}: both "worktrees" and "workflow" are set — remove "worktrees" by hand')
        return None
    if current or not retired:
        return None
    if len(retired) > 1:
        errors.append(f'{path}: "worktrees" appears {len(retired)} times — migrate it by hand')
        return None

    key = retired[0]
    value_span = _boolean_value(tokens, key)
    if value_span is None:
        errors.append(f'{path}: "worktrees" is not a boolean — migrate it by hand')
        return None

    key_start, key_end, _ = key
    value_start, value_end = value_span
    value = original[value_start:value_end]
    expected = WORKFLOW_FOR[value]
    migrated = (
        original[:key_start]
        + '"workflow"'
        + original[key_end:value_start]
        + f'"{expected}"'
        + original[value_end:]
    )

    temp = f"{path}.devbot-migrate.tmp"
    try:
        with open(temp, "w", encoding="utf-8") as handle:
            handle.write(migrated)
        data = load_jsonc(temp)
        if not isinstance(data, dict):
            raise ValueError("not a JSON object")
        if "worktrees" in data:
            raise ValueError("the retired key survived the rewrite")
        if data.get("workflow") != expected:
            raise ValueError(f"expected workflow {expected!r}, got {data.get('workflow')!r}")
        # The temp file starts with the process umask; keep a protected
        # config's mode rather than broadening it during an update.
        shutil.copymode(path, temp)
        os.replace(temp, path)
    except Exception as exc:  # noqa: BLE001 - reported and rolled back below
        errors.append(f"{path}: {exc}")
        try:
            os.unlink(temp)
        except OSError:
            pass
        return None

    return f"MIGRATED: {path} worktrees={value} -> workflow={expected}"


def _migrate_file_down(path, errors):
    """Reverse one config file: `workflow` becomes the boolean `worktrees`."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            original = handle.read()
    except OSError as exc:
        errors.append(f"{path}: {exc} — fix its permissions and re-run")
        return None

    tokens = _tokens(original)
    retired = _top_level_keys(tokens, original, "worktrees")
    current = _top_level_keys(tokens, original, "workflow")

    if current and retired:
        errors.append(f'{path}: both "worktrees" and "workflow" are set — remove "workflow" by hand')
        return None
    if retired or not current:
        return None
    if len(current) > 1:
        errors.append(f'{path}: "workflow" appears {len(current)} times — migrate it by hand')
        return None

    key = current[0]
    value_span = _string_value(tokens, key)
    if value_span is None:
        errors.append(f'{path}: "workflow" is not a string — migrate it by hand')
        return None

    value_start, value_end = value_span
    try:
        name = json.loads(original[value_start:value_end])
    except ValueError:
        errors.append(f'{path}: "workflow" is not a valid string — migrate it by hand')
        return None
    boolean = WORKTREES_FOR.get(name)
    if boolean is None:
        errors.append(f"{path}: unrecognised workflow {name!r} — migrate it by hand")
        return None

    key_start, key_end, _ = key
    migrated = (
        original[:key_start]
        + '"worktrees"'
        + original[key_end:value_start]
        + boolean
        + original[value_end:]
    )

    temp = f"{path}.devbot-migrate.tmp"
    try:
        with open(temp, "w", encoding="utf-8") as handle:
            handle.write(migrated)
        data = load_jsonc(temp)
        if not isinstance(data, dict):
            raise ValueError("not a JSON object")
        if "workflow" in data:
            raise ValueError("the workflow key survived the rewrite")
        if data.get("worktrees") is not (boolean == "true"):
            raise ValueError(f"expected worktrees={boolean}, got {data.get('worktrees')!r}")
        shutil.copymode(path, temp)
        os.replace(temp, path)
    except Exception as exc:  # noqa: BLE001 - reported and rolled back below
        errors.append(f"{path}: {exc}")
        try:
            os.unlink(temp)
        except OSError:
            pass
        return None

    return f"MIGRATED: {path} workflow={name} -> worktrees={boolean}"


def main(argv):
    args = argv[1:]
    down = False
    if args and args[0] == "--down":
        down = True
        args = args[1:]
    if len(args) != 1:
        print("Usage: migrate_workflow_config.py [--down] <global_config>", file=sys.stderr)
        return 2

    migrate_file = _migrate_file_down if down else _migrate_file
    global_config = args[0]
    try:
        global_data = load_jsonc(global_config)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: cannot read {global_config}: {exc}", file=sys.stderr)
        return 1
    if not isinstance(global_data, dict):
        print(f"ERROR: {global_config} is not a JSON object", file=sys.stderr)
        return 1

    errors = []
    reports = []

    # The global config first: the updater's reconciler would otherwise replace
    # its retired key with the dist default and lose a `false` intent.
    line = migrate_file(global_config, errors)
    if line:
        reports.append(line)

    for project in global_data.get("projects", []) or []:
        if not isinstance(project, str):
            continue
        project = os.path.abspath(os.path.join(os.path.dirname(global_config), project))
        config = os.path.join(project, ".devbot.project.jsonc")
        if not os.path.isfile(config):
            continue
        line = migrate_file(config, errors)
        if line:
            reports.append(line)

    if reports:
        print("\n".join(reports))
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
