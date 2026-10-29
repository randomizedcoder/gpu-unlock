# SPDX-License-Identifier: GPL-2.0-only
#
# The eval-tests check: every table of rows, run by table.nix.
{ pkgs, nixpkgs, kernelModule }:
pkgs.callPackage ./table.nix { } "eval-tests" (
  import ./module.nix { inherit pkgs nixpkgs; }
  ++ import ./inputs.nix { inherit (nixpkgs) lib; inherit (kernelModule) firmware; }
  ++ import ./sources.nix { inherit kernelModule; }
)
