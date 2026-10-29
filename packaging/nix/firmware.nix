# SPDX-License-Identifier: GPL-2.0-only
#
# The NVIDIA firmware gpu-unlock loads, made by `make firmware` from two
# pinned NVIDIA downloads. The version and hashes are also written in
# the Makefile, the PKGBUILD and the RPM spec; tests/inputs.nix checks
# that they all agree.
{ lib, stdenv, fetchurl, python3, zstd }:
let
  nvidiaVersion = "610.43.03";
  # The file names the Makefile expects in INPUTS.
  sourceFile = "NVIDIA-kernel-module-source-${nvidiaVersion}.tar.xz";
  installerFile = "NVIDIA-Linux-x86_64-${nvidiaVersion}-no-compat32.run";
  nvidiaSource = fetchurl {
    url = "https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/${sourceFile}";
    sha256 = "7e118923c7a23edc36114d63273a46e3e04e9af98695a42203e7ac2dfe9fc1dc";
  };
  nvidiaInstaller = fetchurl {
    url = "https://download.nvidia.com/XFree86/Linux-x86_64/${nvidiaVersion}/${installerFile}";
    sha256 = "e084451db730a6df29d3d74f655749c4d236e3c945f7d94b5205e84318fe2f90";
  };
in
stdenv.mkDerivation {
  pname = "gpu-unlock-firmware";
  version = lib.fileContents ../../VERSION;
  # Only what `make firmware` reads, so other edits do not rebuild it.
  src = lib.fileset.toSource {
    root = ../../.;
    fileset = lib.fileset.unions [ ../../Makefile ../../VERSION ../../firmware ];
  };
  nativeBuildInputs = [ python3 zstd ];
  buildPhase = ''
    runHook preBuild
    mkdir inputs
    ln -s ${nvidiaSource} inputs/${sourceFile}
    ln -s ${nvidiaInstaller} inputs/${installerFile}
    make firmware INPUTS=$PWD/inputs ASSETS=$PWD/assets
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make install-firmware ASSETS=$PWD/assets DESTDIR=$out \
      FWDIR=/lib/firmware/gpu-unlock/${nvidiaVersion} LICENSEDIR=/share/licenses
    runHook postInstall
  '';
  # The firmware images must stay byte for byte as extracted.
  dontFixup = true;
  # For the rows that check these pins against the other packaging.
  passthru = { inherit nvidiaVersion nvidiaSource nvidiaInstaller; };
  meta = {
    description = "Pinned NVIDIA firmware for gpu-unlock";
    license = [ lib.licenses.unfreeRedistributableFirmware lib.licenses.gpl2Only ];
    platforms = [ "x86_64-linux" ];
  };
}
