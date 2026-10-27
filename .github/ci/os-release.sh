#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Print one field of os-release(5): KEY from /etc/os-release, else
# /usr/lib/os-release, or from FILE. Reads the file rather than
# sourcing it, so nothing in it runs.
set -eu
key=${1:?usage: os-release.sh KEY [FILE]}
if [ $# -gt 1 ]; then
	file=$2
else
	file=/etc/os-release
	[ -f "$file" ] || file=/usr/lib/os-release
fi
[ -f "$file" ] || { echo "no os-release: $file" >&2; exit 1; }
# The last one wins, as when sourced.
value=$(sed -n "s/^$key=//p" "$file" | tail -n 1)
# Values may be quoted with either quote.
case "$value" in
\"*\" | \'*\') value=${value#?} value=${value%?} ;;
esac
# os-release(5): when ID is not set, ID=linux.
[ -n "$value" ] || [ "$key" != ID ] || value=linux
printf '%s\n' "$value"
