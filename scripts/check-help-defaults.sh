#!/bin/bash
# Check that executable .r/.py/.sh scripts end their --help output with a
# pastable defaults one-liner:
#
#   Defaults:
#     <script basename> --opt value --other value ...
#
# The line after "Defaults:" must be indented and start with the script's
# basename. Non-executable files are skipped. Runners match the
# *-help-version / *-tldr hooks (.r scripts are checked under both r and
# Rscript). Exits 1 if any script fails.

# Succeeds iff the --help output in $2 has a "Defaults:" line followed by an
# indented line whose first word is the basename $1.
has_defaults_line() {
	printf '%s\n' "$2" | awk -v b="$1" '
		p { ok = ($0 ~ /^[[:space:]]+/ && $1 == b); exit }
		/^Defaults:[[:space:]]*$/ { p = 1 }
		END { exit !ok }
	'
}

# check <file> <runner command...>
check() {
	local f="$1" path="$1" out
	shift
	# A bare filename would otherwise be looked up on PATH when run directly
	[[ "${path}" == */* ]] || path="./${path}"
	out=$("$@" "${path}" --help 2>&1) || true
	has_defaults_line "$(basename "${f}")" "${out}" && return 0
	echo "FAIL: ${*:+${*} }${f} --help lacks a 'Defaults:' section whose next line starts with '$(basename "${f}")'"
	return 1
}

rc=0
for f in "$@"; do
	[[ -x "${f}" ]] || continue
	case "${f}" in
	*.r)
		check "${f}" r || rc=1
		check "${f}" Rscript || rc=1
		;;
	*.py)
		if grep -qE "^# /// script" "${f}" || { grep -q "import marimo" "${f}" && grep -q "@app\.cell" "${f}"; }; then
			check "${f}" uv run --script || rc=1
		else
			check "${f}" || rc=1
		fi
		;;
	*.sh) check "${f}" bash || rc=1 ;;
	*) echo "SKIP: ${f} - not a .r/.py/.sh script" ;;
	esac
done
exit "${rc}"
