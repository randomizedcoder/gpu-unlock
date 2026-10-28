# SPDX-License-Identifier: GPL-2.0-only
#
# Rows for the source each package is built from: only the files its
# build reads, so an edit elsewhere (README, other packaging, CI) does
# not rebuild the module or the firmware.
{ module }:
let
  inherit (module) firmware;
  top = src: builtins.attrNames (builtins.readDir src);
in
[
  {
    description = "positive: the firmware is built from the Makefile, VERSION and firmware/";
    actual = top firmware.src;
    expected = [ "Makefile" "VERSION" "firmware" ];
  }
  {
    description = "positive: the module is built from kernel/, plus the README and licence it installs";
    actual = top module.src;
    expected = [ "README.md" "kernel" "licenses" ];
  }
  {
    description = "negative: a README edit does not rebuild the firmware";
    actual = builtins.pathExists "${firmware.src}/README.md";
    expected = false;
  }
  {
    description = "boundary: the module gets the GPL text it installs, not every licence";
    actual = top "${module.src}/licenses";
    expected = [ "GPL-2.0.txt" ];
  }
  {
    description = "corner: the module source has its Kbuild";
    actual = builtins.pathExists "${module.src}/kernel/gpu_unlock/Kbuild";
    expected = true;
  }
]
