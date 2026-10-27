# SPDX-License-Identifier: GPL-2.0-only
#
# nix/analysis/kbuild-objects.nix
#
# The objects a Kbuild text links into gpu_unlock.ko: the words of its
# `gpu_unlock-y :=` line, continuation lines included. The gate expects
# each kbuild report to have compiled this many sources.
#

{ lib }:

text:

let
  inherit (import ../make-var.nix { inherit lib; }) makeVar words;
in
lib.filter (lib.hasSuffix ".o") (words (makeVar text "gpu_unlock-y"))
