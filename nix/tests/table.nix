# SPDX-License-Identifier: GPL-2.0-only
#
# nix/tests/table.nix
#
# Runs a table of evaluation-time tests. A row is
# { description; expected; actual; }: actual is computed when the check
# is evaluated, and is "error" if computing it throws (a rejected
# option, a failed assert), so rows can expect a refusal. table.sh
# prints a PASS or FAIL line per row, as the analysis gate does, and
# the check fails if any row fails.
#
# The runner checks itself first, on fixture rows, as the gate does.
#

{
  lib,
  runCommand,
  writeText,
  tableRunner,
}:

name: rows:

let
  attempt =
    value:
    let
      result = builtins.tryEval (builtins.deepSeq value value);
    in
    if result.success then result.value else "error";

  show = value: if builtins.isString value then value else builtins.toJSON value;

  # Nix strings have no \x escape.
  unitSeparator = builtins.fromJSON ''"\u001f"'';

  # One line per row, fields split by the unit separator.
  rowsFile =
    fileName: rows:
    writeText "gpu-unlock-${fileName}-rows" (
      lib.concatMapStrings (row: ''
        ${row.description}${unitSeparator}${show row.expected}${unitSeparator}${show (attempt row.actual)}
      '') rows
    );

  # Self-test: each fixture table and whether the runner must pass it.
  selfTests = [
    {
      description = "positive: equal values pass";
      outcome = "pass";
      rows = [
        {
          description = "same list";
          expected = [ "a" ];
          actual = [ "a" ];
        }
      ];
    }
    {
      description = "negative: one differing row fails the table";
      outcome = "fail";
      rows = [
        {
          description = "same";
          expected = 1;
          actual = 1;
        }
        {
          description = "different";
          expected = 1;
          actual = 2;
        }
      ];
    }
    {
      description = "boundary: empty expected and actual fields line up";
      outcome = "pass";
      rows = [
        {
          description = "empty strings";
          expected = "";
          actual = "";
        }
      ];
    }
    {
      description = "corner: a throw is the value error";
      outcome = "pass";
      rows = [
        {
          description = "refused";
          expected = "error";
          actual = throw "refused";
        }
      ];
    }
    {
      description = "corner: a table with no rows fails";
      outcome = "fail";
      rows = [ ];
    }
    {
      description = "corner: an unexpected throw fails";
      outcome = "fail";
      rows = [
        {
          description = "refused";
          expected = "ok";
          actual = throw "refused";
        }
      ];
    }
  ];

  selfTest = test: ''
    if gpu-unlock-table self-test ${rowsFile "self-test" test.rows} > /dev/null; then said=pass; else said=fail; fi
    if [[ $said == ${test.outcome} ]]; then
      printf 'PASS  %s  (runner said %s)\n' ${lib.escapeShellArg test.description} "$said"
    else
      printf 'FAIL  %s  (runner said %s, expected ${test.outcome})\n' ${lib.escapeShellArg test.description} "$said"
      exit 1
    fi
  '';
in
runCommand "gpu-unlock-${name}" { nativeBuildInputs = [ tableRunner ]; } ''
  echo "=== table runner self-test ==="
  ${lib.concatMapStrings selfTest selfTests}
  echo ""

  mkdir -p $out
  set -o pipefail
  gpu-unlock-table ${name} ${rowsFile name rows} | tee $out/results.txt
''
