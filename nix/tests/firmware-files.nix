# SPDX-License-Identifier: GPL-2.0-only
#
# nix/tests/firmware-files.nix
#
# checks.firmware-files: what the firmware package holds, as a table
# run on the built output. The file list is the Makefile's
# FIRMWARE_FILES and the module's MODULE_FIRMWARE names, so the package,
# the Makefile and the module cannot drift apart. table.sh prints the
# PASS/FAIL lines, as for the eval tests.
#

{
  lib,
  runCommand,
  writeShellApplication,
  tableRunner,
  coreutils,
  findutils,
  firmware,
}:

let
  inherit (firmware) nvVersion;

  inherit (import ../make-var.nix { inherit lib; }) makeVar words;
  read = path: builtins.readFile path;

  # The Makefile's FIRMWARE_FILES, continuation lines included.
  firmwareFiles = words (makeVar (read ../../Makefile) "FIRMWARE_FILES");

  # MODULE_FIRMWARE(GU_FW_X) in firmware_610.c, resolved through the
  # GU_FW_X defines in recipes.h to file names.
  matches =
    pattern: text: lib.filter (m: m != null) (map (builtins.match pattern) (lib.splitString "\n" text));
  defines = lib.listToAttrs (
    map (m: lib.nameValuePair (builtins.elemAt m 0) (baseNameOf (builtins.elemAt m 1))) (
      matches "#define (GU_FW_[A-Z0-9_]+)[[:space:]]+\"([^\"]+)\"" (
        read ../../kernel/gpu_unlock/recipes.h
      )
    )
  );
  moduleFirmware = map (m: defines.${builtins.head m}) (
    matches "MODULE_FIRMWARE\\((GU_FW_[A-Z0-9_]+)\\);" (read ../../kernel/gpu_unlock/firmware_610.c)
  );

  # The sizes the recipes in recipes.c require of the GSP boot images.
  bootSizes = {
    "gsp_boot_ga100.bin" = 4096;
    "gsp_boot_ga102.bin" = 24576;
    "gsp_boot_ad102.bin" = 36864;
  };

  rows = writeShellApplication {
    name = "gpu-unlock-firmware-rows";
    runtimeInputs = [
      coreutils
      findutils
    ];
    text = ''
      out=$1
      fw=$out/lib/firmware/gpu-unlock/${nvVersion}
      lic=$out/share/licenses/gpu-unlock-firmware

      row() { printf '%s\x1f%s\x1f%s\n' "$1" "$2" "$3"; }
      present() { if [[ -f $1 ]]; then echo yes; else echo no; fi; }

      for file in ${lib.escapeShellArgs firmwareFiles}; do
        row "firmware, positive: Makefile FIRMWARE_FILES has $file" yes "$(present "$fw/$file")"
      done
      for file in NVIDIA-LICENSE NOTICE.md; do
        row "firmware, positive: license file $file" yes "$(present "$lic/$file")"
      done
      row "firmware, negative: the directory holds FIRMWARE_FILES and nothing else" \
        ${lib.escapeShellArg (toString (lib.sort lib.lessThan firmwareFiles))} \
        "$(find "$fw" -mindepth 1 -printf '%f\n' | LC_ALL=C sort | xargs)"
      compressed=$(find "$out" \( -name '*.zst' -o -name '*.xz' \) -printf '%f\n' | xargs)
      row "firmware, negative: nothing compressed (the module requests plain .bin)" \
        "" "$compressed"
      ${lib.concatStrings (
        lib.mapAttrsToList (file: size: ''
          row "firmware, boundary: ${file} is the ${toString size} bytes recipes.c requires" \
            ${toString size} "$(stat -c %s "$fw/${file}" 2> /dev/null || echo missing)"
        '') bootSizes
      )}
      for file in gsp_ga10x.bin gsp_tu10x.bin; do
        row "firmware, corner: $file keeps its ELF magic (no fixup)" 7f454c46 \
          "$(od -An -tx1 -N4 "$fw/$file" 2> /dev/null | tr -d ' \n')"
      done
      for file in ${lib.escapeShellArgs moduleFirmware}; do
        row "firmware, corner: MODULE_FIRMWARE $file is in the package" yes "$(present "$fw/$file")"
      done
    '';
  };
in
runCommand "gpu-unlock-firmware-files"
  {
    nativeBuildInputs = [
      tableRunner
      rows
    ];
  }
  ''
    gpu-unlock-firmware-rows ${firmware} > rows
    mkdir -p $out
    set -o pipefail
    gpu-unlock-table firmware-files rows | tee $out/results.txt
  ''
