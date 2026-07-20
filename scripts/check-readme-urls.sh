#!/bin/bash
# Check README.md files for unreachable URLs.
# Exits 1 if broken URLs found, 0 otherwise.
#
# Set GITHUB_TOKEN to also check URLs on private GitHub repos. If a
# github.com/raw.githubusercontent.com/gist.github.com URL is unreachable
# anonymously but reachable with the token, it's assumed to be a private
# repo: a warning is printed but the check does not fail.

found_any=0

# Helper: Extract URLs from a line (http/https only)
# Returns URLs on stdout, one per line
extract_urls() {
	local line="$1"
	# Match http(s) URLs: start with https?:// and grab word chars, dots, slashes, hyphens, underscores
	grep -oE 'https?://[-a-zA-Z0-9._~:/?#@!$&()*+,;=%]*' <<<"${line}" | sed 's/[,.)>"`]*$//' || true
}

# Helper: Is this a GitHub-hosted URL that would accept a GITHUB_TOKEN?
is_github_url() {
	local url="$1"
	[[ "${url}" =~ ^https?://(www\.)?(github\.com|raw\.githubusercontent\.com|gist\.github\.com)/ ]]
}

# Helper: Is this a github.com repo/blob/etc. page (as opposed to raw content or a gist)?
# github.com's web UI uses session-cookie auth, not GITHUB_TOKEN, so a private
# repo's pages must be confirmed via the REST API instead of the page itself.
is_github_web_url() {
	local url="$1"
	[[ "${url}" =~ ^https?://(www\.)?github\.com/ ]]
}

# Helper: Confirm a github.com/OWNER/REPO[/...] URL belongs to a repo GITHUB_TOKEN can see
check_github_repo_via_api() {
	local url="$1"
	local owner_repo status
	owner_repo=$(sed -nE 's#^https?://(www\.)?github\.com/([^/]+/[^/]+).*#\2#p' <<<"${url}")
	owner_repo="${owner_repo%.git}"
	[[ -z "${owner_repo}" ]] && return 1
	status=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --retry 2 --retry-delay 1 -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/${owner_repo}" 2>/dev/null)
	[[ -n "${status}" ]] && [[ "${status}" -ge 200 ]] && [[ "${status}" -lt 300 ]]
}

# Helper: Check URL reachability
# Returns 0 if OK (2xx-3xx), 1 if broken/unreachable
check_url() {
	local url="$1"
	shift
	local auth_args=("$@")
	local status
	# Try HEAD first
	status=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --retry 2 --retry-delay 1 "${auth_args[@]}" -I "${url}" 2>/dev/null)

	# If HEAD failed to get a status, try GET
	if [[ -z "${status}" ]] || [[ "${status}" -eq 000 ]]; then
		status=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --retry 2 --retry-delay 1 "${auth_args[@]}" -L "${url}" 2>/dev/null)
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
				if [[ -n "${GITHUB_TOKEN:-}" ]] && is_github_url "${url}"; then
					if is_github_web_url "${url}"; then
						private_repo_ok=$(check_github_repo_via_api "${url}" && echo 1 || echo 0)
					else
						private_repo_ok=$(check_url "${url}" -H "Authorization: Bearer ${GITHUB_TOKEN}" >/dev/null && echo 1 || echo 0)
					fi
					if [[ "${private_repo_ok}" -eq 1 ]]; then
						echo "WARN: ${file}:${line_no}: private GitHub repo (unreachable anonymously, OK with GITHUB_TOKEN): ${url}"
						continue
					fi
				fi
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
