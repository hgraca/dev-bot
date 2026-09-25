#!/usr/bin/env python3
"""The PHP op table — single source of truth for the refactor tool's PHP ops.

Subcommands:
    meta              — plugin descriptor JSON for the core's registry
    rules <op>        — JSON array of the Rector rules an op needs, in step order
    render <op> [i]   — read a refactor request as JSON on stdin and write the
                        generated `rector.php` for step `i` (default 0)

Why steps: an op may need more than one rule (a usages rule plus the declaration
rule). Registering both in one config does not compose — the declaration rename
invalidates the reflection the usages rule resolves calls through, so the calls
silently stay put. Each step therefore runs as its own Rector invocation with
exactly one rule, which is also the safety posture everywhere else (`--only`).

Entry shape:
    rule         Rector rule class for the usages half of the op
    vo           value-object class, when that rule is configured with objects
    shape        "vo"  -> withConfiguredRule(Rule, [new VO(<args>)])
                 "map" -> withConfiguredRule(Rule, ['<from>' => '<to>'])
    args         which request fields fill the VO, in order (shape "vo" only)
    qualify      map keys/values are namespace-qualified (the rule matches on
                 the resolved name, so a bare name silently matches nothing)
    declaration  adds a second step registering RenameDeclarationRector for this
                 kind ("function" | "constant" | "class") — Rector's renaming
                 rules are usages-only, so without it the rename is a half-rename
"""

import json
import os
import re
import sys

DECLARATION_RULE = "Devbot\\Refactor\\RenameDeclarationRector"
DECLARATION_REQUIRE = "require_once '/refactor/rules/RenameDeclarationRector.php';"

