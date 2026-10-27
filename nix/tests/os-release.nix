# SPDX-License-Identifier: GPL-2.0-only
#
# nix/tests/os-release.nix
#
# checks.os-release: .github/ci/os-release.sh as a table, each row run
# under dash (Debian and Ubuntu /bin/sh), bash (Fedora, Arch) and
# busybox sh. Each row writes an os-release file, asks for one key and
# compares what is printed; "fails" when the script exits non-zero.
#

{
  lib,
  runCommand,
  writeShellApplication,
  bash,
  busybox,
  coreutils,
  dash,
  gnused,
}:

let
  script = ../../.github/ci/os-release.sh;

  # description, key, os-release text (null: no file), expected.
  cases = [
    [
      "positive: unquoted ID"
      "ID"
      "ID=debian\n"
      "debian"
    ]
    [
      "positive: double-quoted ID"
      "ID"
      "NAME=\"Fedora Linux\"\nID=\"fedora\"\n"
      "fedora"
    ]
    [
      "positive: single-quoted ID"
      "ID"
      "ID='arch'\n"
      "arch"
    ]
    [
      "positive: VERSION_ID, as module.sh asks on Ubuntu"
      "VERSION_ID"
      "ID=ubuntu\nVERSION_ID=\"24.04\"\n"
      "24.04"
    ]
    [
      "negative: ID_LIKE is not ID"
      "ID"
      "ID_LIKE=debian\nID=ubuntu\n"
      "ubuntu"
    ]
    [
      "negative: a commented-out ID is ignored"
      "ID"
      "#ID=debian\nID=arch\n"
      "arch"
    ]
    [
      "negative: VERSION_ID is not ID"
      "ID"
      "VERSION_ID=12\n"
      "linux"
    ]
    [
      "boundary: no ID defaults to linux, as os-release(5)"
      "ID"
      "NAME=Linux\n"
      "linux"
    ]
    [
      "boundary: an empty file defaults to linux"
      "ID"
      ""
      "linux"
    ]
    [
      "boundary: no VERSION_ID prints nothing"
      "VERSION_ID"
      "ID=arch\n"
      ""
    ]
    [
      "corner: the last ID wins, as when sourced"
      "ID"
      "ID=debian\nID=ubuntu\n"
      "ubuntu"
    ]
    [
      "corner: no trailing newline"
      "ID"
      "ID=fedora"
      "fedora"
    ]
    [
      "corner: shell in a value is printed, not run"
      "ID"
      "ID=\"$(touch pwned)\"\n"
      "$(touch pwned)"
    ]
    [
      "corner: a missing file fails"
      "ID"
      null
      "fails"
    ]
  ];

  shells = {
    dash = "${dash}/bin/dash";
    bash = "${bash}/bin/bash";
    busybox = "${busybox}/bin/busybox sh";
  };

  table = writeShellApplication {
    name = "gpu-unlock-table";
    text = builtins.readFile ./table.sh;
  };

  runCase =
    shell: run: c:
    let
      description = builtins.elemAt c 0;
      key = builtins.elemAt c 1;
      text = builtins.elemAt c 2;
      expected = builtins.elemAt c 3;
      file = if text == null then "does-not-exist" else "os-release";
    in
    ''
      rm -f os-release
      ${lib.optionalString (text != null) "printf '%s' ${lib.escapeShellArg text} > os-release"}
      got=$(${run} ${script} ${key} ${file}) || got=fails
      row ${lib.escapeShellArg "os-release.sh, ${shell}, ${description}"} \
        ${lib.escapeShellArg expected} "$got"
    '';

  rows = writeShellApplication {
    name = "gpu-unlock-os-release-rows";
    # The row texts hold $(...) on purpose, as text.
    excludeShellChecks = [ "SC2016" ];
    runtimeInputs = [
      coreutils
      gnused
    ];
    text = ''
      row() { printf '%s\x1f%s\x1f%s\n' "$1" "$2" "$3"; }
      ${lib.concatStrings (
        lib.mapAttrsToList (shell: run: lib.concatMapStrings (runCase shell run) cases) shells
      )}
      row "os-release.sh, corner: nothing in a value ran" no "$([[ -e pwned ]] && echo yes || echo no)"
    '';
  };
in
runCommand "gpu-unlock-os-release"
  {
    nativeBuildInputs = [
      table
      rows
    ];
  }
  ''
    gpu-unlock-os-release-rows > rows 2> /dev/null
    mkdir -p $out
    set -o pipefail
    gpu-unlock-table os-release rows | tee $out/results.txt
  ''
