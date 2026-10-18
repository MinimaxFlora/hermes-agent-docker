"""Tests for scripts/install_stamp.py."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import install_stamp  # noqa: E402

COMMIT = "0123456789abcdef0123456789abcdef01234567"
NOW = datetime(2026, 10, 18, 12, 0, 0, tzinfo=timezone.utc)


class BuildStampTests(unittest.TestCase):
    def test_builds_docker_stamp(self) -> None:
        stamp = install_stamp.build_stamp("0.22.2", COMMIT, 1760000000, now=NOW)

        self.assertEqual(stamp["schemaVersion"], 2)
        self.assertEqual(stamp["commit"], COMMIT)
        self.assertEqual(stamp["commitDate"], 1760000000)
        self.assertEqual(stamp["builtAt"], "2026-10-18T12:00:00Z")
        self.assertEqual(stamp["baseVersion"], "0.22.2")
        self.assertEqual(stamp["displayVersion"], "0.22.2")
        self.assertEqual(stamp["distribution"], "docker")
        self.assertEqual(stamp["updateMechanism"], "external")
        self.assertFalse(stamp["dirty"])
        self.assertIsNone(stamp["branch"])
        self.assertIsNone(stamp["tag"])

    def test_rejects_empty_version(self) -> None:
        with self.assertRaises(ValueError):
            install_stamp.build_stamp("", COMMIT, 1760000000)

    def test_rejects_short_commit(self) -> None:
        with self.assertRaises(ValueError):
            install_stamp.build_stamp("0.22.2", "abc123", 1760000000)

    def test_rejects_uppercase_commit(self) -> None:
        with self.assertRaises(ValueError):
            install_stamp.build_stamp("0.22.2", COMMIT.upper(), 1760000000)

    def test_rejects_non_positive_commit_date(self) -> None:
        with self.assertRaises(ValueError):
            install_stamp.build_stamp("0.22.2", COMMIT, 0)

    def test_writes_json_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "nested" / "install-stamp.json"
            exit_code = install_stamp.main(
                [
                    "--output",
                    str(output),
                    "--version",
                    "0.22.2",
                    "--commit",
                    COMMIT,
                    "--commit-date",
                    "1760000000",
                ]
            )

            self.assertEqual(exit_code, 0)
            stamp = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(stamp["commit"], COMMIT)
            self.assertEqual(stamp["displayVersion"], "0.22.2")


if __name__ == "__main__":
    unittest.main()
