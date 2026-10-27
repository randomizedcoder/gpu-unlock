# shellcheck shell=bash
#
# gpu-unlock-table NAME ROWS
#
# ROWS has one row per line: description, expected and actual, separated
# by the unit separator (0x1f), so a field may be empty or hold spaces
# and tabs. Prints PASS or FAIL per row and exits 1 if any row fails,
# or if there are no rows.

name=$1
rows=$2
failed=0
count=0

echo "=== $name ==="
while IFS=$'\x1f' read -r description expected actual; do
	count=$((count + 1))
	if [[ $actual == "$expected" ]]; then
		verdict=PASS
	else
		verdict=FAIL
		failed=1
	fi
	printf '%s  %s  (expected %s, got %s)\n' "$verdict" "$description" "$expected" "$actual"
done < "$rows"

# An empty table tests nothing, so it must not pass.
if ((count == 0)); then
	echo "FAIL  $name has no rows"
	failed=1
fi

exit "$failed"
