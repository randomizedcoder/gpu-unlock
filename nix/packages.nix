# SPDX-License-Identifier: GPL-2.0-only
#
# nix/packages.nix
#
# Every gpu-unlock package, in one scope: callPackage there fills in
# version, sources, inputs and the pinned python3 by name. The flake and the
# NixOS module both build from it, so they cannot drift apart:
#
#   scope = pkgs.callPackage ./nix/packages.nix { };
#   scope.firmware
#   (scope.overrideScope (_: _: { kernelPackages = ...; })).kernelModule
#

{
  lib,
  newScope,
  writeShellApplication,
  linuxPackages_latest,
  python314,
}:

lib.makeScope newScope (self: {
  version = lib.fileContents ../VERSION;

  # What the module and the firmware share; each adds its description.
  baseMeta = {
    homepage = "https://github.com/Zagitta/gpu-unlock";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };

  # One source tree per build; see sources.nix.
  sources = import ./sources.nix { inherit lib; };

  # One Python for the firmware build, the tests and the dev shell.
  # The scripts themselves still run on the distributions' 3.12+.
  python3 = python314;

  # The kernel the module, the analysis and the dev shell build against.
  # The NixOS module sets it to config.boot.kernelPackages.
  kernelPackages = linuxPackages_latest;

  inputs = self.callPackage ./inputs.nix { };

  firmware = self.callPackage ./firmware.nix { src = self.sources.firmware; };

  # kernelPackages.callPackage supplies kernel and kernelModuleMakeFlags.
  kernelModule = self.kernelPackages.callPackage ./kernel-module.nix {
    inherit (self) version baseMeta;
    src = self.sources.kernel;
  };

  analysis = self.callPackage ./analysis { src = self.sources.analysis; };

  devShell = self.callPackage ./devshell.nix { };

  # The PASS/FAIL runner of every test table; see tests/table.sh.
  tableRunner = writeShellApplication {
    name = "gpu-unlock-table";
    text = builtins.readFile ./tests/table.sh;
  };
})
