# SPDX-License-Identifier: GPL-2.0-only
#
# nix/kernel-module.nix
#
# Builds gpu_unlock.ko against a NixOS kernel. Call it from a
# linuxPackages scope so `kernel` and `kernelModuleMakeFlags` match the
# running system:
#
#   config.boot.kernelPackages.callPackage ./nix/kernel-module.nix {
#     inherit src version;
#   };
#
# nix/packages.nix does this. The analysis reuses the derivation for its
# kbuild reports: werror = false and extraMakeFlags via .override (see
# nix/analysis/kbuild.nix), and kdir/ksrc from passthru.
#

{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  src,
  version,
  baseMeta,
  werror ? true,
  extraMakeFlags ? [ ],
}:

let
  modules = "${kernel.dev}/lib/modules/${kernel.modDirVersion}";
  # The kernel build tree, for make -C.
  kdir = "${modules}/build";
in
stdenv.mkDerivation {
  pname = "gpu-unlock";
  version = "${version}-${kernel.version}";
  inherit src;

  sourceRoot = "${src.name or "source"}/kernel/gpu_unlock";

  nativeBuildInputs = kernel.moduleBuildDependencies;

  hardeningDisable = [
    "pic"
    "format"
  ];

  makeFlags =
    kernelModuleMakeFlags
    ++ [
      "-C"
      kdir
      "M=$(PWD)"
    ]
    ++ lib.optional werror "KCFLAGS=-Werror"
    ++ extraMakeFlags;

  buildFlags = [ "modules" ];

  installFlags = [ "INSTALL_MOD_PATH=${placeholder "out"}" ];
  installTargets = [ "modules_install" ];

  # The tree is read-only; modules_install would otherwise try to run depmod.
  preInstall = ''
    makeFlagsArray+=(DEPMOD=true)
  '';

  passthru = {
    inherit kdir;
    # The kernel source tree, for checkpatch.
    ksrc = "${modules}/source";
  };

  meta = baseMeta // {
    description = "Unlock full FP16/BF16 tensor rate on GA102/GA103/GA104/GA106 GeForce cards";
  };
}
