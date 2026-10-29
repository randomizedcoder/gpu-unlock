{
  description = "Ampere GPU unlock: kernel module, pinned firmware, and NixOS integration";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # Only the explicitly requested firmware package needs this exception.
        config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "gpu-unlock-firmware";
      };
      module = pkgs.linuxPackages.callPackage ./packaging/nix/package.nix { };
      testSystem = import ./packaging/nix/tests/system.nix { inherit pkgs nixpkgs; };
      hasScriptedInitrd = ((testSystem { }).options.boot.initrd.systemd.enable.type.name or null) == "bool";
    in
    {
      packages.${system} = {
        default = module;
        gpu-unlock = module;
        gpu-unlock-firmware = module.firmware;
      };

      nixosModules.default = ./packaging/nix/module.nix;
      nixosModules.gpu-unlock = self.nixosModules.default;

      checks.${system} = {
        # Kbuild reads KCFLAGS from the environment. Keep -Werror out of the
        # package so new warnings on users' kernels don't fail their builds.
        kernel-module = module.overrideAttrs { env.KCFLAGS = "-Werror"; };
        firmware = module.firmware;
        nixos-integration = import ./packaging/nix/checks.nix { inherit pkgs nixpkgs; };
        eval-tests = pkgs.callPackage ./packaging/nix/tests/table.nix { } "eval-tests"
          (import ./packaging/nix/tests/module.nix { inherit pkgs nixpkgs; }
            ++ import ./packaging/nix/tests/inputs.nix { inherit (nixpkgs) lib; inherit (module) firmware; });
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
