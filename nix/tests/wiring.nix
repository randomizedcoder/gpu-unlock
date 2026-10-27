# SPDX-License-Identifier: GPL-2.0-only
#
# nix/tests/wiring.nix
#
# The analysis and the dev shell are built from the module derivation
# rather than beside it: the kbuild reports compile the module's source
# in the module's kernel tree (without -Werror, so one warning does not
# hide the rest), and the dev shell has every analysis tool.
#

{
  lib,
  pkgs,
  kernelModule,
  analysis,
  devShell,
  firmware,
  overlay,
}:

let
  inherit (analysis) kbuildNames;

  # An attribute that is not there yet is a failed row, not an
  # evaluation error: tryEval only catches throws.
  need = drv: attr: drv.${attr} or (throw "${drv.name} has no ${attr}");
  makeFlags = drv: need drv "makeFlags";
  kdir = need kernelModule "kdir";

  perReport =
    case: description: actual: expected:
    map (name: {
      description = "wiring, ${case}: ${name} ${description}";
      actual = actual analysis.${name};
      inherit expected;
    }) kbuildNames;

  tools = [
    "sparse"
    "smatch"
    "cppcheck"
    "flawfinder"
    "perl"
    "ruff"
    "mypy"
    "shellcheck"
    "statix"
    "deadnix"
  ];
in
map (name: {
  description = "wiring, positive: the dev shell has ${name}";
  # By name: a multi-output package such as shellcheck can appear as
  # another of its outputs.
  actual = lib.elem (lib.getName pkgs.${name}) (map lib.getName devShell.nativeBuildInputs);
  expected = true;
}) tools
++ perReport "positive" "builds the module's source" (
  report: "${report.src}" == "${kernelModule.src}"
) true
++ perReport "positive" "makes in the module's kernel tree" (
  report: lib.elem kdir (makeFlags report)
) true
++ perReport "negative" "does not stop at the first warning" (
  report: lib.elem "KCFLAGS=-Werror" (makeFlags report)
) false
++ [
  {
    description = "wiring, corner: the shipped module does build with -Werror";
    actual = lib.elem "KCFLAGS=-Werror" kernelModule.makeFlags;
    expected = true;
  }
  {
    description = "wiring, positive: the dev shell's KDIR is the module's kernel tree";
    actual = need devShell "KDIR" == kdir;
    expected = true;
  }
  {
    description = "wiring, positive: the dev shell disables the module's hardening";
    actual = devShell.hardeningDisable == kernelModule.hardeningDisable;
    expected = true;
  }
  {
    description = "wiring, positive: the overlay builds the same module as the flake";
    actual = (pkgs.extend overlay).gpu-unlock.kernelModule.drvPath == kernelModule.drvPath;
    expected = true;
  }
  {
    description = "wiring, positive: the NVIDIA installer is reachable from the firmware";
    actual = lib.hasSuffix ".run" (need firmware "inputs").installer.name;
    expected = true;
  }
  {
    description = "wiring, positive: the gate expects every object Kbuild links";
    actual = builtins.length analysis.moduleObjects;
    expected = 10;
  }
  {
    description = "wiring, positive: the objects are read across continuation lines";
    actual = analysis.kbuildObjects "gpu_unlock-y := a.o \\\n\tb.o c.o\n";
    expected = [
      "a.o"
      "b.o"
      "c.o"
    ];
  }
  {
    description = "wiring, negative: one object removed from Kbuild gives one fewer";
    actual = builtins.length (
      analysis.kbuildObjects (
        builtins.replaceStrings [ " falcon.o" ] [ "" ] (builtins.readFile ../../kernel/gpu_unlock/Kbuild)
      )
    );
    expected = 9;
  }
  {
    description = "wiring, negative: a Kbuild without gpu_unlock-y";
    actual = analysis.kbuildObjects "obj-m += gpu_unlock.o\n";
    expected = "error";
  }
  {
    description = "wiring, boundary: a single object";
    actual = analysis.kbuildObjects "gpu_unlock-y := main.o";
    expected = [ "main.o" ];
  }
  {
    description = "wiring, corner: obj-m and other words are not objects of gpu_unlock";
    actual = analysis.kbuildObjects "obj-m += x.o\ngpu_unlock-y := main.o\nccflags-y := -DX\n";
    expected = [ "main.o" ];
  }
]
