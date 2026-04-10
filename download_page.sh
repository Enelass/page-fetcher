#!/usr/bin/env bash
set -euo pipefail

# Save to /tmp for OS-wide temp access; keeps file for user inspection.
usage() {
  printf 'Usage: download_page <URL>\n' >&2
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

url="$1"

if ! [[ "$url" =~ ^https?:// ]]; then
  printf 'Error: URL must start with http:// or https://\n' >&2
  exit 1
fi

tmp_dir="/tmp"
ts="$(date +%Y%m%d_%H%M%S)"
base="$(basename "$url")"
[[ -z "$base" || "$base" == "/" ]] && base="index"
# Predictable safe filename; timestamp avoids collisions
safe="$(printf '%s' "$base" | tr -cd '[:alnum:]._-')"
[[ -z "$safe" ]] && safe="page"
outfile="${tmp_dir}/${safe}_${ts}.html"

# Use AllOrigins proxy to avoid blocks
PROXY_URL="${PROXY_URL:-https://api.allorigins.win}"
proxy_base="$PROXY_URL"

# Spinner function for background processes
spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  printf ' '
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    printf '\b%c' "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
  done
  printf '\b'
}

# Step 1: Download JSON response from AllOrigins /get endpoint
printf '\033[1;34m[1/4]\033[0m Downloading page via AllOrigins proxy...'
tmp_json="${outfile}.json"

# Retry logic with exponential backoff
max_retries=3
retry_count=0
success=false

while [ $retry_count -lt $max_retries ]; do
  if [ $retry_count -gt 0 ]; then
    printf '\n\033[1;33m↻ Retry %d/%d...\033[0m' "$retry_count" "$((max_retries-1))"
    sleep $((retry_count * 2))
  fi

  # Use HTTP/1.1, longer timeout, verbose for debugging
  printf '\n'
  curl -fL --verbose --http1.1 --max-time 120 --connect-timeout 15 \
    --get --data-urlencode "url=$url" -A "download_page/1.0" \
    -o "$tmp_json" "$proxy_base/get"
  curl_exit=$?
  printf '\n'

  if [ $curl_exit -eq 0 ] && [ -s "$tmp_json" ]; then
    success=true
    break
  fi

  # Show what went wrong
  if [ $curl_exit -ne 0 ]; then
    printf ' \033[1;31m(exit code: %d)\033[0m' "$curl_exit"
  fi

  retry_count=$((retry_count + 1))
done

if [ "$success" = false ]; then
  printf '\n\033[1;31mError:\033[0m AllOrigins proxy failed after %d attempts\n' "$max_retries" >&2
  printf 'Try again later or check if AllOrigins service is down\n' >&2
  rm -f "$tmp_json"
  exit 2
fi
printf ' \033[1;32m✓\033[0m\n'

# Step 2: Extract .contents field from JSON and save as HTML
printf '\033[1;34m[2/4]\033[0m Parsing JSON response...'
if ! command -v jq >/dev/null 2>&1; then
  printf '\n\033[1;31mError:\033[0m jq required for JSON parsing\n' >&2
  rm -f "$tmp_json"
  exit 4
fi

if ! jq -r '.contents' "$tmp_json" > "$outfile" 2>/dev/null; then
  printf '\n\033[1;31mError:\033[0m failed to parse JSON response\n' >&2
  rm -f "$tmp_json"
  exit 5
fi
rm -f "$tmp_json"
printf ' \033[1;32m✓\033[0m\n'

# Step 3: Strip redirects and base tags to allow local viewing
printf '\033[1;34m[3/4]\033[0m Removing anti-scraping redirects...'
sed -i '' \
  -e 's/<base[^>]*>//gi' \
  -e '/location\.href\s*=/d' \
  -e '/location\.replace\s*(/d' \
  -e '/window\.location\s*=/d' \
  "$outfile" 2>/dev/null || true

# Add CSP meta tag after <head> to allow cross-origin images
sed -i '' '/<head>/a\
<meta http-equiv="Content-Security-Policy" content="img-src * data: blob:; default-src *; script-src * '\''unsafe-inline'\'' '\''unsafe-eval'\''; style-src * '\''unsafe-inline'\'';">
' "$outfile" 2>/dev/null || true
printf ' \033[1;32m✓\033[0m\n'

# Step 4: Rewrite URLs to use AllOrigins proxy for resources
printf '\033[1;34m[4/4]\033[0m Rewriting resource URLs for proxy...'
# Extract domain from original URL for resource rewriting
domain="$(printf '%s' "$url" | sed -E 's|^https?://([^/]+).*|\1|')"
base_url="$(printf '%s' "$url" | sed -E 's|^(https?://[^/]+).*|\1|')"

# Rewrite URLs to use AllOrigins /raw proxy for resources with URL encoding
sed -i '' \
  -e "s|src=\"/|src=\"$proxy_base/raw?url=$(printf '%s' "$base_url" | sed 's|%|%25|g; s| |%20|g')/|g" \
  -e "s|href=\"/|href=\"$proxy_base/raw?url=$(printf '%s' "$base_url" | sed 's|%|%25|g; s| |%20|g')/|g" \
  -e "s|url(/|url($proxy_base/raw?url=$(printf '%s' "$base_url" | sed 's|%|%25|g; s| |%20|g')/|g" \
  "$outfile" 2>/dev/null || true

# Also rewrite absolute URLs for the same domain
sed -i '' \
  -e "s|src=\"https://$domain|src=\"$proxy_base/raw?url=https%3A%2F%2F$domain|g" \
  -e "s|href=\"https://$domain|href=\"$proxy_base/raw?url=https%3A%2F%2F$domain|g" \
  -e "s|url(https://$domain|url($proxy_base/raw?url=https%3A%2F%2F$domain|g" \
  "$outfile" 2>/dev/null || true
printf ' \033[1;32m✓\033[0m\n'

# Ensure file writes are flushed before opening browser
sync
sleep 0.5

# Open with default browser (macOS)
printf '\033[1;32m✓ Complete!\033[0m Opening in browser...\n'
open "$outfile" >/dev/null 2>&1 || {
  printf '\033[1;33mWarning:\033[0m could not open file automatically: %s\n' "$outfile" >&2
}

printf '\033[1;36m%s\033[0m\n' "$outfile"