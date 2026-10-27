# SPDX-License-Identifier: GPL-2.0-only
#
# nix/analysis/gate.nix
#
# The analysis reports never fail a build. The gate does: each row
# pins the count of one kind of finding in one report, so a fixed
# finding cannot come back unnoticed. It runs in `nix flake check`.
#
#   nix build .#analysis-gate -L
#
# A row is { description; report; pattern; expected; }: the count of
# lines in report matching the ERE pattern must equal expected ("0"),
# or reach it (">=1"). See gate.sh.
#
# Before the real rows, the gate checks itself against fixture reports.
# Each self-test row adds outcome, what gate_check must say.
#

{
  pkgs,
  rows,
}:

let
  inherit (pkgs) lib;

  fixture = name: text: pkgs.writeText "gate-fixture-${name}" text;

  twoHits = fixture "two-hits" ''
    unlock_610.c:153:72: warning: incorrect type in argument 4 (different base types)
    unlock_610.c:767:60: warning: incorrect type in argument 5 (different base types)
    unlock_610.c:816:51: warning: restricted pci_power_t degrades to integer
  '';

  lookalikes = fixture "lookalikes" ''
    main.c:1:1: style: Variable 'x' can be declared as pointer to const [constVariablePointer]
    main.c:2:1: style: mentions shadowVariable without the brackets [variableScope]
    main.c:3:1: style: Local variable 'dev' shadows outer variable [shadowVariableX]
  '';

  oneHit = fixture "one-hit" ''
    main.c:3:1: style: Local variable 'dev' shadows outer variable [shadowVariable]
  '';

  empty = fixture "empty" "";

  argType = "incorrect type in argument [45] \\(different base types\\)";
  shadow = "\\[shadowVariable\\]";

  selfTests = [
    {
      description = "positive: exact count matches";
      report = twoHits;
      pattern = argType;
      expected = "2";
      outcome = "pass";
    }
    {
      description = "positive: minimum count reached";
      report = twoHits;
      pattern = argType;
      expected = ">=1";
      outcome = "pass";
    }
    {
      description = "negative: count above expected";
      report = twoHits;
      pattern = argType;
      expected = "1";
      outcome = "fail";
    }
    {
      description = "negative: lookalike lines are not counted";
      report = lookalikes;
      pattern = shadow;
      expected = "0";
      outcome = "pass";
    }
    {
      description = "boundary: expected 0, got 0";
      report = twoHits;
      pattern = shadow;
      expected = "0";
      outcome = "pass";
    }
    {
      description = "boundary: expected 0, got 1";
      report = oneHit;
      pattern = shadow;
      expected = "0";
      outcome = "fail";
    }
    {
      description = "boundary: minimum 1, got 0";
      report = twoHits;
      pattern = shadow;
      expected = ">=1";
      outcome = "fail";
    }
    {
      description = "corner: empty report counts 0";
      report = empty;
      pattern = shadow;
      expected = "0";
      outcome = "pass";
    }
    {
      description = "corner: missing report fails";
      report = "/nonexistent/report.txt";
      pattern = shadow;
      expected = "0";
      outcome = "fail";
    }
    {
      description = "corner: bad pattern fails";
      report = twoHits;
      pattern = "(";
      expected = "0";
      outcome = "fail";
    }
  ];

  call =
    r:
    "gate_check ${
      lib.escapeShellArgs [
        r.description
        (toString r.report)
        r.pattern
        r.expected
      ]
    }";

  # The self-test and the rows as one script, shellchecked with gate.sh
  # when it is built. It prints a PASS/FAIL line per row and exits 1 if
  # any row failed.
  gate = pkgs.writeShellApplication {
    name = "gpu-unlock-analysis-gate";
    runtimeInputs = [ pkgs.gnugrep ];
    text = builtins.readFile ./gate.sh + ''

      failed=0

      echo "=== gate self-test ==="
      ${lib.concatMapStrings (r: ''
        if ${call r} > /dev/null; then said=pass; else said=fail; fi
        if [[ $said == ${r.outcome} ]]; then
          printf 'PASS  %s  (gate said %s)\n' ${lib.escapeShellArg r.description} "$said"
        else
          printf 'FAIL  %s  (gate said %s, expected ${r.outcome})\n' ${lib.escapeShellArg r.description} "$said"
          failed=1
        fi
      '') selfTests}

      echo ""
      echo "=== findings ==="
      ${lib.concatMapStrings (r: ''
        ${call r} || failed=1
      '') rows}

      exit "$failed"
    '';
  };
in
pkgs.runCommand "gpu-unlock-analysis-gate" { } ''
  ${lib.getExe gate} | tee $TMPDIR/gate.txt
  status=''${PIPESTATUS[0]}
  if [[ $status -ne 0 ]]; then
    echo "analysis gate failed"
    exit "$status"
  fi
  mkdir -p $out
  cp $TMPDIR/gate.txt $out/gate.txt
''
