# SPDX-License-Identifier: GPL-2.0-only
#
# Rows for the NixOS module, each evaluated in a minimal system: the
# kernel command line, the initrd and packages it produces, and the
# settings it must refuse ("error" from the option type, or the messages
# of its assertions).
{ pkgs, nixpkgs }:
let
  lib = nixpkgs.lib;

  testSystem = import ./system.nix { inherit pkgs nixpkgs; };
  evaluate = settings: extra: testSystem { inherit settings extra; };
  system = settings: extra: (evaluate settings extra).config;

  params = config: lib.filter (lib.hasPrefix "gpu_unlock.") config.boot.kernelParams;
  ownWarnings = config: lib.filter (lib.hasPrefix "hardware.nvidia.gpuUnlock") config.warnings;
  # The messages of the assertions that fail.
  refusals = config: map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);

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
  # Only the driver's version matters to the module.
  driver = version: { hardware.nvidia.package = pkgs.emptyDirectory // { inherit version; }; };
  one = targets [ "0000:01:00.0" ];
in
[
  {
    description = "positive: one card on the command line";
    actual = params (system one { });
    expected = [ "gpu_unlock.targets=0000:01:00.0" ];
  }
  {
    description = "positive: all cards";
    actual = params (system (targets [ "all" ]) { });
    expected = [ "gpu_unlock.targets=all" ];
  }
  {
    description = "positive: two cards, comma separated";
    actual = params (system (targets [ "0000:01:00.0" "0000:02:00.0" ]) { });
    expected = [ "gpu_unlock.targets=0000:01:00.0,0000:02:00.0" ];
  }
  {
    description = "positive: enabled installs the module and firmware, and loads it in the initrd";
    actual = installed one;
    expected = {
      params = [ "gpu_unlock.targets=0000:01:00.0" ];
      module = true;
      firmware = true;
      initrdModule = true;
      initrdUnit = true;
    };
  }
  {
    description = "positive: one card passes the assertions";
    actual = refusals (system one { });
    expected = [ ];
  }
  {
    description = "negative: enabled without targets";
    actual = refusals (system (targets [ ]) { });
    expected = [ "hardware.nvidia.gpuUnlock.targets is empty: list the cards' PCI addresses, or all." ];
  }
  {
    description = "negative: all together with an address";
    actual = refusals (system (targets [ "all" "0000:01:00.0" ]) { });
    expected = [ "hardware.nvidia.gpuUnlock.targets: all already means every card, so it must be the only entry." ];
  }
  {
    description = "negative: an address without the PCI domain";
    actual = params (system (targets [ "01:00.0" ]) { });
    expected = "error";
  }
  {
    description = "boundary: function 7, the last PCI function";
    actual = params (system (targets [ "0000:01:00.7" ]) { });
    expected = [ "gpu_unlock.targets=0000:01:00.7" ];
  }
  {
    description = "boundary: function 8 does not exist";
    actual = params (system (targets [ "0000:01:00.8" ]) { });
    expected = "error";
  }
  # The kernel module unlocks again after resume unless told not to.
  {
    description = "positive: resume left to the kernel module's default";
    actual = params (system (one // { resume = true; }) { });
    expected = [ "gpu_unlock.targets=0000:01:00.0" ];
  }
  {
    description = "negative: resume off adds resume=0";
    actual = params (system (one // { resume = false; }) { });
    expected = [ "gpu_unlock.targets=0000:01:00.0" "gpu_unlock.resume=0" ];
  }
  {
    description = "corner: resume is on unless set";
    actual = (system one { }).hardware.nvidia.gpuUnlock.resume;
    expected = true;
  }
  # nvidia must use its kernel suspend notifiers, or the card is resumed
  # before gpu_unlock can unlock it again.
  {
    description = "negative: resume without nvidia power management warns";
    actual = builtins.length (ownWarnings (system one { }));
    expected = 1;
  }
  {
    description = "positive: resume with nvidia power management does not warn";
    actual = ownWarnings (system one { hardware.nvidia.powerManagement.enable = true; });
    expected = [ ];
  }
  # UseKernelSuspendNotifiers defaults to 1 from 615.71.09 (nv-reg.h).
  {
    description = "boundary: resume on the last driver whose notifiers are off warns";
    actual = builtins.length (ownWarnings (system one (driver "610.57.04")));
    expected = 1;
  }
  {
    description = "boundary: resume on the first driver whose notifiers are on does not warn";
    actual = ownWarnings (system one (driver "615.71.09"));
    expected = [ ];
  }
  {
    description = "positive: resume on a later driver does not warn";
    actual = ownWarnings (system one (driver "615.78.08"));
    expected = [ ];
  }
  {
    description = "corner: resume off does not warn";
    actual = ownWarnings (system (one // { resume = false; }) { });
    expected = [ ];
  }
  {
    description = "corner: upper-case hex, as some tools print it";
    actual = params (system (targets [ "0000:4A:00.0" ]) { });
    expected = [ "gpu_unlock.targets=0000:4A:00.0" ];
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
