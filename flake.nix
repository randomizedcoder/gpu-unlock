{
  description = "Ampere GPU unlock: kernel module, pinned firmware, and NixOS integration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  # nix build                        the kernel module, for nixpkgs' default kernel
  # nix build .#gpu-unlock-firmware  the NVIDIA firmware it loads
  # nixosModules.default             hardware.nvidia.gpuUnlock, see packaging/nix/README.md
  # nix flake check                  builds both, checks a built initrd, runs eval-tests
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # Only the explicitly requested firmware package needs this exception.
        config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "gpu-unlock-firmware";
      };
      kernelModule = pkgs.linuxPackages.callPackage ./packaging/nix/package.nix { };
      # Where NixOS can still build the older scripted initrd, check that too.
      testSystem = import ./packaging/nix/tests/system.nix { inherit pkgs nixpkgs; };
      hasScriptedInitrd = ((testSystem { }).options.boot.initrd.systemd.enable.type.name or null) == "bool";
    in
    {
      packages.${system} = {
        default = kernelModule;
        gpu-unlock = kernelModule;
        gpu-unlock-firmware = kernelModule.firmware;
      };

      nixosModules.default = ./packaging/nix/module.nix;
      nixosModules.gpu-unlock = self.nixosModules.default;

      checks.${system} = {
        kernel-module = kernelModule;
        firmware = kernelModule.firmware;
        nixos-integration = import ./packaging/nix/checks.nix { inherit pkgs nixpkgs; };
        eval-tests = import ./packaging/nix/tests { inherit pkgs nixpkgs kernelModule; };
      } // nixpkgs.lib.optionalAttrs hasScriptedInitrd {
        nixos-integration-scripted = import ./packaging/nix/checks.nix {
          inherit pkgs nixpkgs;
          systemdInitrd = false;
        };
      };

      formatter.${system} = pkgs.nixpkgs-fmt;
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.python3 pkgs.zstd pkgs.gnumake pkgs.gcc pkgs.git ];
      };
    };
}
