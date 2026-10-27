# SPDX-License-Identifier: GPL-2.0-only
#
# nix/tests/sources.nix
#
# What each build's src holds. A build gets only the files it reads, so
# editing anything else (the flake, nix/, docs) does not rebuild it.
#

{
  kernelModule,
  firmware,
  analysis,
  sources,
}:

let
  rows =
    build: drv: entries:
    map (entry: {
      description = "sources, ${entry.case}: ${build} ${
        if entry.expected then "has" else "lacks"
      } ${entry.path}";
      actual = builtins.pathExists "${drv.src or (throw "${build} has no src")}/${entry.path}";
      inherit (entry) expected;
    }) entries;
in
rows "kernel module" kernelModule [
  {
    case = "positive";
    path = "kernel/gpu_unlock/main.c";
    expected = true;
  }
  {
    case = "positive";
    path = "kernel/gpu_unlock/Kbuild";
    expected = true;
  }
  {
    case = "negative";
    path = "flake.nix";
    expected = false;
  }
  {
    case = "negative";
    path = "nix/packages.nix";
    expected = false;
  }
  {
    case = "negative";
    path = "tests/integration/run.py";
    expected = false;
  }
  {
    case = "boundary";
    path = "kernel/gpu_unlock/Makefile";
    expected = true;
  }
  {
    case = "boundary";
    path = "Makefile";
    expected = false;
  }
  {
    case = "corner";
    path = "tests/unit/table.h";
    expected = false;
  }
  {
    case = "corner";
    path = ".gitattributes";
    expected = false;
  }
]
++ rows "firmware" firmware [
  {
    case = "positive";
    path = "firmware/extract_gsp.py";
    expected = true;
  }
  {
    case = "positive";
    path = "Makefile";
    expected = true;
  }
  {
    case = "positive";
    path = "VERSION";
    expected = true;
  }
  {
    case = "negative";
    path = "packaging/arch/PKGBUILD";
    expected = false;
  }
  {
    case = "negative";
    path = "kernel/gpu_unlock/main.c";
    expected = false;
  }
  {
    case = "negative";
    path = "nix/firmware.nix";
    expected = false;
  }
  {
    case = "boundary";
    path = "firmware/README.md";
    expected = true;
  }
  {
    case = "boundary";
    path = "tests/firmware/table.py";
    expected = false;
  }
  {
    case = "corner";
    path = "flake.lock";
    expected = false;
  }
]
++ rows "nix-lint" analysis.nix-lint [
  {
    case = "positive";
    path = "flake.nix";
    expected = true;
  }
  {
    case = "positive";
    path = "nix/tests/sources.nix";
    expected = true;
  }
  {
    case = "negative";
    path = "packaging/arch/PKGBUILD";
    expected = false;
  }
  {
    case = "boundary";
    path = "nix/make-var.nix";
    expected = true;
  }
  {
    case = "corner";
    path = "nix/tests/table.sh";
    expected = true;
  }
]
++ rows "shellcheck" analysis.shellcheck [
  {
    case = "positive";
    path = "nix/analysis/gate.sh";
    expected = true;
  }
  {
    case = "positive";
    path = ".github/ci/module.sh";
    expected = true;
  }
  {
    case = "negative";
    path = "packaging/arch/PKGBUILD";
    expected = false;
  }
  {
    case = "boundary";
    path = "tests/docker.sh";
    expected = true;
  }
  {
    case = "corner";
    path = "nix/tests/table.sh";
    expected = true;
  }
]
++ rows "unit tests" { src = sources.unitTests; } [
  {
    case = "positive";
    path = "tests/unit/main.c";
    expected = true;
  }
  {
    case = "positive";
    path = "kernel/gpu_unlock/gfw_eval.c";
    expected = true;
  }
  {
    case = "negative";
    path = "tests/integration/run.py";
    expected = false;
  }
  {
    case = "negative";
    path = "flake.nix";
    expected = false;
  }
  {
    case = "boundary";
    path = "kernel/gpu_unlock/Kbuild";
    expected = true;
  }
  {
    case = "corner";
    path = "firmware/extract_gsp.py";
    expected = false;
  }
]
++ rows "python tests" { src = sources.pythonTests; } [
  {
    case = "positive";
    path = "tests/firmware/table.py";
    expected = true;
  }
  {
    case = "positive";
    path = "firmware/extract_gsp.py";
    expected = true;
  }
  {
    case = "negative";
    path = "kernel/gpu_unlock/main.c";
    expected = false;
  }
  {
    case = "negative";
    path = "nix/packages.nix";
    expected = false;
  }
  {
    case = "boundary";
    path = "tests/integration/run.py";
    expected = false;
  }
  {
    case = "corner";
    path = "tests/unit/main.c";
    expected = false;
  }
]
