# SPDX-License-Identifier: GPL-2.0-only
"""extract_boot_assets.py on synthetic NVIDIA generated sources."""

from __future__ import annotations

import struct
import unittest
import zlib
from typing import NamedTuple

import extract_boot_assets
from table import outcome, run


def array(label: str, data: bytes, size: int | None = None,
          compressed: bytes | None = None, tokens: str | None = None) -> str:
    """One BINDATA array as the generated sources declare it."""
    stored = data if compressed is None else compressed
    lines = [f"// COMPRESSION: {'NO' if compressed is None else 'YES'}",
             f"// DATA SIZE (bytes): {len(data) if size is None else size}"]
    if compressed is not None:
        lines.append(f"// COMPRESSED SIZE (bytes): {len(stored)}")
    if tokens is None:
        tokens = ", ".join(f"0x{byte:02x}" for byte in stored)
    lines.append(f"static BINDATA_LABEL_{label}_data[] =\n{{\n    {tokens}\n}};")
    return "\n".join(lines) + "\n"


def deflate(data: bytes, crc: int | None = None, size: int | None = None) -> bytes:
    """Raw DEFLATE and the gzip CRC32/ISIZE trailer, as NVIDIA stores it."""
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    body = compressor.compress(data) + compressor.flush()
    return body + struct.pack("<II", zlib.crc32(data) if crc is None else crc,
                              len(data) if size is None else size)


DATA = bytes(range(16))
LIMIT = 16 * 1024 * 1024


class ArrayRow(NamedTuple):
    description: str
    text: str
    expected: object


ARRAY_ROWS = (
    ArrayRow("positive: an uncompressed array", array("X", DATA), DATA),
    ArrayRow("positive: a compressed array", array("X", DATA, compressed=deflate(DATA)), DATA),
    ArrayRow("negative: no such label", array("Y", DATA),
             "ValueError: missing or duplicate X"),
    ArrayRow("negative: the label twice", array("X", DATA) * 2,
             "ValueError: missing or duplicate X"),
    ArrayRow("negative: no DATA SIZE line", "static BINDATA_LABEL_X_data[] = { 0x00 };",
             "ValueError: missing storage declaration for X"),
    ArrayRow("negative: a token that is not a byte", array("X", DATA, tokens="0x00, 0x100"),
             "ValueError: non-byte token in generated array"),
    ArrayRow("negative: no closing brace",
             array("X", DATA).replace("};", ";"),
             "ValueError: malformed byte-array declaration"),
    ArrayRow("negative: DATA SIZE is not the array length", array("X", DATA, size=17),
             "ValueError: X: inflated 16 bytes, header says 17"),
    ArrayRow("negative: a wrong CRC32 in the trailer",
             array("X", DATA, compressed=deflate(DATA, crc=0)),
             "ValueError: compressed checksum or size mismatch"),
    ArrayRow("negative: a wrong ISIZE in the trailer",
             array("X", DATA, compressed=deflate(DATA, size=17)),
             "ValueError: compressed checksum or size mismatch"),
    ArrayRow("boundary: DATA SIZE 0", array("X", b"", size=0, tokens="0x00"),
             "ValueError: asset exceeds extraction limit"),
    ArrayRow("boundary: a one-byte array", array("X", b"\x7f"), b"\x7f"),
    ArrayRow("boundary: DATA SIZE 16 MiB + 1", array("X", DATA, size=LIMIT + 1),
             "ValueError: asset exceeds extraction limit"),
    ArrayRow("corner: a trailing comma and spaces around tokens",
             array("X", b"\x01\x02", tokens=" 0x01 ,\n 0x02 , "), b"\x01\x02"),
    ArrayRow("corner: a byte after the trailer",
             array("X", DATA, compressed=deflate(DATA) + b"\x00"),
             "ValueError: truncated, trailing or oversized compressed stream"),
    ArrayRow("corner: COMPRESSED SIZE is not the array length",
             array("X", DATA, compressed=deflate(DATA)).replace(
                 f"COMPRESSED SIZE (bytes): {len(deflate(DATA))}", "COMPRESSED SIZE (bytes): 1"),
             "ValueError: compressed storage size mismatch"),
)


