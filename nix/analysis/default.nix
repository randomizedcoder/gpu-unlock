# SPDX-License-Identifier: GPL-2.0-only
#
# nix/analysis/default.nix
#
# Static analysis entry point, laid out like xdp2's nix/analysis but
# aimed at an out-of-tree kernel module. Three levels:
#
#   quick:    gcc-warnings (W=1), sparse, checkpatch, ruff, mypy, shellcheck,
#             nix-lint
#   standard: + smatch, cppcheck (kernel, tests), flawfinder
#   deep:     + gcc-analyzer (-fanalyzer)
#
# Usage:
#   nix build .#analysis-quick    && cat result/summary.txt
#   nix build .#analysis-standard
#   nix build .#analysis-deep
#   nix build .#analysis-sparse   && cat result/report.txt
#   nix build .#analysis-gate -L
#
# Reports never fail the build; read count.txt / report.txt. The gate
# (gate.nix) does fail, on the findings pinned in gate-rows.nix.
#

{
  pkgs,
  kernelPackages,
  kernelModule,
  src,
}:

let
  inherit (kernelPackages) kernel;

  kbuild = import ./kbuild.nix {
    inherit (pkgs) lib sparse smatch;
    inherit kernelModule;
  };
  source = import ./source.nix { inherit pkgs kernelModule src; };

  tools = kbuild // source;

  kbuildObjects = import ./kbuild-objects.nix { inherit (pkgs) lib; };
  # What the module links; every kbuild report must compile them all.
  moduleObjects = kbuildObjects (builtins.readFile "${src}/kernel/gpu_unlock/Kbuild");

  kbuildNames = [
    "gcc-warnings"
    "gcc-analyzer"
    "sparse"
    "smatch"
  ];

  gate = import ./gate.nix {
    inherit pkgs;
    rows = import ./gate-rows.nix { inherit tools kbuildNames moduleObjects; };
  };

  levels = rec {
    quick = [
      "gcc-warnings"
      "sparse"
      "checkpatch"
      "ruff"
      "mypy"
      "shellcheck"
      "nix-lint"
    ];
    standard = quick ++ [
      "smatch"
      "cppcheck"
      "cppcheck-tests"
      "flawfinder"
    ];
    deep = standard ++ [ "gcc-analyzer" ];
  };

  mkSummary =
    level: names:
    let
      summary = pkgs.writeShellApplication {
        name = "gpu-unlock-analysis-${level}";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          out=$1
          mkdir -p "$out"
          {
            echo "=== gpu_unlock analysis (${level}) against linux ${kernel.version} ==="
            echo ""
            ${pkgs.lib.concatMapStrings (n: ''
              ln -s ${tools.${n}} "$out/${n}"
              printf '%-16s %s findings\n' "${n}:" "$(cat ${tools.${n}}/count.txt)"
            '') names}
            echo ""
            echo "Details: result/<tool>/report.txt"
          } > "$out/summary.txt"
          cat "$out/summary.txt"
        '';
      };
    in
    pkgs.runCommand "gpu-unlock-analysis-${level}" { } ''
      ${pkgs.lib.getExe summary} $out
    '';
in
tools
// {
  inherit gate kbuildObjects moduleObjects;
  # Every report by tool name, for the dev shell's inputsFrom. Not a
  # derivation, so the flake does not export it as a package.
  reports = tools;
}
// builtins.mapAttrs mkSummary levels
