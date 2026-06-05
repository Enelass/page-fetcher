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

if ! command -v jq >/dev/null 2>&1; then
  printf '\033[1;31mError:\033[0m jq required for JSON parsing and URL encoding\n' >&2
  exit 4
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf '\033[1;31mError:\033[0m python3 required for HTML/CSS post-processing\n' >&2
  exit 4
fi

tmp_dir="/tmp"
ts="$(date +%Y%m%d_%H%M%S)"
base="$(basename "$url")"
[[ -z "$base" || "$base" == "/" ]] && base="index"
# Predictable safe filename; timestamp avoids collisions
safe="$(printf '%s' "$base" | tr -cd '[:alnum:]._-')"
[[ -z "$safe" ]] && safe="page"
outfile="${tmp_dir}/${safe}_${ts}.html"

# Use public CORS proxies to avoid direct-origin blocks.
# PROXY_URL is kept as a legacy override for AllOrigins.
ALLORIGINS_URL="${ALLORIGINS_URL:-${PROXY_URL:-https://api.allorigins.win}}"
CODETABS_URL="${CODETABS_URL:-https://api.codetabs.com/v1/proxy/}"
PROXY_CHAIN="${PROXY_CHAIN:-codetabs allorigins}"
PROXY_CHAIN="${PROXY_CHAIN//,/ }"

url_encode() {
  printf '%s' "$1" | jq -sRr @uri
}

proxy_raw_prefix() {
  case "$1" in
    allorigins) printf '%s/raw?url=' "$ALLORIGINS_URL" ;;
    codetabs) printf '%s?quest=' "$CODETABS_URL" ;;
    *) printf '%s/raw?url=' "$ALLORIGINS_URL" ;;
  esac
}

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

# Step 1: Download HTML response from a CORS proxy
printf '\033[1;34m[1/4]\033[0m Downloading page via CORS proxy...'
tmp_payload="${outfile}.download"

# Retry logic with exponential backoff
max_retries=3
retry_count=0
success=false
curl_fail_args=(-f)
if curl --help all 2>/dev/null | grep -q -- '--fail-with-body'; then
  curl_fail_args=(--fail-with-body)
fi
last_curl_exit=0
last_http_code="000"
last_proxy=""
active_proxy=""

while [ $retry_count -lt $max_retries ]; do
  if [ $retry_count -gt 0 ]; then
    printf '\n\033[1;33m↻ Retry %d/%d...\033[0m' "$retry_count" "$((max_retries-1))"
    sleep $((retry_count * 2))
  fi

  for proxy_name in $PROXY_CHAIN; do
    last_proxy="$proxy_name"
    rm -f "$tmp_payload"
    printf '\nTrying %s...\n' "$proxy_name"

    curl_exit=0
    case "$proxy_name" in
      allorigins)
        http_code="$(curl "${curl_fail_args[@]}" -sS --location --verbose --http1.1 --max-time 120 --connect-timeout 15 \
          --get --data-urlencode "url=$url" -A "download_page/1.0" \
          -w '%{http_code}' -o "$tmp_payload" "$ALLORIGINS_URL/get")" || curl_exit=$?
        ;;
      codetabs)
        http_code="$(curl "${curl_fail_args[@]}" -sS --location --verbose --http1.1 --max-time 120 --connect-timeout 15 \
          --get --data-urlencode "quest=$url" -A "download_page/1.0" \
          -w '%{http_code}' -o "$tmp_payload" "$CODETABS_URL")" || curl_exit=$?
        ;;
      *)
        printf ' \033[1;33m(skipping unknown proxy: %s)\033[0m' "$proxy_name"
        continue
        ;;
    esac

    last_curl_exit=$curl_exit
    last_http_code="${http_code:-000}"
    printf '\n'

    if [ $curl_exit -ne 0 ]; then
      printf ' \033[1;31m%s failed (http: %s, exit code: %d)\033[0m' "$proxy_name" "$last_http_code" "$curl_exit"
      continue
    fi

    if [ ! -s "$tmp_payload" ]; then
      printf ' \033[1;31m%s returned an empty response\033[0m' "$proxy_name"
      continue
    fi

    if [ "$proxy_name" = "allorigins" ]; then
      if ! jq -er '.contents // empty' "$tmp_payload" > "$outfile" 2>/dev/null; then
        printf ' \033[1;31m%s response did not include .contents\033[0m' "$proxy_name"
        continue
      fi
    else
      mv "$tmp_payload" "$outfile"
    fi

    active_proxy="$proxy_name"
    success=true
    break
  done

  retry_count=$((retry_count + 1))
  [ "$success" = true ] && break
