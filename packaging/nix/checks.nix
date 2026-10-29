# SPDX-License-Identifier: GPL-2.0-only
{ pkgs, nixpkgs, systemdInitrd ? true }:
let
  testSystem = import ./tests/system.nix { inherit pkgs nixpkgs; };
  enabled = (testSystem {
    settings = { enable = true; targets = [ "0000:01:00.0" ]; };
    inherit systemdInitrd;
  }).config;
  initrd = if systemdInitrd then "systemd" else "scripted";
in
pkgs.runCommand "gpu-unlock-nixos-integration-${initrd}"
{
  nativeBuildInputs = [ pkgs.python3 pkgs.cpio pkgs.zstd pkgs.kmod ];
}
  ''
    mkdir root
    (cd root; zstd -dc ${enabled.system.build.initialRamdisk}/initrd | cpio --quiet -id --no-absolute-filenames)
    python3 ${./check-initrd.py} root ${enabled.system.build.gpuUnlock.firmware} \
      ${enabled.boot.kernelPackages.kernel.modDirVersion} \
      ${initrd}
    mkdir -p $out
    cp verified-initrd-ordering.txt $out/
    echo 'module ABI, firmware hashes and initrd ordering: PASS' > $out/result
  ''
