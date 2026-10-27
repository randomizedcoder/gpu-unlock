# SPDX-License-Identifier: GPL-2.0-only
#
# nix/firmware.nix
#
# Generates the twelve firmware files gpu_unlock requests with the
# Makefile's own `make firmware` and `make install-firmware`, so the file
# list and the steps are written once: extract_gsp.py takes the GSP
# images out of the pinned installer, and extract_boot_assets.py derives
# the booter and GSP boot blobs from the pinned open kernel module
# source.
#
# Output layout matches hardware.firmware:
#   $out/lib/firmware/gpu-unlock/610.43.03/*.bin
#

{
  lib,
  stdenvNoCC,
  python3,
  zstd,
  xz,
  inputs,
  src,
  version,
  baseMeta,
}:

let
  fwDir = "lib/firmware/gpu-unlock/${inputs.nvVersion}";
in
stdenvNoCC.mkDerivation {
  pname = "gpu-unlock-firmware";
  inherit version src;

  nativeBuildInputs = [
    python3
    zstd
    xz
  ];

  dontConfigure = true;
  # gsp_ga10x.bin is an ELF: strip/patchelf must not touch the pinned bytes.
  dontFixup = true;

  # The firmware rule reads the inputs from $(INPUTS) by their upstream
  # file names.
  buildPhase = ''
    runHook preBuild
    mkdir inputs
    ln -s ${inputs.kernelModuleSource} inputs/${inputs.kernelModuleSource.name}
    ln -s ${inputs.installer} inputs/${inputs.installer.name}
    make firmware INPUTS=inputs ASSETS=assets PYTHON="python3 -E -s"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    make install-firmware ASSETS=assets DESTDIR=$out \
      FWDIR=/${fwDir} LICENSEDIR=/share/licenses
    runHook postInstall
  '';

  passthru = {
    inherit (inputs) nvVersion;
  };

  meta = baseMeta // {
    description = "Firmware for the gpu_unlock kernel module";
    # NVIDIA firmware stays under its own terms; see firmware/NOTICE.md.
    license = [
      baseMeta.license
      lib.licenses.unfreeRedistributableFirmware
    ];
  };
}
