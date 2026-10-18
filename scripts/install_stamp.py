#!/usr/bin/env python3
"""Generate the ``install-stamp.json`` consumed by the Hermes Agent image.

The upstream Dockerfile copies the whole build context into ``/opt/hermes`` and
reads ``install-stamp.json`` to report provenance (``hermes --version``, the
TUI banner, and ``/etc/hermes/image-provenance.json``). Upstream CI generates
that file with ``scripts/write_install_stamp.py``; this repository only has the
upstream source checkout, so it writes the same schema directly instead of
importing upstream's packaging modules.

Schema reference:
https://github.com/NousResearch/hermes-agent/blob/main/scripts/write_install_stamp.py
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_VERSION = 2

_COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


def build_stamp(
    version: str,
    commit: str,
    commit_date: int,
    *,
    now: datetime | None = None,
) -> dict:
    """Return an install stamp for an immutable Docker image build."""
    if not version:
        raise ValueError("version must not be empty")
    if not _COMMIT_RE.fullmatch(commit):
        raise ValueError(f"commit must be a 40-character lowercase hex SHA, got {commit!r}")
    if commit_date <= 0:
        raise ValueError("commit_date must be a positive Unix timestamp")

    built_at = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    built_at = built_at.replace(microsecond=0)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "commit": commit,
        "commitDate": commit_date,
        "branch": None,
        "builtAt": built_at.isoformat().replace("+00:00", "Z"),
        "dirty": False,
        "source": "ci",
        "distribution": "docker",
        "updateMechanism": "external",
        "baseVersion": version,
        "displayVersion": version,
        "distance": 0,
        "payload": "bootstrap",
        "tag": None,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Write install-stamp.json for the Hermes Agent Docker image.",
    )
    parser.add_argument("--output", "-o", required=True, type=Path, help="output file path")
    parser.add_argument("--version", required=True, help="upstream release version, e.g. 0.22.2")
    parser.add_argument("--commit", required=True, help="upstream commit SHA (40 hex characters)")
    parser.add_argument(
        "--commit-date",
        required=True,
        type=int,
        help="upstream commit timestamp (Unix epoch seconds)",
    )
    args = parser.parse_args(argv)

    stamp = build_stamp(args.version, args.commit, args.commit_date)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(stamp, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {args.output} ({stamp['displayVersion']}, {stamp['commit'][:7]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
