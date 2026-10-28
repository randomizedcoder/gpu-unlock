# SPDX-License-Identifier: GPL-2.0-only
"""Table-driven tests: each row has a description and an expected value.

Each row prints as the Nix tables and the analysis gate do:

  PASS  script, description  (expected X, got Y)
"""

from __future__ import annotations

import unittest
import zlib
from collections.abc import Callable, Iterable
from typing import Protocol


class Row(Protocol):
    @property
    def description(self) -> str: ...

    @property
    def expected(self) -> object: ...


def outcome(call: Callable[[], object]) -> object:
    """What call returns, or the message of the error it raises.

    The errors are those the scripts' main() reports: OSError, ValueError
    and zlib.error.
    """
    try:
        return call()
    except (OSError, ValueError, zlib.error) as error:
        return f"{type(error).__name__}: {error}"


def run[R: Row](case: unittest.TestCase, rows: Iterable[R],
               check: Callable[[R], object]) -> None:
    script = type(case).__module__.removeprefix("test_")
    for row in rows:
        with case.subTest(row.description):
            got = check(row)
            verdict = "PASS" if got == row.expected else "FAIL"
            print(f"{verdict}  {script}, {row.description}  (expected {row.expected!r}, got {got!r})")
            case.assertEqual(got, row.expected)
