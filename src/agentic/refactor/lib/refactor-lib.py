#!/usr/bin/env python3
"""JSON + plugin-registry helper for the refactor CLI.

The CLI entry point is `refactor.sh` (bash). This helper carries everything that
needs real JSON handling:

    resolve   read the CLI options, discover the language plugins, pick one,
              validate the refactoring and its required fields, write the
              decision as JSON on stdout
    emit      turn a decision into the two lines the shell needs (plugin
              directory, request JSON)
    ops       print the union of every plugin's refactorings (for --help)
    finish    read a plugin's response, print its warnings, write the rendered
              report, and exit non-zero when the refactoring failed

Subcommands are reached only from refactor.sh; the contract with a plugin is
unchanged (plan/apply take the request JSON on stdin and answer with JSON on
stdout).
"""

import argparse
import json
import os
import subprocess
import sys


def _warn(message):
    sys.stderr.write("WARN: %s\n" % message)


# ── Plugin discovery ──────────────────────────────────────────────────────────


def discover(langs_dir):
    """Every langs/<lang>/plugin.sh that answers `meta` with a valid descriptor."""
    plugins = []
    if not os.path.isdir(langs_dir):
        return plugins

    for entry in sorted(os.listdir(langs_dir)):
        directory = os.path.join(langs_dir, entry)
        script = os.path.join(directory, "plugin.sh")
        if not os.path.isfile(script):
            continue

        try:
            completed = subprocess.run(
                ["bash", script, "meta"],
                capture_output=True,
                text=True,
                check=True,
            )
            meta = json.loads(completed.stdout)
        except Exception:
            meta = None

        if not isinstance(meta, dict) or not isinstance(meta.get("lang"), str):
            _warn("langs/%s exposes no valid meta — skipped" % entry)
            continue

        meta["_dir"] = directory
        plugins.append(meta)

    return plugins


def ops_union(plugins):
    ops = set()
    for plugin in plugins:
        ops.update(plugin.get("ops") or [])
    return ", ".join(sorted(ops)) or "none"


def _select_lang(plugins, op, lang, file_path):
    available = ", ".join(sorted(plugin["lang"] for plugin in plugins)) or "none"

    if lang:
        for plugin in plugins:
            if plugin["lang"] == lang:
                return plugin
        raise ValueError("unknown language '%s' (available: %s)" % (lang, available))

    if file_path:
        extension = os.path.splitext(file_path)[1].lower()
        matches = [
            plugin
            for plugin in plugins
            if extension in [item.lower() for item in (plugin.get("extensions") or [])]
        ]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            raise ValueError(
                "extension '%s' matches several languages (%s) — pass --lang"
                % (extension, ", ".join(sorted(plugin["lang"] for plugin in matches)))
            )
        raise ValueError(
            "cannot infer a language from '%s' (extension '%s') — pass --lang"
            % (file_path, extension or "none")
        )

    matches = [plugin for plugin in plugins if op in (plugin.get("ops") or [])]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        raise ValueError(
            "unknown op '%s' (available: %s)" % (op, ops_union(plugins))
        )
    raise ValueError(
        "op '%s' exists in several languages (%s) — pass --file or --lang"
        % (op, ", ".join(sorted(plugin["lang"] for plugin in matches)))
    )


# ── Subcommands ───────────────────────────────────────────────────────────────


def _resolve_native(plugin, op, kind, method, prop):
    """(kind, native_op) for a canonical op, using the plugin's own map.

    The map is `{canonical: {kind: native}}`. A `*` key means the op has one
    native form and any kind is passed through (the TypeScript driver reads
    `kind` as a declaration kind). An op with several named kinds needs one —
    named explicitly, or inferred from --method/--property.
    """
    mapping = (plugin.get("map") or {}).get(op) or {}
    if not mapping:
        raise ValueError(
            "language '%s' exposes no map for op '%s'" % (plugin["lang"], op)
        )
    named = sorted(key for key in mapping if key != "*")

    if kind:
        if kind in mapping:
            return kind, mapping[kind]
        if "*" in mapping:
            return kind, mapping["*"]
        raise ValueError(
            "op '%s' does not support kind '%s' (kinds: %s)"
            % (op, kind, ", ".join(named) or "none")
        )

    if method and "method" in mapping:
        return "method", mapping["method"]
    if prop and "property" in mapping:
        return "property", mapping["property"]

    if "*" in mapping:
        return None, mapping["*"]
    if len(named) == 1:
        return named[0], mapping[named[0]]
    raise ValueError("op '%s' needs --kind (one of: %s)" % (op, ", ".join(named)))


