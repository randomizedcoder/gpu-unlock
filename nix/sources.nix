# SPDX-License-Identifier: GPL-2.0-only
#
# nix/sources.nix
#
# One source tree per build, holding only the files that build reads,
# so editing anything else (docs, packaging/, the flake, nix/) does not
# rebuild it. nix/tests/sources.nix checks what each one holds.
#

{ lib }:

let
  toSource =
    fileset:
    lib.fileset.toSource {
      root = ../.;
      inherit fileset;
    };
in
lib.mapAttrs (_: toSource) {
  kernel = ../kernel;

  # make firmware and make install-firmware.
  firmware = lib.fileset.unions [
    ../VERSION
    ../Makefile
    ../firmware
  ];

  # The analysed sources, and the flake and nix/ for nix-lint and
  # shellcheck. tests/ holds the integration runner and the CI scripts.
  analysis = lib.fileset.unions [
    ../kernel
    ../firmware
    ../tests
    ../.github/ci
    ../flake.nix
    ../nix
  ];
}