OPS = {
    "rename-method": {
        "rule": "Rector\\Renaming\\Rector\\MethodCall\\RenameMethodRector",
        "vo": "Rector\\Renaming\\ValueObject\\MethodCallRename",
        "shape": "vo",
        "args": ["class", "from", "to"],
        "requires": ["class", "from", "to"],
    },
    # RenameMethodRector (not RenameStaticMethodRector) deliberately: it rewrites
    # the declaration as well as the calls, so it needs no second step.
    "rename-static-method": {
        "rule": "Rector\\Renaming\\Rector\\MethodCall\\RenameMethodRector",
        "vo": "Rector\\Renaming\\ValueObject\\MethodCallRename",
        "shape": "vo",
        "args": ["class", "from", "to"],
        "requires": ["class", "from", "to"],
    },
    "rename-property": {
        "rule": "Rector\\Renaming\\Rector\\PropertyFetch\\RenamePropertyRector",
        "vo": "Rector\\Renaming\\ValueObject\\RenameProperty",
        "shape": "vo",
        "args": ["class", "from", "to"],
        "requires": ["class", "from", "to"],
    },
    # Annotations live in doc-comments: no separate declaration, so one step.
    "rename-annotation": {
        "rule": "Rector\\Renaming\\Rector\\ClassMethod\\RenameAnnotationRector",
        "vo": "Rector\\Renaming\\ValueObject\\RenameAnnotationByType",
        "shape": "vo",
        "args": ["class", "from", "to"],
        "requires": ["class", "from", "to"],
    },
    # A free function: Rector resolves the call by fully-qualified name, so the
    # namespace is needed — hence `qualify`, and the class field is not.
    "rename-function": {
        "rule": "Rector\\Renaming\\Rector\\FuncCall\\RenameFunctionRector",
        "shape": "map",
        "qualify": True,
        "declaration": "function",
        "requires": ["from", "to"],
    },
    # Constants: the usages rule matches on the BARE name (a qualified key is
    # rejected outright), so no `qualify` here — unlike functions.
    "rename-constant": {
        "rule": "Rector\\Renaming\\Rector\\ConstFetch\\RenameConstantRector",
        "shape": "map",
        "declaration": "constant",
        "requires": ["from", "to"],
    },
    # A class rename also has to move the file: Rector rewrites the declaration
    # and the references but moves no files, and a PSR-4 autoloader keys on the
    # file name, so leaving it produces a class that no longer loads.
    "rename-class": {
        "rule": "Rector\\Renaming\\Rector\\Name\\RenameClassRector",
        "shape": "map",
        "qualify": True,
        "declaration": "class",
        "move_file": True,
        "requires": ["from", "to"],
    },
    # A class move keeps the class name and changes its namespace. Rector rewrites
    # the references, and ships no namespace rule at all — but a namespace rename
    # would hit EVERY file in the namespace, whereas a move changes one file. So
    # the namespace is rewritten by the plugin, on the declaration file alone.
    "move-class": {
        "rule": "Rector\\Renaming\\Rector\\Name\\RenameClassRector",
        "shape": "map",
        "move_file": True,
        "namespace_move": True,
        "requires": ["from", "to"],
    },
    # A class constant: the fetch rule rewrites `self::OLD` and leaves the
    # declaration, so the class-constant declaration step is ours.
    "rename-class-constant": {
        "rule": "Rector\\Renaming\\Rector\\ClassConstFetch\\RenameClassConstFetchRector",
        "vo": "Rector\\Renaming\\ValueObject\\RenameClassConstFetch",
        "shape": "vo",
        "args": ["class", "from", "to"],
        "declaration": "class-constant",
        "requires": ["class", "from", "to"],
    },
    # A string literal has no declaration, so the usages rule alone is complete.
    "rename-string": {
        "rule": "Rector\\Renaming\\Rector\\String_\\RenameStringRector",
        "shape": "map",
        "requires": ["from", "to"],
    },
    # Cleanup ops: unconfigured rules that act across the scope, changing many
    # things rather than one symbol. No from/to.
    "remove-unused-private-methods": {
        "rule": "Rector\\DeadCode\\Rector\\ClassMethod\\RemoveUnusedPrivateMethodRector",
        "shape": "rules",
        "requires": [],
    },
    "remove-unused-private-properties": {
        "rule": "Rector\\DeadCode\\Rector\\Property\\RemoveUnusedPrivatePropertyRector",
        "shape": "rules",
        "requires": [],
    },
    "privatize-final-class-properties": {
        "rule": "Rector\\Privatization\\Rector\\Property\\PrivatizeFinalClassPropertyRector",
        "shape": "rules",
        "requires": [],
    },
    "privatize-final-class-methods": {
        "rule": "Rector\\Privatization\\Rector\\ClassMethod\\PrivatizeFinalClassMethodRector",
        "shape": "rules",
        "requires": [],
    },
    "privatize-final-class-constants": {
        "rule": "Rector\\Privatization\\Rector\\ClassConst\\PrivatizeFinalClassConstantRector",
        "shape": "rules",
        "requires": [],
    },
    "remove-unused-private-class-constants": {
        "rule": "Rector\\DeadCode\\Rector\\ClassConst\\RemoveUnusedPrivateClassConstantRector",
        "shape": "rules",
        "requires": [],
    },
    # These two are classified `signature` below: dropping a constructor parameter
    # changes the callable, not just what is inside it.
    "remove-unused-constructor-params": {
        "rule": "Rector\\DeadCode\\Rector\\ClassMethod\\RemoveUnusedConstructorParamRector",
        "shape": "rules",
        "requires": [],
    },
    "remove-unused-promoted-properties": {
        "rule": "Rector\\DeadCode\\Rector\\ClassMethod\\RemoveUnusedPromotedPropertyRector",
        "shape": "rules",
        "requires": [],
    },
}

# How much care an op needs. The tool never runs the caller's tests, so this is
# the signal an agent uses to judge how much its own suite must back the change.
#   rename    — behaviour preserving; the symbol keeps its role
#   cleanup   — deletes dead code or tightens visibility; safe for correct code
#   signature — changes a callable's signature or a type; can break callers
RISKS = {
    "rename-method": "rename",
    "rename-static-method": "rename",
    "rename-property": "rename",
    "rename-annotation": "rename",
    "rename-function": "rename",
    "rename-constant": "rename",
    "rename-class": "rename",
    "rename-class-constant": "rename",
    "rename-string": "rename",
    "move-class": "rename",
    "remove-unused-private-methods": "cleanup",
    "remove-unused-private-properties": "cleanup",
    "remove-unused-private-class-constants": "cleanup",
    "privatize-final-class-properties": "cleanup",
    "privatize-final-class-methods": "cleanup",
    "privatize-final-class-constants": "cleanup",
    "remove-unused-constructor-params": "signature",
    "remove-unused-promoted-properties": "signature",
}

LANG = "php"
EXTENSIONS = [".php"]

