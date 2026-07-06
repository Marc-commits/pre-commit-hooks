#!/bin/bash
# Check README.md files for unreachable URLs.
# Exits 1 if broken URLs found, 0 otherwise.

found_any=0

# Helper: Extract URLs from a line (http/https only)
# Returns URLs on stdout, one per line
extract_urls() {
	local line="$1"
	# Match http(s) URLs: start with https?:// and grab word chars, dots, slashes, hyphens, underscores
	grep -oE 'https?://[-a-zA-Z0-9._~:/?#@!$&()*+,;=%]*' <<<"${line}" | sed 's/[,.)>"`]*$//' || true
}

# Helper: Check URL reachability
# Returns 0 if OK (2xx-3xx), 1 if broken/unreachable
check_url() {
	local url="$1"
	local status
	# Try HEAD first
	status=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --retry 2 --retry-delay 1 -I "${url}" 2>/dev/null)

	# If HEAD failed to get a status, try GET
	if [[ -z "${status}" ]] || [[ "${status}" -eq 000 ]]; then
		status=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --retry 2 --retry-delay 1 -L "${url}" 2>/dev/null)
	fi

	# Check if status is 2xx or 3xx
	if [[ -n "${status}" ]] && [[ "${status}" -ge 200 ]] && [[ "${status}" -lt 400 ]]; then
		return 0
	else
		echo "${status}"
		return 1
	fi
}

# Process each file
for file in "$@"; do
	line_no=0
	declare -A seen_urls # Track which URLs we've already checked/warned

	while IFS= read -r line; do
		line_no=$((line_no + 1))

		# Extract URLs from this line
		while read -r url; do
			[[ -z "${url}" ]] && continue

			# Skip if we've already warned about this URL
			if [[ -n "${seen_urls[${url}]}" ]]; then
				continue
			fi
			seen_urls[${url}]=1

			# Check reachability
			status=$(check_url "${url}")
			rc=$?
			if [[ "${rc}" -ne 0 ]]; then
				echo "WARN: ${file}:${line_no}: unreachable URL (status ${status}): ${url}"
				found_any=1
			fi
		done < <(extract_urls "${line}" || true)
	done <"${file}"
done

if [[ "${found_any}" -eq 1 ]]; then
	echo ""
	echo "Tip: if these URLs are temporarily unavailable or behind auth, use: git commit --no-verify"
	exit 1
fi
exit 0
