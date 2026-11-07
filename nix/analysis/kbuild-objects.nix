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
  joined = builtins.replaceStrings [ "\\\n" ] [ " " ] text;
  objects = lib.findFirst (m: m != null) (throw "Kbuild has no gpu_unlock-y") (
    map (builtins.match "gpu_unlock-y[[:space:]]*:=(.*)") (lib.splitString "\n" joined)
  );
in
lib.filter (word: lib.hasSuffix ".o" word) (
  lib.splitString " " (builtins.replaceStrings [ "\t" ] [ " " ] (builtins.head objects))
)