# The canonical operation vocabulary: one name per refactoring, shared by every
# language. Each plugin maps a canonical op to its own native ops by KIND, so the
# core stays language-agnostic — it only merges these maps and resolves a name.
# A kind the plugin does not list simply does not exist for that language.
CANONICAL = {
    # Renaming a symbol. `--kind` picks which Rector rule: the declaration and
    # the references move together in every case.
    "rename": {
        "method": "rename-method",
        "static-method": "rename-static-method",
        "property": "rename-property",
        "annotation": "rename-annotation",
        "function": "rename-function",
        "constant": "rename-constant",
        "class": "rename-class",
        "class-constant": "rename-class-constant",
        "string": "rename-string",
    },
    # Relocating a unit and repointing what refers to it (a class's namespace and
    # file, here).
    "move": {
        "class": "move-class",
    },
    # Deleting what nothing references, and tightening visibility.
    "remove-unused": {
        "method": "remove-unused-private-methods",
        "property": "remove-unused-private-properties",
        "class-constant": "remove-unused-private-class-constants",
        "constructor-param": "remove-unused-constructor-params",
        "promoted-property": "remove-unused-promoted-properties",
    },
    "privatize": {
        "method": "privatize-final-class-methods",
        "property": "privatize-final-class-properties",
        "constant": "privatize-final-class-constants",
    },
}

_NAMESPACE_RE = re.compile(r"^\s*namespace\s+([A-Za-z_][A-Za-z0-9_\\]*)\s*;", re.M)


def php_literal(value: str) -> str:
    """A PHP single-quoted literal. Only backslash and quote need escaping."""
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def qualify(namespace: str, name: str) -> str:
    return "%s\\%s" % (namespace, name) if namespace else name


def _declaration_re(name: str, kind: str) -> re.Pattern:
    if kind == "function":
        return re.compile(r"^\s*function\s+" + re.escape(name) + r"\s*\(", re.M)
    if kind == "constant":
        return re.compile(r"^\s*const\s+" + re.escape(name) + r"\s*=", re.M)
    return re.compile(r"^\s*(?:final\s+|abstract\s+)*class\s+" + re.escape(name) + r"\b", re.M)


def find_declarations(project: str, name: str, kind: str) -> list:
    """(namespace, path) for each declaration of `name` under the source roots."""
    if not project or not os.path.isdir(project):
        return []

    pattern = _declaration_re(name, kind)
    found = []
    for root_name in ("app", "src"):
        root = os.path.join(project, root_name)
        if not os.path.isdir(root):
            continue
        for dirpath, _dirs, files in os.walk(root):
            for filename in files:
                if not filename.endswith(".php"):
                    continue
                path = os.path.join(dirpath, filename)
                try:
                    with open(path, encoding="utf-8", errors="replace") as handle:
                        text = handle.read()
                except OSError:
                    continue
                if not pattern.search(text):
                    continue
                match = _NAMESPACE_RE.search(text)
                found.append((match.group(1) if match else "", path))

    return found


def find_declaring_namespaces(project: str, name: str, kind: str) -> list:
    """Namespaces declaring `name` under the project's source roots ("" = global)."""
    return list(dict.fromkeys(ns for ns, _path in find_declarations(project, name, kind)))


def resolve_namespace(request: dict, spec: dict, from_name: str, to_name: str = "") -> str:
    """The namespace for a qualified op: explicit, else derived, else fatal."""
    explicit = request.get("namespace")
    if explicit:
        return explicit

    kind = spec.get("declaration") or "function"
    project = request.get("project") or ""
    candidates = find_declaring_namespaces(project, from_name, kind)
    if not candidates and to_name:
        # A completed rename leaves the declaration under the NEW name, and the
        # namespace is unchanged. Without this fallback a re-plan — including the
        # post-apply verification pass — could not resolve the op at all, and the
        # verification would report a clean run it never performed.
        candidates = find_declaring_namespaces(project, to_name, kind)

    if not candidates:
        raise ValueError(
            "could not find a declaration of '%s' under app/ or src/ — "
            "pass --namespace explicitly" % from_name
        )
    if len(candidates) > 1:
        raise ValueError(
            "'%s' is declared in several namespaces (%s) — pass --namespace to pick one"
            % (from_name, ", ".join(ns or "(global)" for ns in candidates))
        )
    return candidates[0]


_QUOTED_RE = re.compile(r"'([^'\n]*)'|\"([^\"\n]*)\"")


