# SPDX-License-Identifier: GPL-2.0-only
#
# nix/tests/python.nix
#
# checks.python-tests: the tables in tests/firmware, run against the
# firmware/ scripts with the pinned python3. extract_gsp.py pipes the
# installer through zstd, so the tables build their installers with it.
#

{
  runCommand,
  writeShellApplication,
  python3,
  zstd,
  sources,
}:

let
  tests = writeShellApplication {
    name = "gpu-unlock-python-tests";
    runtimeInputs = [
      python3
      zstd
    ];
    text = ''
      cd "$1"
      PYTHONPATH=firmware:tests/firmware PYTHONDONTWRITEBYTECODE=1 \
        python3 -m unittest discover -s tests/firmware
    '';
  };
in
runCommand "gpu-unlock-python-tests" { nativeBuildInputs = [ tests ]; } ''
  mkdir -p $out
  set -o pipefail
  gpu-unlock-python-tests ${sources.pythonTests} 2>&1 | tee $out/results.txt
''
