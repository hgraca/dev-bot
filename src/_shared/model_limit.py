#!/usr/bin/env python3
"""Resolve a model's context-window size from opencode's model catalog.

The catalog is the only authoritative source of a limit on this machine; when a
model is absent the caller must report "unknown" rather than invent a number.
"""
from __future__ import annotations

import json
import os

CATALOG_ENV = "OPENCODE_MODELS_JSON"

def catalog_path(path=None):
    if path:
        return os.path.expanduser(path)
    configured = os.environ.get(CATALOG_ENV)
    if configured:
        return os.path.expanduser(configured)
    cache = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(cache, "opencode", "models.json")


def _context_tokens(entry):
    limit = entry.get("limit") if isinstance(entry, dict) else None
    value = limit.get("context") if isinstance(limit, dict) else None
    return value if isinstance(value, int) and value > 0 else None


def resolve(provider, model, path=None):
    """Return the context limit for ``provider/model``, or ``None``."""
    if not model:
        return None
    try:
        with open(catalog_path(path), encoding="utf-8") as fh:
            catalog = json.load(fh)
    except (OSError, ValueError):
        return None
    if not isinstance(catalog, dict):
        return None

    models_by_provider = {
        name: entry.get("models") or {}
        for name, entry in catalog.items()
        if isinstance(entry, dict)
    }

    exact = models_by_provider.get(provider, {}).get(model)
    if exact is not None:
        return _context_tokens(exact)

    # A differently-keyed entry for the same provider is still the same model;
    # the same id under another provider can be a different deployment with a
    # different window, so it is never used as a stand-in.
    canonical = f"{provider}/{model}"
    for entry in models_by_provider.get(provider, {}).values():
        if isinstance(entry, dict) and (
            entry.get("canonical_model_id") == canonical or entry.get("id") == model
        ):
            return _context_tokens(entry)
    for models in models_by_provider.values():
        for entry in models.values():
            if isinstance(entry, dict) and entry.get("canonical_model_id") == canonical:
                return _context_tokens(entry)
    return None