def find_string_references(project: str, name: str) -> list:
    """Quoted occurrences of `name` under the source roots.

    Every rename here is blind to a reference held in a string — a class, method
    or function named inside quotes (`'App\\Old'`, `"oldMethod"`). Those are
    exactly the dynamic references each op documents as invisible, so they are
    surfaced for the caller to judge rather than silently left behind.
    """
    if not project or not os.path.isdir(project) or not name:
        return []

    hits = []
    for root_name in ("app", "src"):
        root = os.path.join(project, root_name)
        if not os.path.isdir(root):
            continue
        for dirpath, _dirs, files in os.walk(root):
            for filename in sorted(files):
                if not filename.endswith(".php"):
                    continue
                path = os.path.join(dirpath, filename)
                try:
                    with open(path, encoding="utf-8", errors="replace") as handle:
                        text = handle.read()
                except OSError:
                    continue
                for match in _QUOTED_RE.finditer(text):
                    content = match.group(1) if match.group(1) is not None else match.group(2)
                    if not content or name not in content:
                        continue
                    hits.append(
                        {
                            "file": os.path.relpath(path, project),
                            "line": text.count("\n", 0, match.start()) + 1,
                            "text": content.strip(),
                        }
                    )
    return hits


def namespace_target_dir(path: str, old_fq: str, new_fq: str):
    """The PSR-4 directory for a class moved to another namespace, or None.

    The source directory mirrors the source namespace's tail (the namespace minus
    its root prefix); the target is rebuilt the same way. Returns None when the
    layout does not mirror the namespace — guessing would move the file somewhere
    that does not match, and a wrong move is worse than no move.
    """
    old_ns = old_fq.split("\\")[:-1]
    new_ns = new_fq.split("\\")[:-1]
    tail = old_ns[1:]

    # Split the absolute dir, keeping the root: normpath("/a/b").split("/") yields
    # a leading empty segment, and joining from it would drop the leading slash.
    segments = os.path.dirname(path).rstrip(os.sep).split(os.sep)
    if tail and segments[-len(tail):] != tail:
        return None

    keep = segments[: len(segments) - len(tail)] if tail else segments
    if not keep:
        return None

    root = os.sep.join(keep)
    return os.path.join(root, *new_ns[1:]) if new_ns[1:] else root


def steps_for(request: dict, spec: dict):
    """The ordered Rector steps for an op, each self-contained (imports + config)."""
    values = {
        "class": request.get("class") or "",
        "from": request.get("from") or "",
        "to": request.get("to") or "",
    }

    missing = [field for field in spec.get("requires", []) if not values.get(field)]
    if missing:
        raise ValueError(
            "op '%s' requires %s" % (request.get("op"), ", ".join("--" + f for f in missing))
        )

    steps = []

    # Unconfigured rule: runs over the scope and changes whatever it finds, so it
    # takes no from/to and needs no second step.
    if spec["shape"] == "rules":
        return [
            {
                "rule": spec["rule"],
                "imports": ["use %s;" % spec["rule"]],
                "body": ["    ->withRules([%s::class]);" % spec["rule"].rsplit("\\", 1)[-1]],
            }
        ]

    namespace = ""
    if spec.get("qualify"):
        namespace = resolve_namespace(request, spec, values["from"], values["to"])

    # The declaration rule is handed the same (qualified) names as the usages
    # rule, so a common short name cannot match a declaration elsewhere.
    declared_from = qualify(namespace, values["from"]) if namespace else values["from"]
    declared_to = qualify(namespace, values["to"]) if namespace else values["to"]

    if spec["shape"] == "map":
        pair = "        %s => %s," % (php_literal(declared_from), php_literal(declared_to))
    else:
        vo_short = spec["vo"].rsplit("\\", 1)[-1]
        args = ", ".join(php_literal(values[a]) for a in spec["args"])
        pair = "        new %s(%s)," % (vo_short, args)

    short = spec["rule"].rsplit("\\", 1)[-1]
    imports = ["use %s;" % spec["rule"]]
    if spec.get("vo"):
        imports.append("use %s;" % spec["vo"])
    steps.append(
        {
            "rule": spec["rule"],
            "imports": imports,
            "body": [
                "    ->withConfiguredRule(%s::class, [" % short,
                pair,
                "    ]);",
            ],
        }
    )

    if spec.get("declaration"):
        steps.append(
            {
                "rule": DECLARATION_RULE,
                "imports": ["use %s;" % DECLARATION_RULE],
                "require": DECLARATION_REQUIRE,
                "body": [
                    "    ->withConfiguredRule(RenameDeclarationRector::class, [",
                    "        'kind' => %s," % php_literal(spec["declaration"]),
                    "        'from' => %s," % php_literal(declared_from),
                    "        'to' => %s," % php_literal(declared_to),
                    "    ]);",
                ],
            }
        )

    return steps


