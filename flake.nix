# SPDX-License-Identifier: GPL-2.0-only
#
# flake.nix for gpu-unlock
#
# Provides:
#   nix build                         gpu_unlock.ko for linuxPackages_latest
#   nix build .#firmware              the generated firmware (fetches the
#                                     pinned NVIDIA inputs, ~340 MB)
#   nix flake check                   module build (-Werror), the
#                                     analysis gate, the firmware files
#                                     and the NixOS module tests
#                                     (nix/tests)
#   nix develop                       build/test/analysis shell
#   nix build .#analysis-quick        static analysis, see nix/analysis
#   nix build .#analysis-standard
#   nix build .#analysis-deep
#
# NixOS: import nixosModules.default and set
#
#   hardware.gpu-unlock = {
#     enable = true;
#     targets = [ "0000:41:00.0" ];   # or "all"
#   };
#
# Every package comes from one scope, nix/packages.nix. The module
# builds gpu_unlock from it for config.boot.kernelPackages, so it
# follows the system kernel rather than the one pinned here.
#
{
  description = "Unlock full FP16/BF16 tensor rate on Ampere GeForce cards";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # The unlock and its firmware are x86_64 only.
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;

      scope = pkgs.callPackage ./nix/packages.nix { };
      inherit (scope) analysis kernelModule;
    in
    {
      packages.${system} = {
        default = kernelModule;
        kernel-module = kernelModule;
        inherit (scope) firmware;
        nvidia-kernel-module-source = scope.inputs.kernelModuleSource;
        nvidia-installer = scope.inputs.installer;
      }
      // lib.mapAttrs' (name: lib.nameValuePair "analysis-${name}") (
        lib.filterAttrs (_: lib.isDerivation) analysis
      );

      checks.${system} = {
        kernel-module = kernelModule;
        analysis-gate = analysis.gate;
        firmware-files = scope.callPackage ./nix/tests/firmware-files.nix { };
        eval-tests = scope.callPackage ./nix/tests/table.nix { } "eval-tests" (
          scope.callPackage ./nix/tests/module.nix {
            inherit (nixpkgs.lib) nixosSystem;
            module = self.nixosModules.default;
          }
          ++ scope.callPackage ./nix/tests/sources.nix { }
          ++ scope.callPackage ./nix/tests/wiring.nix { }
          ++ scope.callPackage ./nix/tests/inputs.nix { }
        );
      };

      devShells.${system}.default = scope.devShell;

      nixosModules.default = ./nix/nixos-module.nix;

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
