# SPDX-License-Identifier: GPL-2.0-only
#
# nix/inputs.nix
#
# The two pinned NVIDIA inputs the firmware build needs, fetched as
# fixed-output derivations: the open kernel module source and the
# driver installer. URLs as in firmware/fetch_artifacts.py, file names
# as the Makefile's NV_SOURCE and NV_INSTALLER, and SHA-256 as in the
# PKGBUILD and the RPM spec. nix/tests/inputs.nix checks that all of
# these still agree.
#

{
  fetchurl,
  nvVersion ? "610.43.03",
}:

let
  fetch =
    dir: name: sha256:
    fetchurl {
      inherit name sha256;
      url = "https://download.nvidia.com/XFree86/${dir}/${name}";
    };
in
{
  inherit nvVersion;

  kernelModuleSource =
    fetch "NVIDIA-kernel-module-source" "NVIDIA-kernel-module-source-${nvVersion}.tar.xz"
      "7e118923c7a23edc36114d63273a46e3e04e9af98695a42203e7ac2dfe9fc1dc";

  installer =
    fetch "Linux-x86_64/${nvVersion}" "NVIDIA-Linux-x86_64-${nvVersion}-no-compat32.run"
      "e084451db730a6df29d3d74f655749c4d236e3c945f7d94b5205e84318fe2f90";
}