def render(request: dict, index: int = 0) -> int:
    op = request.get("op") or ""
    spec = OPS.get(op)
    if spec is None:
        print("ERROR: unsupported op: %s" % op, file=sys.stderr)
        return 1

    try:
        steps = steps_for(request, spec)
    except ValueError as error:
        print("ERROR: %s" % error, file=sys.stderr)
        return 1

    if index < 0 or index >= len(steps):
        print("ERROR: step %d out of range for op %s" % (index, op), file=sys.stderr)
        return 1

    step = steps[index]
    scope = request.get("scope") or ["/app"]

    lines = ["<?php", "", "declare(strict_types=1);", "", "use Rector\\Config\\RectorConfig;"]
    lines += step["imports"]
    if step.get("require"):
        lines += ["", step["require"]]

    lines += [
        "",
        "return RectorConfig::configure()",
        "    ->withPaths([" + ", ".join(php_literal(p) for p in scope) + "])",
    ]
    lines += step["body"]
    lines.append("")

    sys.stdout.write("\n".join(lines))
    return 0


def rules_for(op: str):
    spec = OPS.get(op)
    if spec is None:
        return None
    found = [spec["rule"]]
    if spec.get("declaration"):
        found.append(DECLARATION_RULE)
    return found


def main(argv: list) -> int:
    command = argv[1] if len(argv) > 1 else ""

    if command == "meta":
        print(json.dumps({
            "lang": LANG,
            "extensions": EXTENSIONS,
            "ops": list(CANONICAL),
            "map": CANONICAL,
            "requires": {op: spec.get("requires", []) for op, spec in OPS.items()},
            "risks": {op: RISKS.get(op, "cleanup") for op in OPS},
        }))
        return 0

    if command == "rules":
        op = argv[2] if len(argv) > 2 else ""
        found = rules_for(op)
        if found is None:
            print("ERROR: unsupported op: %s" % op, file=sys.stderr)
            return 1
        print(json.dumps(found))
        return 0

    if command == "move-target":
        # The host file a class rename must relocate: Rector moves no files, and a
        # PSR-4 autoloader keys on the file name. Emits nothing when the op does
        # not move files, when the declaration is absent, or when it is ambiguous
        # (several matches) — the caller leaves those to the human.
        request = json.load(sys.stdin)
        spec = OPS.get(request.get("op") or "")
        if not spec or not spec.get("move_file"):
            return 0

        old = request.get("from") or ""
        new = request.get("to") or ""
        # The declaration carries the SHORT name; `from` may be qualified.
        found = find_declarations(
            request.get("project") or "", old.rsplit("\\", 1)[-1], spec.get("declaration") or ""
        )
        if len(found) != 1:
            return 0

        _namespace, path = found[0]
        short = new.rsplit("\\", 1)[-1]

        result = {"from": path}
        if spec.get("namespace_move"):
            target_dir = namespace_target_dir(path, old, new)
            if target_dir is None:
                return 0
            # The plugin rewrites the namespace in this one file: a namespace step
            # in Rector would hit every file in the namespace instead.
            result["namespace_from"] = old.rsplit("\\", 1)[0] if "\\" in old else ""
            result["namespace_to"] = new.rsplit("\\", 1)[0] if "\\" in new else ""
            result["to"] = os.path.join(target_dir, short + ".php")
        else:
            result["to"] = os.path.join(os.path.dirname(path), short + ".php")

        if os.path.normpath(path) == os.path.normpath(result["to"]) and not spec.get("namespace_move"):
            return 0

        print(json.dumps(result))
        return 0

    if command == "string-refs":
        request = json.load(sys.stdin)
        if OPS.get(request.get("op") or "") is None:
            return 0
        name = (request.get("from") or "").rsplit("\\", 1)[-1]
        print(json.dumps({"hits": find_string_references(request.get("project") or "", name)}))
        return 0

    if command == "render":
        index = int(argv[2]) if len(argv) > 2 else 0
        return render(json.load(sys.stdin), index)

    print("ERROR: ops.py: expected one of meta|rules|render|move-target|string-refs", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
