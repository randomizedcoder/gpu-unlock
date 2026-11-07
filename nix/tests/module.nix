# SPDX-License-Identifier: GPL-2.0-only
#
# nix/tests/module.nix
#
# The NixOS module, evaluated in a minimal system for each row: the
# kernel command line, initrd modules, module package and firmware it
# produces, and the settings it must refuse.
#

{
  lib,
  linuxPackages,
  nixosSystem,
  module,
  version,
}:

let
  evaluate =
    settings: extra:
    nixosSystem {
      modules = [
        module
        extra
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          system.stateVersion = lib.trivial.release;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          boot.loader.grub.enable = false;
          hardware.gpu-unlock = settings;
        }
      ];
    };

  system = settings: extra: (evaluate settings extra).config;

  params = config: lib.filter (lib.hasPrefix "gpu_unlock.") config.boot.kernelParams;

  hasPname =
    pname: packages: lib.any (package: (package.pname or "") == pname) (lib.flatten packages);

  # hardware.firmware applies compression, so look at what was defined.
  firmwareDefined =
    settings:
    hasPname "gpu-unlock-firmware" (evaluate settings { }).options.hardware.firmware.definitions;

  one = {
    enable = true;
    targets = [ "0000:41:00.0" ];
  };
in
[
  {
    description = "module, positive: one card on the command line";
    actual = params (system one { });
    expected = [ "gpu_unlock.targets=0000:41:00.0" ];
  }
  {
    description = "module, positive: all cards";
    actual = params (
      system {
        enable = true;
        targets = "all";
      } { }
    );
    expected = [ "gpu_unlock.targets=all" ];
  }
  {
    description = "module, positive: two cards, comma separated";
    actual = params (
      system {
        enable = true;
        targets = [
          "0000:41:00.0"
          "0000:42:00.0"
        ];
      } { }
    );
    expected = [ "gpu_unlock.targets=0000:41:00.0,0000:42:00.0" ];
  }
  {
    description = "module, positive: module and firmware installed, loaded in the initrd";
    actual =
      let
        config = system one { };
      in
      {
        module = hasPname "gpu-unlock" config.boot.extraModulePackages;
        firmware = firmwareDefined one;
        initrd = lib.elem "gpu_unlock" config.boot.initrd.kernelModules;
      };
    expected = {
      module = true;
      firmware = true;
      initrd = true;
    };
  }
  {
    description = "module, negative: an address without the PCI domain";
    actual = params (
      system {
        enable = true;
        targets = [ "41:00.0" ];
      } { }
    );
    expected = "error";
  }
  {
    description = "module, negative: enabled without targets";
    actual = params (system { enable = true; } { });
    expected = "error";
  }
  {
    description = "module, boundary: an empty target list";
    actual = params (
      system {
        enable = true;
        targets = [ ];
      } { }
    );
    expected = "error";
  }
  {
    description = "module, boundary: function 7, the last PCI function";
    actual = params (
      system {
        enable = true;
        targets = [ "0000:41:00.7" ];
      } { }
    );
    expected = [ "gpu_unlock.targets=0000:41:00.7" ];
  }
  {
    description = "module, boundary: function 8 does not exist";
    actual = params (
      system {
        enable = true;
        targets = [ "0000:41:00.8" ];
      } { }
    );
    expected = "error";
  }
  {
    description = "module, boundary: resume off adds resume=0";
    actual = params (system (one // { resume = false; }) { });
    expected = [
      "gpu_unlock.targets=0000:41:00.0"
      "gpu_unlock.resume=0"
    ];
  }
  {
    description = "module, corner: upper-case hex, as some tools print it";
    actual = params (
      system {
        enable = true;
        targets = [ "0000:4A:00.0" ];
      } { }
    );
    expected = [ "gpu_unlock.targets=0000:4A:00.0" ];
  }
  {
    description = "module, corner: disabled adds nothing";
    actual =
      let
        config = system { } { };
      in
      {
        params = params config;
        module = hasPname "gpu-unlock" config.boot.extraModulePackages;
        firmware = firmwareDefined { };
      };
    expected = {
      params = [ ];
      module = false;
      firmware = false;
    };
  }
  {
    description = "module, corner: loaded before nvidia when nvidia is in the initrd too";
    # Only the order of the two matters; NixOS puts dm_mod first too.
    actual =
      lib.filter (name: name == "gpu_unlock" || name == "nvidia")
        (system one { boot.initrd.kernelModules = [ "nvidia" ]; }).boot.initrd.kernelModules;
    expected = [
      "gpu_unlock"
      "nvidia"
    ];
  }
  {
    description = "module, corner: built for the system's kernel, not the flake's";
    actual =
      (system one ({ pkgs, ... }: { boot.kernelPackages = pkgs.linuxPackages; }))
      .hardware.gpu-unlock.kernelModule.version;
    expected = "${version}-${linuxPackages.kernel.version}";
  }
  {
    description = "module, corner: firmware built with the pinned Python, whatever python3 is";
    actual =
      let
        config = system one { nixpkgs.overlays = [ (_: prev: { python3 = prev.python312; }) ]; };
      in
      (lib.findFirst (
        package: package ? pythonVersion
      ) null config.hardware.gpu-unlock.firmware.nativeBuildInputs).pythonVersion;
    expected = "3.14";
  }
  # README: gpu_unlock must not be made a softdep of nvidia; it runs
  # from the initrd before nvidia instead.
  {
    description = "module, corner: no softdep on nvidia in the modprobe config";
    actual = lib.hasInfix "softdep nvidia" (system one { }).boot.extraModprobeConfig;
    expected = false;
  }
]
