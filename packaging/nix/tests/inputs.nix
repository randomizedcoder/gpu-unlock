# SPDX-License-Identifier: GPL-2.0-only
#
# Rows for the pinned NVIDIA inputs. The version, file names, URLs and
# SHA-256 are also written in the Makefile, the PKGBUILD and the RPM
# spec, so these rows check that all of them still agree, and that a
# GitHub tarball of the repo (what a github: flake input fetches) still
# holds the flake.
{ lib, firmware }:
let
  inherit (firmware) nvidiaVersion nvidiaSource nvidiaInstaller;

  inherit (builtins) readFile;
  makefile = readFile ../../../Makefile;
  pkgbuild = readFile ../../arch/PKGBUILD;
  spec = readFile ../../rpm/gpu-unlock.spec;
  gitattributes = readFile ../../../.gitattributes;

  lines = text: lib.splitString "\n" text;

  # The first capture of pattern on any line of text; throws if none.
  field = text: pattern: builtins.head (lib.findFirst (m: m != null)
    (throw "no line matches ${pattern}")
    (map (builtins.match pattern) (lines text)));

  # `NAME := value` from the Makefile, with $(NV) expanded.
  makeVar = text: name:
    builtins.replaceStrings [ "$(NV)" ] [ (field text "NV[[:space:]]*:=[[:space:]]*(.*)") ]
      (field text "${name}[[:space:]]*:=[[:space:]]*(.*)");

  # `SourceN: url` from the spec, with %{nv} expanded.
  specSource = n: builtins.replaceStrings [ "%{nv}" ] [ nvidiaVersion ]
    (field spec "Source${n}:[[:space:]]*(.*)");

  # Every whole run of lowercase hex digits that is a SHA-256, so a
  # longer run or a prefix does not count as one.
  hashesIn = text: lib.filter (run: builtins.stringLength run == 64)
    (map builtins.head (lib.filter builtins.isList (builtins.split "([0-9a-f]+)" text)));

  pinned = [ nvidiaSource.outputHash nvidiaInstaller.outputHash ];
  hasPinned = text: lib.all (hash: lib.elem hash (hashesIn text)) pinned;

  sourceHash = nvidiaSource.outputHash;
  # The same hash with its last digit changed.
  editedHash = lib.substring 0 63 sourceHash + (if lib.hasSuffix "0" sourceHash then "1" else "0");

  # What a github: flake input needs from the tarball.
  keepsFlake = text: lib.all (path: lib.elem "${path} -export-ignore" (lines text))
    [ "/flake.nix" "/flake.lock" "/packaging" ];
in
[
  {
    description = "positive: the PKGBUILD's sha256sums pin both inputs";
    actual = hasPinned pkgbuild;
    expected = true;
  }
  {
    description = "positive: the RPM spec's sha256sum -c lines pin both inputs";
    actual = hasPinned spec;
    expected = true;
  }
  {
    description = "positive: the NVIDIA version is the Makefile's NV, the PKGBUILD's _nv and the spec's nv";
    actual = [ nvidiaVersion nvidiaVersion nvidiaVersion ];
    expected = [
      (makeVar makefile "NV")
      (field pkgbuild "_nv=(.*)")
      (field spec "%global nv (.*)")
    ];
  }
  {
    description = "positive: the downloads are the Makefile's NV_SOURCE and NV_INSTALLER";
    actual = [ nvidiaSource.name nvidiaInstaller.name ];
    expected = [ "${makeVar makefile "NV_SOURCE"}.tar.xz" (makeVar makefile "NV_INSTALLER") ];
  }
  {
    description = "positive: the URLs are the spec's Source1 and Source2";
    actual = [ (lib.head nvidiaSource.urls) (lib.head nvidiaInstaller.urls) ];
    expected = [ (specSource "1") (specSource "2") ];
  }
  {
    description = "negative: a PKGBUILD with one hash digit changed";
    actual = hasPinned (builtins.replaceStrings [ sourceHash ] [ editedHash ] pkgbuild);
    expected = false;
  }
  {
    description = "negative: a Makefile with NV := 610.43.04";
    actual = makeVar (builtins.replaceStrings [ "610.43.03" ] [ "610.43.04" ] makefile) "NV";
    expected = "610.43.04";
  }
  {
    description = "negative: a Makefile without NV";
    actual = makeVar "VERSION := 1\n" "NV";
    expected = "error";
  }
  {
    description = "boundary: a 63-digit prefix of a pinned hash is not the hash";
    actual = hashesIn (lib.substring 0 63 sourceHash);
    expected = [ ];
  }
  {
    description = "boundary: a 65-digit run holding a pinned hash is not the hash";
    actual = hashesIn "${sourceHash}0";
    expected = [ ];
  }
  {
    description = "boundary: exactly 64 digits is the hash";
    actual = hashesIn "'${sourceHash}'";
    expected = [ sourceHash ];
  }
  {
    description = "corner: .gitattributes keeps the flake and packaging/nix in GitHub tarballs";
    actual = keepsFlake gitattributes;
    expected = true;
  }
  {
    description = "negative: a .gitattributes without the flake.lock line loses the flake";
    actual = keepsFlake (builtins.replaceStrings [ "/flake.lock -export-ignore" ] [ "" ] gitattributes);
    expected = false;
  }
  {
    description = "corner: .gitattributes still leaves *.bin out";
    actual = lib.elem "*.bin export-ignore" (lines gitattributes);
    expected = true;
  }
]