# A Booter: code [0, 256), data [256, 768), app [768, 1024), one signature
# patched into DMEM at 256.
IMAGE = bytes(1024)
HEADER = (0, 256, 256, 512, 1, 768, 256, 0, 0)


def booter(header: tuple[int, ...] = HEADER, loc: int = 256, num_sigs: int = 1,
           sigs: int = 1, ucode: int = 2) -> str:
    return "".join((
        array("IMAGE_PROD", IMAGE),
        array("HEADER_PROD", struct.pack("<9I", *header)),
        array("SIG_PROD", bytes(384 * sigs)),
        array("PATCH_LOC", struct.pack("<I", loc)),
        array("PATCH_META", struct.pack("<3I", 0, 3, ucode)),
        array("NUM_SIGS", struct.pack("<I", num_sigs)),
    ))


def bundle_header(data: bytes) -> tuple[int, ...]:
    """Magic, version, the 14 header words and the two lengths."""
    return struct.unpack_from("<18I", data)


class BundleRow(NamedTuple):
    description: str
    text: str
    expected: object


VALID = (extract_boot_assets.MAGIC, 1, *HEADER[:7], 0, 0, 256, 2, 3, 1, 384, 1024, 384)
BUNDLE_ROWS = (
    BundleRow("positive: the bundle header", booter(), VALID),
    BundleRow("negative: no signatures", booter(num_sigs=0),
              "ValueError: unsupported production Booter signature/application table"),
    BundleRow("negative: two applications", booter(header=(*HEADER[:4], 2, *HEADER[5:])),
              "ValueError: unsupported production Booter signature/application table"),
    BundleRow("negative: a ucode id of 0", booter(ucode=0),
              "ValueError: unsupported production Booter signature/application table"),
    BundleRow("boundary: the patch below DMEM", booter(loc=255),
              "ValueError: signature patch is outside DMEM image"),
    BundleRow("boundary: the patch ending at the end of DMEM", booter(loc=768 - 384),
              (*VALID[:11], 768 - 384, *VALID[12:])),
    BundleRow("boundary: the patch one past the end of DMEM", booter(loc=768 - 383),
              "ValueError: signature patch is outside DMEM image"),
    BundleRow("corner: a transfer not 256-byte aligned",
              booter(header=(*HEADER[:5], 640, 384, 0, 0)),
              "ValueError: invalid Falcon transfer range"),
    BundleRow("corner: a short header record",
              booter().replace(array("HEADER_PROD", struct.pack("<9I", *HEADER)),
                               array("HEADER_PROD", struct.pack("<8I", *HEADER[:8]))),
              "ValueError: unexpected BooterLoad record size"),
)


class ExtractBootAssetsTest(unittest.TestCase):
    def test_array_bytes(self) -> None:
        def check(row: ArrayRow) -> object:
            return outcome(lambda: extract_boot_assets._array_bytes(row.text, "X")[0])

        run(self, ARRAY_ROWS, check)

    def test_build_bundle(self) -> None:
        def check(row: BundleRow) -> object:
            return outcome(lambda: bundle_header(extract_boot_assets.build_bundle(row.text)))

        run(self, BUNDLE_ROWS, check)

    def test_bundle_layout(self) -> None:
        data = extract_boot_assets.build_bundle(booter())
        row = BundleRow("positive: header, image, then signatures", "",
                        (8 + 14 * 4 + 8 + len(IMAGE) + 384, IMAGE, bytes(384)))
        run(self, (row,), lambda _: (len(data), data[72:72 + len(IMAGE)], data[-384:]))


if __name__ == "__main__":
    unittest.main()
