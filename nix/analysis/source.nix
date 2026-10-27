# SPDX-License-Identifier: GPL-2.0-only
#
# nix/analysis/source.nix
#
# Analysis that reads the source tree directly:
#
#   checkpatch      the kernel's own style/API checker on kernel/gpu_unlock
#   cppcheck        kernel/gpu_unlock
#   cppcheck-tests  tests/integration, separately: its kernel shim and
#                   device model would otherwise decide conditions in
#                   the kernel code
#   flawfinder      C source scanner
#   ruff            Python lint of firmware/ and tests/firmware
#   mypy            strict type check of firmware/
#   shellcheck      the CI and test scripts and the gate's
#                   nix/analysis/gate.sh
#   nix-lint        statix + deadnix on flake.nix and nix/
#
# Same report layout as kbuild.nix: report.txt + count.txt in $out.
#

{
  pkgs,
  kernelModule,
  src,
}:

let
  inherit (kernelModule) ksrc;

  # Each report is a script, checked by shellcheck when it is built,
  # that writes into the directory it is given: the derivation's $out.
  mkSourceReport =
    name: tools: script:
    let
      report = pkgs.writeShellApplication {
        name = "gpu-unlock-analysis-${name}";
        runtimeInputs = tools ++ [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.findutils
        ];
        text = ''
          out=$1
          mkdir -p "$out"
          cd ${src}
          echo "=== ${name} ==="
          ${script}
          echo "${name}: $(cat "$out/count.txt") findings"
        '';
      };
    in
    pkgs.runCommand "gpu-unlock-analysis-${name}"
      {
        inherit src;
        # The tools the script runs, for the dev shell.
        passthru.runtimeInputs = tools;
      }
      ''
        ${pkgs.lib.getExe report} $out
      '';

  countLines = pattern: ''
    { grep -cE '${pattern}' "$out/report.txt" || true; } > "$out/count.txt"
  '';

  # Findings go to report.txt, the "Checking <file> ..." progress to
  # checked.txt, so the gate can see which files were analysed.
  mkCppcheck =
    name: args:
    mkSourceReport name [ pkgs.cppcheck ] ''
      cppcheck --enable=warning,style,performance,portability \
        --std=c11 --inline-suppr \
        -D__KERNEL__ -DMODULE \
        --suppress=missingInclude --suppress=missingIncludeSystem \
        --suppress=unmatchedSuppression \
        --template='{file}:{line}:{column}: {severity}: {message} [{id}]' \
        ${args} > "$out/checked.txt" 2> "$out/report.txt" || true
      ${countLines ": (error|warning|style|performance|portability):"}
    '';
in
{
  checkpatch = mkSourceReport "checkpatch" [ pkgs.perl ] ''
    perl ${ksrc}/scripts/checkpatch.pl --no-tree --file --terse --show-types \
      --ignore SPDX_LICENSE_TAG \
      kernel/gpu_unlock/*.[ch] > "$out/report.txt" 2>&1 || true
    ${countLines ": (ERROR|WARNING|CHECK):"}
  '';

  cppcheck = mkCppcheck "cppcheck" "--library=${./cppcheck-kernel.cfg} kernel/gpu_unlock";

  # The integration runner #includes the kernel sources to run them
  # against a shim. Those sources are analysed, without it, in the
  # cppcheck run above; here the shim would decide their conditions.
  cppcheck-tests = mkCppcheck "cppcheck-tests" "--library=${./cppcheck-kernel.cfg} --suppress='*:kernel/gpu_unlock/*' tests/integration";

  flawfinder = mkSourceReport "flawfinder" [ pkgs.flawfinder ] ''
    flawfinder --minlevel=1 --columns --context --singleline \
      kernel/gpu_unlock > "$out/report.txt" 2>&1 || true
    { grep -oP 'Hits = \K[0-9]+' "$out/report.txt" || echo 0; } > "$out/count.txt"
  '';

  ruff = mkSourceReport "ruff" [ pkgs.ruff ] ''
    ruff check --no-cache --output-format=concise --target-version=py312 \
      firmware tests/firmware > "$out/report.txt" 2>&1 || true
    ${countLines "^[^ ]+\\.py:[0-9]+:[0-9]+: "}
  '';

  # --python-version: the oldest python3 the scripts run on outside Nix.
  mypy = mkSourceReport "mypy" [ pkgs.mypy ] ''
    printf '%s\n' firmware/*.py > "$out/checked.txt"
    xargs mypy --strict --python-version 3.12 \
      --no-incremental --cache-dir=/dev/null --no-error-summary \
      < "$out/checked.txt" > "$out/report.txt" 2>&1 || true
    ${countLines "^[^ ]+\\.py:[0-9]+: error:"}
  '';

  shellcheck = mkSourceReport "shellcheck" [ pkgs.shellcheck ] ''
    # checked.txt lists the scripts, as a clean run prints nothing.
    printf '%s\n' .github/ci/*.sh tests/*.sh tests/packaging/*.sh nix/analysis/gate.sh \
      > "$out/checked.txt"
    xargs shellcheck --format=gcc < "$out/checked.txt" > "$out/report.txt" 2>&1 || true
    ${countLines ":[0-9]+:[0-9]+: (error|warning|note):"}
  '';

  # deadnix's human output is coloured and spread over several lines;
  # its JSON gives one file:line:column: line per finding, as statix's
  # errfmt does.
  nix-lint =
    mkSourceReport "nix-lint"
      [
        pkgs.statix
        pkgs.deadnix
        pkgs.jq
      ]
      ''
        find flake.nix nix -name '*.nix' | sort > "$out/checked.txt"
        {
          statix check --format errfmt flake.nix || true
          statix check --format errfmt nix || true
          xargs deadnix --output-format json < "$out/checked.txt" \
            | jq -r '.file as $file | .results[]
                | "\($file):\(.line):\(.column): deadnix: \(.message)"' || true
        } > "$out/report.txt" 2>&1
        ${countLines "^[^ ]+\\.nix[>:][0-9]+:[0-9]+:"}
      '';
}