done

if [ "$success" = false ]; then
  printf '\n\033[1;31mError:\033[0m CORS proxy chain failed after %d attempts\n' "$max_retries" >&2
  printf 'Last proxy: %s, curl exit code: %d, HTTP status: %s\n' "$last_proxy" "$last_curl_exit" "$last_http_code" >&2
  if [ -s "$tmp_payload" ]; then
    printf 'Last response body: ' >&2
    head -c 500 "$tmp_payload" | tr '\n' ' ' >&2
    printf '\n' >&2
  fi
  printf 'Try again later or set PROXY_CHAIN to another supported proxy\n' >&2
  rm -f "$tmp_payload"
  exit 2
fi
rm -f "$tmp_payload"
printf ' \033[1;32m✓\033[0m\n'

# Step 2: Validate downloaded HTML
printf '\033[1;34m[2/4]\033[0m Validating downloaded HTML...'
if ! grep -qi '<html' "$outfile"; then
  printf '\n\033[1;31mError:\033[0m downloaded response does not look like HTML\n' >&2
  exit 5
fi
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

# Step 4: Rewrite URLs to use the active CORS proxy for resources
printf '\033[1;34m[4/4]\033[0m Rewriting resource URLs for proxy...'
# Extract domain from original URL for resource rewriting
domain="$(printf '%s' "$url" | sed -E 's|^https?://([^/]+).*|\1|')"
base_url="$(printf '%s' "$url" | sed -E 's|^(https?://[^/]+).*|\1|')"

# Rewrite URLs to use a CORS proxy for resources with URL encoding
resource_proxy_base="$(proxy_raw_prefix "$active_proxy")"
encoded_base_url="$(url_encode "$base_url")"
encoded_domain_url="$(url_encode "https://$domain")"

sed -i '' \
  -e "s|src=\"/|src=\"$resource_proxy_base$encoded_base_url/|g" \
  -e "s|href=\"/|href=\"$resource_proxy_base$encoded_base_url/|g" \
  -e "s|url(/|url($resource_proxy_base$encoded_base_url/|g" \
  "$outfile" 2>/dev/null || true

# Also rewrite absolute URLs for the same domain
sed -i '' \
  -e "s|src=\"https://$domain|src=\"$resource_proxy_base$encoded_domain_url|g" \
  -e "s|href=\"https://$domain|href=\"$resource_proxy_base$encoded_domain_url|g" \
  -e "s|url(https://$domain|url($resource_proxy_base$encoded_domain_url|g" \
  "$outfile" 2>/dev/null || true

# Inline stylesheets to avoid browser MIME checks on public proxy responses.
export PAGE_FETCHER_ACTIVE_PROXY="$active_proxy"
export PAGE_FETCHER_ALLORIGINS_URL="$ALLORIGINS_URL"
export PAGE_FETCHER_CODETABS_URL="$CODETABS_URL"
export PAGE_FETCHER_BASE_URL="$base_url"
python3 - "$outfile" <<'PY'
import html
import os
import re
import subprocess
import sys
from urllib.parse import parse_qs, quote, unquote, urljoin, urlparse

path = sys.argv[1]
active_proxy = os.environ["PAGE_FETCHER_ACTIVE_PROXY"]
allorigins_url = os.environ["PAGE_FETCHER_ALLORIGINS_URL"]
codetabs_url = os.environ["PAGE_FETCHER_CODETABS_URL"]
base_url = os.environ["PAGE_FETCHER_BASE_URL"]
base_host = urlparse(base_url).netloc

