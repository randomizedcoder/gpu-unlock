# SPDX-License-Identifier: GPL-2.0-only
#
# A minimal NixOS system with the gpu-unlock module, for the checks.
# settings is hardware.nvidia.gpuUnlock, and extra is any other NixOS
# configuration the check needs.
{ pkgs, nixpkgs }:
{ settings ? { }, systemdInitrd ? true, extra ? { } }:
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    ../module.nix
    extra
    ({ options, ... }: {
      nixpkgs.pkgs = pkgs;
      system.stateVersion = "26.05";
      boot.loader.grub.enable = false;
      fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
      hardware.cpu.intel.updateMicrocode = false;
      hardware.cpu.amd.updateMicrocode = false;
      hardware.nvidia.gpuUnlock = settings;
      # Releases without the scripted initrd have no toggle to set.
      boot.initrd.systemd = nixpkgs.lib.optionalAttrs
        ((options.boot.initrd.systemd.enable.type.name or null) == "bool")
        { enable = systemdInitrd; };
    })
  ];
}
