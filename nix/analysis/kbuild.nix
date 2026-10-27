# SPDX-License-Identifier: GPL-2.0-only
#
# nix/analysis/kbuild.nix
#
# Analysis that runs inside the real kernel build of the module, so the
# tools see the same headers, config and flags as the shipped .ko:
#
#   gcc-warnings   W=1 extra warnings
#   gcc-analyzer   KCFLAGS=-fanalyzer
#   sparse         C=2 CHECK=sparse  (kernel annotations: __iomem, endianness)
#   smatch         C=2 CHECK="smatch -p=kernel"
#
# Each report is the module derivation (kernel-module.nix) with its build
# and install replaced. It keeps the full build log, the findings that
# point into the module's own sources, and count.txt. Findings never
# fail the build.
#

{
  lib,
  kernelModule,
  sparse,
  smatch,
}:

let
  # The shipped module's derivation, built without -Werror (so one
  # warning does not hide the rest) and with V=1 (so the gate can see
  # each tool run). The flags go on the make command line rather than
  # into makeFlags, which is split on spaces ("CHECK=smatch -p=kernel").
  mkKbuildReport =
    name:
    {
      flags,
      tools ? [ ],
      # Lines a tool reports a finding on.
      pattern ? "(warning|error|warn):",
    }:
    (kernelModule.override {
      werror = false;
      extraMakeFlags = [ "V=1" ];
    }).overrideAttrs
      (old: {
        name = "gpu-unlock-analysis-${name}";
        nativeBuildInputs = old.nativeBuildInputs ++ tools;

        buildPhase = ''
          runHook preBuild
          echo "=== ${name} ==="
          local flagsArray=()
          concatTo flagsArray makeFlags makeFlagsArray buildFlags buildFlagsArray
          make "''${flagsArray[@]}" ${lib.escapeShellArgs flags} \
            > build.log 2>&1 || echo "build exited $?" >> build.log
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp build.log $out/build.log
          # Only findings in our sources: kbuild prints them relative to M=,
          # kernel headers come out as ./include/... or /nix/store/... paths.
          grep -E '^[A-Za-z0-9_]+\.[ch]:[0-9]+' build.log \
            | grep -E '${pattern}' | sort -u > $out/report.txt || true
          wc -l < $out/report.txt | tr -d ' ' > $out/count.txt
          echo "${name}: $(cat $out/count.txt) findings"
          runHook postInstall
        '';

        # Reports, not a module: nothing to strip or patch.
        dontFixup = true;
      });
in
{
  gcc-warnings = mkKbuildReport "gcc-warnings" { flags = [ "W=1" ]; };

  gcc-analyzer = mkKbuildReport "gcc-analyzer" {
    flags = [ "KCFLAGS=-fanalyzer" ];
  };

  sparse = mkKbuildReport "sparse" {
    flags = [
      "C=2"
      "CHECK=sparse"
    ];
    tools = [ sparse ];
  };

  smatch = mkKbuildReport "smatch" {
    flags = [
      "C=2"
      "CHECK=smatch -p=kernel"
    ];
    tools = [ smatch ];
  };
}
