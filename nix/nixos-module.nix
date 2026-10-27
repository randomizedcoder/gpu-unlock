# SPDX-License-Identifier: GPL-2.0-only
#
# nix/nixos-module.nix
#
# NixOS equivalent of the mkinitcpio/initramfs-tools/dracut drop-ins in
# packaging/boot/: build gpu_unlock for the system kernel, put it and its
# firmware in the initrd, load it there, and opt the cards in on the
# kernel command line.
#
# NixOS copies the firmware a module declares with MODULE_FIRMWARE() into
# the initrd from hardware.firmware (makeModulesClosure), so adding the
# firmware package there is enough for request_firmware() in stage 1.
#
# Ordering: gpu_unlock must run before nvidia binds the card. It is
# loaded from boot.initrd.kernelModules, and stage 1 loads that list in
# order, so it comes before nvidia when nvidia is only loaded in stage 2
# (boot.kernelModules / udev). If nvidia is also in the initrd, this
# module puts gpu_unlock in front of it with mkBefore.
#
#   hardware.gpu-unlock = {
#     enable = true;
#     targets = [ "0000:41:00.0" ];   # or "all"
#   };
#

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardware.gpu-unlock;

  # The flake's packages, built for this system's kernel.
  scope = (pkgs.callPackage ./packages.nix { }).overrideScope (
    _: _: { inherit (config.boot) kernelPackages; }
  );

  targetsParam = if cfg.targets == "all" then "all" else lib.concatStringsSep "," cfg.targets;
in
{
  options.hardware.gpu-unlock = {
    enable = lib.mkEnableOption ''
      gpu_unlock, which unlocks the full FP16/BF16 tensor issue rate on
      GA102/GA103/GA104/GA106 GeForce cards at boot, before the nvidia
      driver binds them
    '';

    targets = lib.mkOption {
      type = lib.types.either (lib.types.enum [ "all" ]) (
        lib.types.nonEmptyListOf (
          lib.types.strMatching "[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\\.[0-7]"
        )
      );
      example = [ "0000:41:00.0" ];
      description = ''
        Cards to unlock: `"all"` for every unbound supported card, or full
        PCI addresses as `lspci -D` prints them. Becomes
        `gpu_unlock.targets=` on the kernel command line.
      '';
    };

    resume = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Unlock the cards again after suspend to RAM, before nvidia resumes
        them. Sets `gpu_unlock.resume=0` when disabled.
      '';
    };

    kernelModule = lib.mkOption {
      type = lib.types.package;
      default = scope.kernelModule;
      defaultText = lib.literalExpression "gpu_unlock built for config.boot.kernelPackages";
      description = "The gpu_unlock kernel module package.";
    };

    firmware = lib.mkOption {
      type = lib.types.package;
      default = scope.firmware;
      defaultText = lib.literalExpression "the generated gpu_unlock firmware";
      description = "The generated gpu_unlock firmware package.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isx86_64;
        message = "hardware.gpu-unlock only supports x86_64-linux.";
      }
    ];

    boot = {
      extraModulePackages = [ cfg.kernelModule ];
      initrd.kernelModules = lib.mkBefore [ "gpu_unlock" ];
      kernelParams = [
        "gpu_unlock.targets=${targetsParam}"
      ]
      ++ lib.optional (!cfg.resume) "gpu_unlock.resume=0";
    };

    hardware.firmware = [ cfg.firmware ];
  };
}
