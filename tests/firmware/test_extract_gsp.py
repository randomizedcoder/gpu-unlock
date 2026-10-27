# SPDX-License-Identifier: GPL-2.0-only
"""extract_gsp.py on synthetic makeself installers, no NVIDIA download."""

from __future__ import annotations

import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path
from typing import NamedTuple

import extract_gsp
from table import outcome, run

WANTED = (*extract_gsp.FIRMWARE, extract_gsp.NOTICE)
LIMIT = 128 * 1024 * 1024


def header(version: str = extract_gsp.VERSION, skip: int | None = 5, pad: int = 0) -> bytes:
    """A makeself shell header; the payload starts after skip - 1 lines."""
    lines = [b"#!/bin/sh", b"#" * pad]
    lines.append(f"version_string={version}".encode())
    if skip is not None:
        lines.append(f"skip={skip}".encode())
    return b"\n".join(lines) + b"\n"


class Member(NamedTuple):
    name: str
    size: int = 4
    kind: bytes = tarfile.REGTYPE


def payload(members: tuple[Member, ...]) -> bytes:
    """A zstd-compressed tar of members; data is zeros, from /dev/zero."""
    with tempfile.TemporaryFile() as compressed:
        with subprocess.Popen(["zstd", "-qc"], stdin=subprocess.PIPE,
                              stdout=compressed) as zstd:
            assert zstd.stdin is not None
            with tarfile.open(fileobj=zstd.stdin, mode="w|") as archive, \
                    open("/dev/zero", "rb") as zeros:
                for member in members:
                    info = tarfile.TarInfo(member.name)
                    info.type = member.kind
                    info.size = member.size if member.kind == tarfile.REGTYPE else 0
                    archive.addfile(info, zeros if info.size else None)
            zstd.stdin.close()
        compressed.seek(0)
        return compressed.read()


def installer(directory: Path, head: bytes, members: tuple[Member, ...]) -> Path:
    path = directory / "installer.run"
    path.write_bytes(head + payload(members))
    return path


class OffsetRow(NamedTuple):
    description: str
    head: bytes
    expected: object


OFFSET_ROWS = (
    OffsetRow("positive: the payload starts after skip - 1 lines", header(skip=5),
              len(header(skip=5))),
    OffsetRow("negative: another driver version",
              header(version="610.43.04"),
              "ValueError: installer version is 610.43.04, expected 610.43.03"),
    OffsetRow("negative: no skip= line", header(skip=None),
              "ValueError: not an NVIDIA makeself installer"),
    OffsetRow("boundary: skip one past the header's lines", header(skip=6),
              "ValueError: installer header is shorter than its skip count"),
    OffsetRow("corner: the header past the 1 MiB read window",
              header(pad=extract_gsp.HEADER_BYTES),
              "ValueError: not an NVIDIA makeself installer"),
)


class MembersRow(NamedTuple):
    description: str
    members: tuple[Member, ...]
    expected: object


VALID = tuple(Member(name) for name in WANTED)
MEMBERS_ROWS = (
    MembersRow("positive: the three members, in any order",
               (Member("other"), *reversed(VALID)), {name: 4 for name in WANTED}),
    MembersRow("negative: a member missing", VALID[1:],
               f"ValueError: missing installer member: {WANTED[0]}"),
    MembersRow("negative: a member twice", (*VALID, VALID[0]),
               f"ValueError: duplicate installer member: {WANTED[0]}"),
    MembersRow("negative: a member that is a directory",
               (Member(WANTED[0], kind=tarfile.DIRTYPE), *VALID[1:]),
               f"ValueError: not a regular file in installer: {WANTED[0]}"),
    MembersRow("boundary: a member of exactly 128 MiB",
               (Member(WANTED[0], LIMIT), *VALID[1:]),
               {WANTED[0]: LIMIT, WANTED[1]: 4, WANTED[2]: 4}),
    MembersRow("boundary: a member of 128 MiB + 1",
               (Member(WANTED[0], LIMIT + 1), *VALID[1:]),
               f"ValueError: not a regular file in installer: {WANTED[0]}"),
)


def zstd(data: bytes) -> bytes:
    return subprocess.run(["zstd", "-qc"], input=data, stdout=subprocess.PIPE,
                          check=True).stdout


class PayloadRow(NamedTuple):
    description: str
    payload: bytes
    expected: object


NOT_TAR = "ValueError: installer payload is not a zstd tar archive"
PAYLOAD_ROWS = (
    PayloadRow("corner: a payload zstd cannot read", b"not zstd", NOT_TAR),
    PayloadRow("corner: a zstd payload that is not a tar", zstd(b"not a tar"), NOT_TAR),
)


class ExtractGspTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(self.enterContext(tempfile.TemporaryDirectory()))

    def test_payload_offset(self) -> None:
        def check(row: OffsetRow) -> object:
            path = self.directory / "header"
            path.write_bytes(row.head)
            return outcome(lambda: extract_gsp.payload_offset(path))

        run(self, OFFSET_ROWS, check)

    def test_extract_members(self) -> None:
        def check(row: MembersRow) -> object:
            path = installer(self.directory, header(), row.members)

            def sizes() -> dict[str, int]:
                members = extract_gsp.extract_members(path, WANTED)
                return {name: len(data) for name, data in members.items()}

            return outcome(sizes)

        run(self, MEMBERS_ROWS, check)

    def test_unreadable_payload(self) -> None:
        def check(row: PayloadRow) -> object:
            path = self.directory / "installer.run"
            path.write_bytes(header() + row.payload)
            return outcome(lambda: extract_gsp.extract_members(path, WANTED))

        run(self, PAYLOAD_ROWS, check)


if __name__ == "__main__":
    unittest.main()
