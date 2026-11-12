#!/usr/bin/env python3
"""Report how full the calling session's context window is.

Harness-agnostic front end for the ``session-usage`` MCP tool: resolves which
session is asking, delegates the harness-specific read to
``src/harnesses/<harness>/session_usage.py``, resolves the model's context
limit, and renders one line (or JSON).
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
DEV_BOT_ROOT = os.path.normpath(os.path.join(_HERE, "..", ".."))
HARNESS_ENV = "DEV_BOT_SESSION_USAGE_HARNESS"
SESSION_ENV = "DEV_BOT_SESSION_ID"
SUPPORTED_HARNESSES = ("opencode", "claudecode")

sys.path.insert(0, _HERE)
import model_limit  # noqa: E402

_ERRORS = {
    "unknown-session": "unknown session '{session}'",
    "no-usage": "no assistant step recorded yet for session '{session}'",
    "no-database": "cannot read the harness transcript database: {detail}",
}


def _adapter(harness):
    path = os.path.join(DEV_BOT_ROOT, "src", "harnesses", harness, "session_usage.py")
    spec = importlib.util.spec_from_file_location(f"session_usage_{harness}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _is_plain_relative(value):
    if os.path.isabs(value) or value.startswith("~"):
        return False
    return ".." not in value.replace("\\", "/").split("/")


def _devbot_dir(project_dir):
    try:
        from read_jsonc import load_jsonc

        value = load_jsonc(os.path.join(project_dir, ".devbot.project.jsonc")).get(
            "devbot_dir"
        )
        if isinstance(value, str) and _is_plain_relative(value):
            return value
    except Exception:
        pass
    return ".agents"


def _marker_session(project_dir, harness):
    path = os.path.join(
        project_dir, _devbot_dir(project_dir), "logs", f"session-{harness}"
    )
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def resolve_session(explicit, project_dir, harness):
    return (
        (explicit or "").strip()
        or os.environ.get(SESSION_ENV, "").strip()
        or _marker_session(project_dir, harness)
    )


def _model_label(provider, model):
    if provider and model:
        return f"{provider}/{model}"
    return model or provider or "unknown"


def build_payload(report, harness):
    tokens = int(report["context_tokens"])
    limit = model_limit.resolve(report.get("provider", ""), report.get("model", ""))
    percent = round(tokens * 100 / limit, 1) if limit else None
    return {
        "session": report["session"],
        "harness": harness,
        "model": _model_label(report.get("provider", ""), report.get("model", "")),
        "context_tokens": tokens,
        "context_limit": limit,
        "percent": percent,
    }


def render_text(payload):
    tokens = f"{payload['context_tokens']:,}"
    if payload["context_limit"]:
        usage = (
            f"context {tokens} / {payload['context_limit']:,} "
            f"({payload['percent']}%)"
        )
    else:
        usage = f"context {tokens} (limit unknown)"
    return f"{usage} — {payload['model']} · {payload['session']}"


def _fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def main(argv):
    parser = argparse.ArgumentParser(prog="session-usage", add_help=True)
    parser.add_argument("--session")
    parser.add_argument("--harness")
    parser.add_argument(
        "--project-dir", default=os.environ.get("TOOLS_MCP_PROJECT_DIR") or os.getcwd()
    )
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    harness = (args.harness or os.environ.get(HARNESS_ENV) or "").strip().lower()
    if harness not in SUPPORTED_HARNESSES:
        return _fail(
            f"unsupported harness '{harness}' "
            f"(expected one of: {', '.join(SUPPORTED_HARNESSES)})"
        )

    session = resolve_session(args.session, args.project_dir, harness)
    if not session:
        return _fail(
            "no session id — pass --session <id> "
            '(in bash: echo "$DEV_BOT_SESSION_ID")'
        )

    report = _adapter(harness).gather(session)
    if "error" in report:
        template = _ERRORS.get(report["error"], "cannot read session '{session}'")
        return _fail(template.format(**report))

    payload = build_payload(report, harness)
    print(json.dumps(payload) if args.json else render_text(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