def cmd_resolve(args):
    plugins = discover(args.langs_dir)
    plugin = _select_lang(plugins, args.op, args.lang, args.file)

    if args.op not in (plugin.get("ops") or []):
        raise ValueError(
            "%s does not support op '%s' (supports: %s)"
            % (
                plugin["lang"],
                args.op,
                ", ".join(plugin.get("ops") or []) or "none",
            )
        )

    kind, native_op = _resolve_native(plugin, args.op, args.kind, args.method, args.property)

    source = args.from_ or args.method or args.property
    provided = {
        "class": args.klass,
        "from": source,
        "to": args.to,
        "file": args.file,
        "kind": kind,
        "start": args.start,
        "end": args.end,
        "index": args.index,
        "default": args.default,
    }

    requires_map = plugin.get("requires") or {}
    requires = requires_map[native_op] if native_op in requires_map else ["class", "from", "to"]
    missing = [field for field in requires if not provided.get(field)]
    if missing:
        raise ValueError(
            "op '%s' requires %s"
            % (args.op, ", ".join("--" + field for field in missing))
        )

    request = {
        "op": native_op,
        "class": args.klass or None,
        "from": source or None,
        "to": args.to or None,
        "apply": args.apply == "true",
        "image": args.image or None,
        "namespace": args.namespace or None,
        "file": args.file or None,
        "kind": kind,
        "start": args.start or None,
        "end": args.end or None,
        "index": args.index or None,
        "default": args.default or None,
    }

    print(json.dumps({
        "lang": plugin["lang"],
        "plugin": plugin["_dir"],
        "risk": (plugin.get("risks") or {}).get(native_op),
        "request": request,
    }))
    return 0


def cmd_emit(_args):
    decision = json.load(sys.stdin)
    sys.stdout.write(
        "%s\n%s\n%s\n"
        % (decision["plugin"], json.dumps(decision["request"]), decision.get("risk") or "")
    )
    return 0


def cmd_ops(args):
    print(ops_union(discover(args.langs_dir)))
    return 0


def render_markdown(response, op, risk=""):
    lines = ["## refactor: %s" % op, ""]
    lines.append("**Engine:** %s" % (response.get("engine") or "unknown"))
    lines.append("**Applied:** %s" % ("yes" if response.get("applied") else "no"))
    if risk:
        lines.append("**Risk:** %s" % risk)
    lines.append("")
    if response.get("summary"):
        lines.append(response["summary"])
        lines.append("")
    if response.get("files"):
        lines.append("### Files")
        for path in response["files"]:
            lines.append("- %s" % path)
        lines.append("")
    if response.get("string_references"):
        lines.append("### String references (reported, not rewritten)")
        for hit in response["string_references"]:
            lines.append("- %s:%s — %s" % (hit.get("file"), hit.get("line"), hit.get("text")))
        lines.append("")
    if response.get("remaining_changes"):
        lines.append(
            "**Remaining changes:** %s — references the rename could not reach"
            % response["remaining_changes"]
        )
        lines.append("")
    return "\n".join(lines) + "\n"


def cmd_finish(args):
    raw = sys.stdin.read()
    try:
        response = json.loads(raw)
    except ValueError:
        sys.stderr.write("ERROR: the plugin returned invalid JSON\n")
        return 1

    if not isinstance(response, dict):
        sys.stderr.write("ERROR: the plugin returned an unexpected response\n")
        return 1

    for warning in response.get("warnings") or []:
        _warn(warning)

    if not response.get("ok"):
        sys.stderr.write("ERROR: %s\n" % (response.get("error") or "refactor failed"))
        return 1

    if args.format == "json":
        sys.stdout.write(json.dumps(response, indent=2) + "\n")
    else:
        sys.stdout.write(render_markdown(response, args.op, args.risk))
    return 0


# ── Argument surface ──────────────────────────────────────────────────────────


def build_parser():
    parser = argparse.ArgumentParser(prog="refactor-lib")
    parser.add_argument(
        "--langs-dir",
        default=os.environ.get("REFACTOR_LANGS_DIR", ""),
        help="directory holding <lang>/plugin.sh (default: $REFACTOR_LANGS_DIR)",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    resolve = subparsers.add_parser("resolve")
    resolve.add_argument("--op", required=True)
    resolve.add_argument("--lang", default="")
    resolve.add_argument("--file", default="")
    resolve.add_argument("--kind", default="")
    resolve.add_argument("--class", dest="klass", default="")
    resolve.add_argument("--from", dest="from_", default="")
    resolve.add_argument("--method", default="")
    resolve.add_argument("--property", default="")
    resolve.add_argument("--to", default="")
    resolve.add_argument("--namespace", default="")
    resolve.add_argument("--start", default="")
    resolve.add_argument("--end", default="")
    resolve.add_argument("--index", default="")
    resolve.add_argument("--default", default="")
    resolve.add_argument("--image", default="")
    resolve.add_argument("--apply", default="false")
    resolve.set_defaults(func=cmd_resolve)

    emit = subparsers.add_parser("emit")
    emit.set_defaults(func=cmd_emit)

    ops = subparsers.add_parser("ops")
    ops.set_defaults(func=cmd_ops)

    finish = subparsers.add_parser("finish")
    finish.add_argument("--op", required=True)
    finish.add_argument("--risk", default="")
    finish.add_argument("--format", default="markdown", choices=["markdown", "json"])
    finish.set_defaults(func=cmd_finish)

    return parser


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    try:
        return args.func(args)
    except ValueError as error:
        sys.stderr.write("ERROR: %s\n" % error)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
