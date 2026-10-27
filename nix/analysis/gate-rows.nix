# SPDX-License-Identifier: GPL-2.0-only
#
# nix/analysis/gate-rows.nix
#
# Findings that were fixed and must stay fixed, as rows for gate.nix:
# each row counts the lines of one report file that match a pattern.
#

{
  tools,
  kbuildNames,
  moduleObjects,
}:

let
  row = expected: tool: file: description: pattern: {
    inherit description pattern expected;
    report = "${tools.${tool}}/${file}";
  };
  # No line of the tool's report.txt matches.
  none = tool: row "0" tool "report.txt";
  # At least n lines of the tool's file match.
  atLeast = n: row ">=${toString n}";

  sources = builtins.length moduleObjects;
  allSources = "all ${toString sources} sources";
in
[
  # gfp_t, pci_power_t and the other __bitwise types are only visible
  # to sparse.
  (none "sparse" "sparse: PMCSR state not compared with pci_power_t"
    "restricted pci_power_t degrades to integer"
  )
  (none "sparse" "sparse: allocation flags passed as gfp_t"
    "incorrect type in argument [0-9]+ \\(different base types\\)"
  )
  # cppcheck on the kernel alone: the integration shim is not the kernel.
  (none "cppcheck" "cppcheck: every kernel source parses" "\\[syntaxError\\]")
  (none "cppcheck" "cppcheck: no conditions decided by test mocks" "\\[knownConditionTrueFalse\\]")
  (none "cppcheck" "cppcheck: no unknown macros (main.c is analysed)" "\\[unknownMacro\\]")
  (atLeast 1 "cppcheck" "checked.txt" "cppcheck: main.c is in the kernel run"
    "^Checking kernel/gpu_unlock/main\\.c "
  )
  (row "0" "cppcheck" "checked.txt" "cppcheck: kernel run does not read tests/" "^Checking tests/")
  # cppcheck on tests/integration: the kernel sources it #includes are
  # analysed in the kernel run, without the shim.
  (none "cppcheck-tests" "cppcheck-tests: no unknown macros" "\\[unknownMacro\\]")
  (none "cppcheck-tests" "cppcheck-tests: reports only tests/" "^kernel/")
  (atLeast 3 "mypy" "checked.txt" "mypy: checked the firmware scripts" "^firmware/[a-z_0-9]+\\.py$")
]
# The 0 rows above only mean something if the tools ran. A failed
# kbuild leaves an empty report, so each kbuild run must finish and
# must have analysed every source Kbuild links.
++ map (
  name: row "0" name "build.log" "${name}: the module build finished" "^build exited "
) kbuildNames
++ [
  (atLeast sources "sparse" "build.log" "sparse: ran on ${allSources}" "^ +sparse .* [a-z0-9_]+\\.c$")
  (atLeast sources "smatch" "build.log" "smatch: ran on ${allSources}" "^ +smatch .* [a-z0-9_]+\\.c$")
  (atLeast sources "gcc-analyzer" "build.log" "gcc-analyzer: compiled ${allSources} with -fanalyzer"
    " -fanalyzer .* -c -o [a-z0-9_]+\\.o [a-z0-9_]+\\.c *$"
  )
  (none "nix-lint" "nix-lint: no statix or deadnix findings" "^[^ ]+\\.nix[>:][0-9]+:[0-9]+:")
  (atLeast 15 "nix-lint" "checked.txt" "nix-lint: checked flake.nix and nix/"
    "^(flake|nix/.+)\\.nix$"
  )
  (row "1" "shellcheck" "checked.txt" "shellcheck: checks the gate's own script"
    "^nix/analysis/gate\\.sh$"
  )
]
