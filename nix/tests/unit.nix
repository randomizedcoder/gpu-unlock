# SPDX-License-Identifier: GPL-2.0-only
#
# nix/tests/unit.nix
#
# checks.unit-tests: the tables in tests/unit, built on the host against
# the kernel helpers that touch no hardware (recipes.c, payload.c,
# gfw_eval.c) with AddressSanitizer and UBSan, and run. recipes.c keeps
# the GA100 and AD102 families no card uses yet, hence
# -Wno-unused-const-variable.
#

{
  stdenv,
  sources,
}:

stdenv.mkDerivation {
  name = "gpu-unlock-unit-tests";
  src = sources.unitTests;

  buildPhase = ''
    runHook preBuild
    $CC -std=gnu11 -O1 -g -Wall -Wextra -Werror -Wno-unused-const-variable \
      -fsanitize=address,undefined -fno-sanitize-recover=all \
      -I kernel/gpu_unlock \
      tests/unit/*.c \
      kernel/gpu_unlock/recipes.c kernel/gpu_unlock/payload.c kernel/gpu_unlock/gfw_eval.c \
      -o unit-tests
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    set -o pipefail
    ./unit-tests | tee results.txt
    runHook postCheck
  '';

  installPhase = ''
    mkdir -p $out
    cp results.txt $out/
  '';
}
