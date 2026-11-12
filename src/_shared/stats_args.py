#!/usr/bin/env python3
"""Shared helpers for ``devbot stats`` adapters.

Small, harness-independent argument-normalisation helpers used by the harness
adapters (opencode, claudecode) when aggregating tool arguments.
"""
from __future__ import annotations

import re
import shlex


def _is_bare_cd(line: str) -> bool:
    """True if the line is just ``cd <path>`` with no trailing command."""
    match = re.match(r"^\s*cd\s+", line)
    if not match:
        return False
    rest = line[match.end():]
    return "&&" not in rest and ";" not in rest


def strip_leading_cd(line: str) -> str:
    """Drop a leading ``cd <path> && `` (or ``; ``) from a single line."""
    while True:
        match = re.match(r"^\s*cd\s+", line)
        if not match:
            return line
        rest = line[match.end():]
        positions = [p for p in (rest.find("&&"), rest.find(";")) if p != -1]
        if not positions:
            return line
        idx = min(positions)
        sep_len = 2 if rest[idx:idx + 2] == "&&" else 1
        line = rest[idx + sep_len:].strip()


# A tool argument can carry a credential: an `export TOKEN=…`, a signed URL, a
# connection string, an inline password on a SQL call. The report groups by
# these values and prints them, so anything credential-shaped is masked first.
_SECRET_PATTERNS = (
    # key=value / key: value forms, with or without quotes around the value.
    # An auth scheme is part of the credential, not decoration: in
    # `Authorization: Bearer abc123` a value match that stops at the space
    # would mask `Bearer` and leave `abc123` in the report.
    re.compile(
        # `(?<!--)` leaves `--token …` to the option rule below, so the mask
        # keeps the option's shape. A single leading hyphen must still match:
        # `X-Api-Key: …` is a header, not a CLI flag.
        r"(?i)(?<!--)\b(password|passwd|pwd|token|secret|api[_-]?key|access[_-]?key"
        r"|client[_-]?secret|authorization|bearer)\b"
        r"[\"']?\s*[:=]?\s*[\"']?"
        r"(?:(bearer|basic|digest|negotiate)\s+)?"
        r"[^\s\"',;]+[\"']?"
    ),
    # scheme://user:password@host
    re.compile(r"(?i)\b([a-z][a-z0-9+.-]*://)[^\s:/@]+:[^\s@/]+@"),
    # a long opaque blob: hex, base64 or an AWS-style key id. Requiring both a
    # letter and a digit keeps ordinary long identifiers (a branch slug, a
    # repeated filler) visible — only key-shaped runs are masked.
    re.compile(
        r"\b(?=[A-Za-z0-9+/_=-]{32,}\b)"
        r"(?=[A-Za-z0-9+/_=-]*\d)(?=[A-Za-z0-9+/_=-]*[A-Za-z])"
        r"[A-Za-z0-9+/_=-]{32,}\b"
    ),
    # A separate-token option: `--token supersecret` carries the secret in the
    # NEXT element, so joining a positional list first would leave it readable.
    # Only unambiguous names qualify — `--key` alone takes a harmless value
    # (`project-for-path <path> --key modules`).
    re.compile(
        r"(?i)(--[a-z0-9-]*(?:token|secret|password|passwd|credential"
        r"|api-key|access-key|client-secret|private-key))[\s=:]+[^\s\"',;]+"
    ),
)
_SECRET_MASK = "***"

# A field/option name that holds a credential. Used where the value alone
# carries no tell: `{"password": "hunter2"}` is a new MCP tool's arbitrary
# schema, and no value pattern can know that.
_SENSITIVE_NAME = re.compile(
    r"(?i)(password|passwd|pwd|token|secret|api[_-]?key|access[_-]?key"
    r"|client[_-]?secret|authorization|credential|private[_-]?key)"
)


def is_sensitive_name(name) -> bool:
    """True when a field or option name denotes a credential."""
    return bool(name) and bool(_SENSITIVE_NAME.search(str(name)))


def _mask_key_value(match: "re.Match[str]") -> str:
    """Keep the key and any auth scheme visible; mask only the credential."""
    key, scheme = match.group(1), match.group(2)
    return f"{key}=" + (f"{scheme} " if scheme else "") + _SECRET_MASK


def redact_secrets(text: str) -> str:
    """Mask credential-shaped fragments so a report never quotes a secret."""
    if not text:
        return ""
    cleaned = _SECRET_PATTERNS[0].sub(_mask_key_value, text)
    cleaned = _SECRET_PATTERNS[1].sub(lambda m: m.group(1) + _SECRET_MASK + "@", cleaned)
    cleaned = _SECRET_PATTERNS[2].sub(_SECRET_MASK, cleaned)
    return _SECRET_PATTERNS[3].sub(lambda m: m.group(1) + " " + _SECRET_MASK, cleaned)


def tool_arg_value(value, limit: int = 80) -> str:
    """Collapse a tool argument value to one bounded line.

    MCP tools carry free-form strings (a search query, a SQL statement); the
    stats report groups by them, so whitespace is collapsed and the value is
    capped well inside the rendered column. Non-string values yield "" — a
    list or dict would render as noise rather than an argument.
    """
    if not isinstance(value, str):
        return ""
    collapsed = " ".join(redact_secrets(value).split())
    if len(collapsed) > limit:
        collapsed = collapsed[: limit - 1].rstrip() + "…"
    return collapsed


def mask_argv(parts) -> str:
    """Join a positional argument list, masking the value of a secret option.

    `["--token", "supersecret"]` keeps the secret in a later element, where a
    pattern over the joined text can still miss it — so sensitive pairs are
    masked before the join.
    """
    if not isinstance(parts, list):
        return ""
    out: list[str] = []
    mask_next = False
    for part in parts:
        token = str(part)
        if mask_next:
            out.append(_SECRET_MASK)
            mask_next = False
            continue
        out.append(token)
        if token.startswith("-") and is_sensitive_name(token.lstrip("-")):
            mask_next = True
    return " ".join(out)


def bash_value(command) -> str:
    """Normalise a bash command to ``program subcommand`` (first two tokens).

    Agents prefix the project dir in several shapes — ``cd <path> && cmd``, a
    leading ``cd <path>`` line, or a leading comment line — all of which are
    stripped before the first two tokens are taken.
    """
    lines = (command or "").strip().splitlines()
    idx = 0
    while idx < len(lines):
        line = lines[idx].strip()
        if not line or line.startswith("#") or _is_bare_cd(line):
            idx += 1
            continue
        break
    line = strip_leading_cd(lines[idx].strip()) if idx < len(lines) else ""
    try:
        tokens = shlex.split(line)
    except ValueError:
        tokens = line.split()
    return " ".join(tokens[:2])
