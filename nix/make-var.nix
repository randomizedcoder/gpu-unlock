# SPDX-License-Identifier: GPL-2.0-only
#
# nix/make-var.nix
#
# Reads `NAME := value` lines of a Makefile or Kbuild text, for the
# rows that check the flake against them.
#
#   makeVar text name   the value, continuation lines joined and tabs
#                       read as spaces; throws if there is no such line
#   words value         the value split on spaces
#

{ lib }:

let
  joined = text: builtins.replaceStrings [ "\\\n" "\t" ] [ " " " " ] text;
in
{
  makeVar =
    text: name:
    builtins.head (
      lib.findFirst (m: m != null) (throw "no ${name} := line") (
        map (builtins.match "${name}[[:space:]]*:=[[:space:]]*(.*)") (lib.splitString "\n" (joined text))
      )
    );

  words = value: lib.filter (word: word != "") (lib.splitString " " value);
}
