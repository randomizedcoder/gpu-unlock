# SPDX-License-Identifier: GPL-2.0-only
#
# nix/devshell.nix
#
# `nix develop`: everything `make` and the analysis tools need, with
# KDIR pointing at the Nix kernel's build tree so
#
#   make -C kernel/gpu_unlock            # builds gpu_unlock.ko
#   make inputs firmware                 # generates the firmware
#
# work as on the distributions the Makefile targets. The module's build
# inputs and every analysis tool come from those derivations and
# scripts, so the shell has what they use.
#

{
  lib,
  mkShell,
  python3,
  kernelPackages,
  kernelModule,
  analysis,
  git,
  pciutils,
  kmod,
  nixfmt,
  zstd,
  xz,
}:

let
  inherit (kernelPackages) kernel;
in
mkShell {
  name = "gpu-unlock";

  # The kbuild reports build in the module's derivation with their
  # checkers added; the source reports run their tools from a script.
  inputsFrom = [ kernelModule ] ++ lib.attrValues analysis.reports;

  # What `make inputs firmware` and the hardware need.
  packages = [
    python3
    git
    pciutils
    kmod
    nixfmt
    zstd
    xz
  ]
  ++ lib.concatMap (report: report.runtimeInputs or [ ]) (lib.attrValues analysis.reports);

  inherit (kernelModule) hardeningDisable;

  KDIR = kernelModule.kdir;
  CHECKPATCH = "${kernelModule.ksrc}/scripts/checkpatch.pl";

  shellHook = ''
    echo "gpu-unlock dev shell: linux ${kernel.version} (KDIR=$KDIR)"
    echo "  make -C kernel/gpu_unlock                 build the module"
    echo "  make -C kernel/gpu_unlock C=2 CHECK=sparse   sparse"
    echo "  perl \$CHECKPATCH --no-tree -f kernel/gpu_unlock/*.[ch]"
    echo "  make inputs firmware                      generate the firmware"
    echo "  nix build .#analysis-standard             all reports"
    # uname is stubbed to the build kernel here, so ask /proc.
    running=$(cat /proc/sys/kernel/osrelease)
    if [ "$running" != "${kernel.modDirVersion}" ]; then
      echo "  note: running kernel is $running; this .ko targets ${kernel.modDirVersion}"
      echo "        (the NixOS module builds for config.boot.kernelPackages)"
    fi
  '';
}
