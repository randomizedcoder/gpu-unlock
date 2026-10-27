# SPDX-License-Identifier: GPL-2.0-only
#
# nix/tests/inputs.nix
#
# Rows for checks.eval-tests: the NVIDIA version, the input file names,
# URLs and SHA-256 are written in several places upstream (Makefile,
# PKGBUILD, RPM spec). nix/inputs.nix is one more, so these rows check
# that all of them still agree, and that a GitHub tarball of the repo
# (what a github: flake input fetches) still holds the flake.
#

{ lib, fetchurl }:

let
  inputs = import ../inputs.nix { inherit fetchurl; };
  inherit (inputs) kernelModuleSource installer;

  read = path: builtins.readFile path;
  makefile = read ../../Makefile;
  pkgbuild = read ../../packaging/arch/PKGBUILD;
  spec = read ../../packaging/rpm/gpu-unlock.spec;
  gitattributes = read ../../.gitattributes;

  lines = text: lib.splitString "\n" text;

  # Every whole run of lowercase hex digits that is a SHA-256, so a
  # longer run or a prefix does not count as one.
  hashesIn =
    text:
    lib.filter (run: builtins.stringLength run == 64) (
      map builtins.head (lib.filter builtins.isList (builtins.split "([0-9a-f]+)" text))
    );

  # `NAME := value` from a Makefile text, as written.
  makeRaw =
    text: name:
    builtins.head (
      lib.findFirst (m: m != null) (throw "Makefile has no ${name}") (
        map (builtins.match "${name}[[:space:]]*:=[[:space:]]*(.*)") (lines text)
      )
    );

  # The same with $(NV) expanded.
  makeVar =
    text: name: builtins.replaceStrings [ "$(NV)" ] [ (makeRaw text "NV") ] (makeRaw text name);

  # `SourceN: url` from the spec, with %{nv} expanded.
  specSource =
    n:
    let
      found = lib.findFirst (m: m != null) (throw "spec has no Source${n}") (
        map (builtins.match "Source${n}:[[:space:]]*(.*)") (lines spec)
      );
    in
    builtins.replaceStrings [ "%{nv}" ] [ inputs.nvVersion ] (builtins.head found);

  pinned = [
    kernelModuleSource.outputHash
    installer.outputHash
  ];

  hasPinned = text: lib.all (hash: lib.elem hash (hashesIn text)) pinned;

  sourceHash = kernelModuleSource.outputHash;
  # The same hash with its last digit changed.
  editedHash = lib.substring 0 63 sourceHash + (if lib.hasSuffix "0" sourceHash then "1" else "0");

  attribute = line: lib.elem line (lines gitattributes);
in
[
  {
    description = "inputs, positive: the PKGBUILD's sha256sums pin both inputs";
    expected = true;
    actual = hasPinned pkgbuild;
  }
  {
    description = "inputs, positive: the RPM spec's sha256sum -c lines pin both inputs";
    expected = true;
    actual = hasPinned spec;
  }
  {
    description = "inputs, positive: nvVersion is the Makefile's NV";
    expected = makeVar makefile "NV";
    actual = inputs.nvVersion;
  }
  {
    description = "inputs, positive: the source tarball is the Makefile's NV_SOURCE";
    expected = "${makeVar makefile "NV_SOURCE"}.tar.xz";
    actual = kernelModuleSource.name;
  }
  {
    description = "inputs, positive: the installer is the Makefile's NV_INSTALLER";
    expected = makeVar makefile "NV_INSTALLER";
    actual = installer.name;
  }
  {
    description = "inputs, positive: the URLs are the spec's Source1 and Source2";
    expected = [
      (specSource "1")
      (specSource "2")
    ];
    actual = [
      (lib.head kernelModuleSource.urls)
      (lib.head installer.urls)
    ];
  }
  {
    description = "inputs, negative: a PKGBUILD with one hash digit changed";
    expected = false;
    actual = hasPinned (builtins.replaceStrings [ sourceHash ] [ editedHash ] pkgbuild);
  }
  {
    description = "inputs, negative: a Makefile with NV := 610.43.04";
    expected = "610.43.04";
    actual = makeVar (builtins.replaceStrings [ "610.43.03" ] [ "610.43.04" ] makefile) "NV";
  }
  {
    description = "inputs, negative: a Makefile without NV";
    expected = "error";
    actual = makeVar "VERSION := 1\n" "NV";
  }
  {
    description = "inputs, boundary: a 63-digit prefix of a pinned hash is not the hash";
    expected = [ ];
    actual = hashesIn (lib.substring 0 63 sourceHash);
  }
  {
    description = "inputs, boundary: a 65-digit run holding a pinned hash is not the hash";
    expected = [ ];
    actual = hashesIn "${sourceHash}0";
  }
  {
    description = "inputs, boundary: exactly 64 digits is the hash";
    expected = [ sourceHash ];
    actual = hashesIn "'${sourceHash}'";
  }
  {
    description = "inputs, corner: .gitattributes keeps the flake in GitHub tarballs";
    expected = true;
    actual = lib.all attribute [
      "/flake.nix -export-ignore"
      "/flake.lock -export-ignore"
      "/nix -export-ignore"
    ];
  }
  {
    description = "inputs, corner: .gitattributes still leaves *.bin out";
    expected = true;
    actual = attribute "*.bin export-ignore";
  }
]