def proxy_prefix(proxy_name):
    if proxy_name == "codetabs":
        return codetabs_url + ("&" if "?" in codetabs_url else "?") + "quest="
    return allorigins_url.rstrip("/") + "/raw?url="

def proxy_url(target):
    return proxy_prefix(active_proxy) + quote(target, safe="")

def original_from_proxy(href):
    parsed = urlparse(href)
    query = parse_qs(parsed.query)
    if "quest" in query and query["quest"]:
        return query["quest"][0]
    if "url" in query and query["url"]:
        return query["url"][0]
    return href

def rewrite_css_urls(css, css_url):
    def replace(match):
        quote_char = match.group(1) or ""
        raw = match.group(2).strip()
        if raw.startswith(("data:", "blob:", "#", "about:")):
            return match.group(0)
        target = urljoin(css_url, raw)
        target_host = urlparse(target).netloc
        rewritten = proxy_url(target) if target_host == base_host else target
        return f"url({quote_char}{rewritten}{quote_char})"

    return re.sub(r"url\(\s*(['\"]?)([^)'\"\s][^)'\"]*?)\1\s*\)", replace, css)

def rewrite_media_urls(contents):
    def rewrite_url(value):
        if value.startswith(("data:", "blob:", "#", "about:", "mailto:", "javascript:")):
            return value
        parsed = urlparse(value)
        if parsed.netloc in {
            urlparse(allorigins_url).netloc,
            urlparse(codetabs_url).netloc,
        }:
            return value
        if parsed.scheme in {"http", "https"}:
            return proxy_url(value)
        if value.startswith("/"):
            return proxy_url(urljoin(base_url, value))
        return value

    def rewrite_srcset(value):
        parts = []
        for item in value.split(","):
            item = item.strip()
            if not item:
                continue
            bits = item.split()
            bits[0] = rewrite_url(bits[0])
            parts.append(" ".join(bits))
        return ", ".join(parts)

    def rewrite_tag(match):
        tag = match.group(0)

        def attr_replace(attr_match):
            name, quote_char, value = attr_match.groups()
            rewritten = rewrite_srcset(value) if name.lower() == "srcset" else rewrite_url(value)
            return f'{name}={quote_char}{html.escape(rewritten, quote=True)}{quote_char}'

        return re.sub(r"\b(src|poster|srcset)=(['\"])(.*?)\2", attr_replace, tag, flags=re.I)

    return re.sub(r"<(?:img|source|video|audio)\b[^>]*>", rewrite_tag, contents, flags=re.I)

def fetch_text(url):
    result = subprocess.run(
        [
            "curl",
            "-fsSL",
            "--http1.1",
            "--max-time",
            "60",
            "-A",
            "download_page/1.0",
            url,
        ],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0 or not result.stdout:
        return None
    return result.stdout.decode("utf-8", errors="replace")

contents = open(path, encoding="utf-8").read()
contents = rewrite_media_urls(contents)
contents = re.sub(r"<link\b(?=[^>]*\brel=[\"']preload[\"'])(?=[^>]*\bas=[\"']style[\"'])[^>]*>", "", contents, flags=re.I)
link_pattern = re.compile(r"<link\b(?=[^>]*\brel=[\"'][^\"']*\bstylesheet\b[^\"']*[\"'])(?=[^>]*\bhref=[\"']([^\"']+)[\"'])[^>]*>", re.I)

def inline_link(match):
    href = html.unescape(match.group(1))
    if href.startswith(("data:", "blob:")):
        return match.group(0)
    css = fetch_text(href)
    if css is None:
        return match.group(0)
    css = rewrite_css_urls(css, original_from_proxy(href))
    css = css.replace("</style", "<\\/style")
    return f"<style data-inlined-from=\"{html.escape(href, quote=True)}\">\n{css}\n</style>"

contents = link_pattern.sub(inline_link, contents)
open(path, "w", encoding="utf-8").write(contents)
PY
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
