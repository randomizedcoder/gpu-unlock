# SPDX-License-Identifier: GPL-2.0-only
# shellcheck shell=bash
#
# nix/analysis/gate.sh, sourced by gate.nix.
#
# gate_check DESCRIPTION REPORT PATTERN EXPECTED
#
# Counts the lines of REPORT matching the ERE PATTERN. EXPECTED is an
# exact count ("0") or a minimum (">=1"). Prints one PASS/FAIL line and
# returns 0 on PASS. A missing report or a bad pattern is a FAIL, never
# a count of 0, so a broken tool cannot pass the gate by producing
# nothing. An EXPECTED of any other form is a FAIL too.

gate_check() {
	local description=$1 report=$2 pattern=$3 expected=$4 got status

	if [[ ! -f $report ]]; then
		printf 'FAIL  %s  (no report: %s)\n' "$description" "$report"
		return 1
	fi
	got=$(grep -cE -e "$pattern" -- "$report")
	status=$?
	# grep -c exits 1 with a count of 0, and 2 on error.
	if ((status > 1)); then
		printf 'FAIL  %s  (bad pattern: %s)\n' "$description" "$pattern"
		return 1
	fi
	if [[ ! $expected =~ ^(>=)?[0-9]+$ ]]; then
		printf 'FAIL  %s  (bad expected: %s)\n' "$description" "$expected"
		return 1
	fi
	case $expected in
	'>='*) ((got >= ${expected#>=})) ;;
	*) ((got == expected)) ;;
	esac
	status=$?
	if ((status == 0)); then
		printf 'PASS  %s  (expected %s, got %s)\n' "$description" "$expected" "$got"
	else
		printf 'FAIL  %s  (expected %s, got %s)\n' "$description" "$expected" "$got"
	fi
	return "$status"
}
