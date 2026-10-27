# SPDX-License-Identifier: GPL-2.0-only
"""fetch_artifacts.py against a stub urlopen, no network."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from typing import NamedTuple, Self
from unittest import mock

import fetch_artifacts
from table import outcome, run

ENTRY = {"filename": "input.tar.xz", "url": "https://example.invalid/input.tar.xz"}
GIB = 1024 * 1024 * 1024


class Block:
    """Reports a length without holding the bytes, for the 1 GiB limit."""

    def __init__(self, length: int) -> None:
        self.length = length

    def __len__(self) -> int:
        return self.length


class Response:
    """What urlopen returns: the final URL and the body in blocks."""

    def __init__(self, url: str, blocks: tuple[object, ...]) -> None:
        self.url = url
        self.blocks = list(blocks)

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self, size: int) -> object:
        return self.blocks.pop(0) if self.blocks else b""


class FetchRow(NamedTuple):
    description: str
    cached: bool
    offline: bool
    response: Response | None
    expected: object


ROWS = (
    FetchRow("positive: a download is written whole", False, False,
             Response(ENTRY["url"], (b"ab", b"cd")), ("abcd", 0o644, [], 1)),
    FetchRow("positive: a cached file is not fetched again", True, False, None,
             ("cached", 0o600, [], 0)),
    FetchRow("positive: a cached file is used offline", True, True, None,
             ("cached", 0o600, [], 0)),
    FetchRow("negative: offline and not cached", False, True, None,
             "FileNotFoundError: missing cached artifact: {output}/input.tar.xz"),
    FetchRow("negative: a redirect to http://", False, False,
             Response("http://example.invalid/input.tar.xz", (b"ab",)),
             "ValueError: refusing non-HTTPS redirect"),
    FetchRow("boundary: 1 GiB + 1 byte in one block is refused before it is written",
             False, False, Response(ENTRY["url"], (Block(GIB + 1),)),
             "ValueError: artifact exceeds 1 GiB download limit"),
    FetchRow("boundary: 1 GiB + 1 byte over two blocks is refused", False, False,
             Response(ENTRY["url"], (b"a", Block(GIB))),
             "ValueError: artifact exceeds 1 GiB download limit"),
    FetchRow("corner: an empty download is written", False, False,
             Response(ENTRY["url"], ()), ("", 0o644, [], 1)),
)


class FetchArtifactsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.output = Path(self.enterContext(tempfile.TemporaryDirectory())) / "inputs"

    def test_fetch(self) -> None:
        def check(row: FetchRow) -> object:
            destination = self.output / ENTRY["filename"]
            for path in self.output.glob("*") if self.output.exists() else ():
                path.unlink()
            if row.cached:
                self.output.mkdir(parents=True, exist_ok=True)
                destination.write_text("cached")
                destination.chmod(0o600)
            opener = mock.Mock(return_value=row.response)
            with mock.patch.object(fetch_artifacts.urllib.request, "urlopen", opener):
                got = outcome(lambda: fetch_artifacts.fetch(ENTRY, self.output, row.offline))
            if isinstance(got, str):
                # Nothing is left behind, not even the partial download.
                left = sorted(path.name for path in self.output.glob("*"))
                return got.replace(str(self.output), "{output}") + (f" left {left}" if left else "")
            return (destination.read_text(), destination.stat().st_mode & 0o777,
                    sorted(path.name for path in self.output.glob(".download-*")),
                    opener.call_count)

        run(self, ROWS, check)


if __name__ == "__main__":
    unittest.main()
