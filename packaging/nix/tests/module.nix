# SPDX-License-Identifier: GPL-2.0-only
#
# Rows for the NixOS module, each evaluated in a minimal system: the
# kernel command line, the initrd and packages it produces, and the
# settings it must refuse ("error" from the option type, or false from
# its assertions).
{ pkgs, nixpkgs }:
let
  lib = nixpkgs.lib;

  evaluate = settings: extra: nixpkgs.lib.nixosSystem {
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
        boot.initrd.systemd = lib.optionalAttrs
          ((options.boot.initrd.systemd.enable.type.name or null) == "bool")
          { enable = true; };
      })
    ];
  };
  system = settings: extra: (evaluate settings extra).config;

  params = config: lib.filter (lib.hasPrefix "gpu_unlock.") config.boot.kernelParams;
  accepted = config: builtins.all (a: a.assertion) config.assertions;

  # What the module puts in the system, enabled or not.
  # hardware.firmware compresses its packages, so look at what was defined.
  installed = settings:
    let
      eval = evaluate settings { };
      inherit (eval) config;
    in
    {
      params = params config;
      module = lib.any (p: (p.pname or "") == "gpu-unlock") config.boot.extraModulePackages;
      firmware = lib.any (p: (p.pname or "") == "gpu-unlock-firmware")
        (lib.flatten (map (d: d.value) eval.options.hardware.firmware.definitionsWithLocations));
      initrdModule = lib.elem "gpu_unlock" config.boot.initrd.kernelModules;
      initrdUnit = config.boot.initrd.systemd.services ? gpu-unlock;
    };

  targets = list: { enable = true; targets = list; };
  one = targets [ "0000:01:00.0" ];
in
[
  {
    description = "positive: one card on the command line";
    actual = params (system one { });
    expected = [ "gpu_unlock.targets=0000:01:00.0" "gpu_unlock.resume=0" ];
  }
  {
    description = "positive: all cards";
    actual = params (system (targets [ "all" ]) { });
    expected = [ "gpu_unlock.targets=all" "gpu_unlock.resume=0" ];
  }
  {
    description = "positive: two cards, comma separated";
    actual = params (system (targets [ "0000:01:00.0" "0000:02:00.0" ]) { });
    expected = [ "gpu_unlock.targets=0000:01:00.0,0000:02:00.0" "gpu_unlock.resume=0" ];
  }
  {
    description = "positive: enabled installs the module and firmware, and loads it in the initrd";
    actual = installed one;
    expected = {
      params = [ "gpu_unlock.targets=0000:01:00.0" "gpu_unlock.resume=0" ];
      module = true;
      firmware = true;
      initrdModule = true;
      initrdUnit = true;
    };
  }
  {
    description = "positive: one card passes the assertions";
    actual = accepted (system one { });
    expected = true;
  }
  {
    description = "negative: enabled without targets";
    actual = accepted (system (targets [ ]) { });
    expected = false;
  }
  {
    description = "negative: all together with an address";
    actual = accepted (system (targets [ "all" "0000:01:00.0" ]) { });
    expected = false;
  }
  {
    description = "negative: an address without the PCI domain";
    actual = params (system (targets [ "01:00.0" ]) { });
    expected = "error";
  }
  {
    description = "boundary: function 7, the last PCI function";
    actual = params (system (targets [ "0000:01:00.7" ]) { });
    expected = [ "gpu_unlock.targets=0000:01:00.7" "gpu_unlock.resume=0" ];
  }
  {
    description = "boundary: function 8 does not exist";
    actual = params (system (targets [ "0000:01:00.8" ]) { });
    expected = "error";
  }
  {
    description = "corner: upper-case hex, as some tools print it";
    actual = params (system (targets [ "0000:4A:00.0" ]) { });
    expected = [ "gpu_unlock.targets=0000:4A:00.0" "gpu_unlock.resume=0" ];
  }
  {
    description = "corner: disabled adds nothing";
    actual = installed { };
    expected = {
      params = [ ];
      module = false;
      firmware = false;
      initrdModule = false;
      initrdUnit = false;
    };
  }
  # boot.initrd.kernelModules is a set, listed by name, so mkBefore does
  # not order it: gpu_unlock comes before nvidia because g sorts before
  # n. In a systemd initrd the unit below orders it instead.
  {
    description = "corner: listed before nvidia when nvidia is in the initrd too";
    actual = lib.filter (name: name == "gpu_unlock" || name == "nvidia")
      (system one { boot.initrd.kernelModules = [ "nvidia" ]; }).boot.initrd.kernelModules;
    expected = [ "gpu_unlock" "nvidia" ];
  }
  {
    description = "corner: the systemd initrd unit runs before modules-load and udev";
    actual = (system one { }).boot.initrd.systemd.services.gpu-unlock.before;
    expected = [ "systemd-modules-load.service" "systemd-udevd.service" "systemd-udev-trigger.service" ];
  }
  {
    description = "corner: built for the system's kernel, not the flake's";
    actual = (system one { boot.kernelPackages = pkgs.linuxPackages_latest; }).system.build.gpuUnlock.kernelVersion;
    expected = pkgs.linuxPackages_latest.kernel.modDirVersion;
  }
  # README: gpu_unlock must not be made a softdep of nvidia.
  {
    description = "corner: no softdep on nvidia in the modprobe config";
    actual = lib.hasInfix "softdep nvidia" (system one { }).boot.extraModprobeConfig;
    expected = false;
  }
]
