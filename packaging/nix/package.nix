# SPDX-License-Identifier: GPL-2.0-only
#
# The gpu_unlock kernel module, built for one kernel. Call it from that
# kernel's package set, e.g. config.boot.kernelPackages.callPackage.
# The firmware it loads is passthru.firmware (firmware.nix).
{ lib, stdenv, callPackage, kernel, kernelModuleMakeFlags }:
let
  # Kbuild, run on kernel/gpu_unlock against this kernel's build tree.
  kbuild = "make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    + " M=$PWD/kernel/gpu_unlock ${lib.escapeShellArgs kernelModuleMakeFlags}";
in
stdenv.mkDerivation {
  pname = "gpu-unlock";
  version = lib.fileContents ../../VERSION;
  # Only kernel/ and the files installed with it, so other edits do not
  # rebuild it.
  src = lib.fileset.toSource {
    root = ../../.;
    fileset = lib.fileset.unions [ ../../kernel ../../README.md ../../licenses/GPL-2.0.txt ];
  };
  nativeBuildInputs = kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  buildPhase = ''
    runHook preBuild
    ${kbuild} KCFLAGS=-Werror modules
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    # Use Kbuild installation so nixpkgs signing/certificate flags are honored.
    ${kbuild} INSTALL_MOD_PATH=$out INSTALL_MOD_DIR=extra DEPMOD=true modules_install
    install -Dm644 README.md $out/share/doc/gpu-unlock/README.md
    install -Dm644 licenses/GPL-2.0.txt $out/share/licenses/gpu-unlock/GPL-2.0.txt
    runHook postInstall
  '';
  # Kernel objects must not go through user-space ELF/RPATH fixups.
  dontFixup = true;
  passthru = {
    firmware = callPackage ./firmware.nix { };
    kernelVersion = kernel.modDirVersion;
  };
  meta = {
    description = "Ampere pre-driver Tensor throughput unlock";
    homepage = "https://github.com/Zagitta/gpu-unlock";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
