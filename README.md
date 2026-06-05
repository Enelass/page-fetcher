# Page Downloader

A command-line tool that downloads web pages, bypasses CORS restrictions, removes anti-scraping measures, and opens them locally in your browser with all images and resources properly loaded.

![Page Fetcher Workflow](diagram.png)

## What This Does

This script downloads any web page and makes it viewable locally by:

1. **Downloading via a CORS proxy chain** - Tries configured public proxies until one returns usable content
2. **Parsing proxy responses** - Handles proxy-specific response formats and extracts the page HTML
3. **Removing anti-scraping redirects** - Strips base tags and JavaScript redirects that prevent local viewing
4. **Rewriting resource URLs** - Proxies same-origin images, scripts, and assets through the working CORS proxy
5. **Inlining stylesheets** - Downloads CSS and embeds it into the saved HTML to avoid browser MIME-type rejections from proxy responses
6. **Adding security headers** - Includes Content Security Policy to allow cross-origin resources
7. **Opening in browser** - Automatically opens the processed page in your default browser

The script provides visual progress indicators showing each step and includes a spinner for longer operations.

## Quick Usage

**Remote execution (no installation required):**
```bash
curl -s https://raw.githubusercontent.com/Enelass/page-fetcher/main/download_page.sh | bash -s -- "https://example.com"
```

**Add shell alias for convenience:**
```bash
# Add to ~/.zshrc or ~/.bashrc
alias download_page='curl -s https://raw.githubusercontent.com/Enelass/page-fetcher/main/download_page.sh | bash -s --'

# Then use like:
download_page "https://example.com"
```

## How It Works

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Target URL    │───▶│ CORS Proxy Chain │───▶│ Proxy Response  │
│ https://site... │    │ configured list  │    │ HTML or JSON    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Browser Opens  │◀───│  Process & Save  │◀───│  Extract HTML   │
│   /tmp/page     │    │ Remove redirects │    │ Parse with jq   │
└─────────────────┘    │ Rewrite URLs     │    └─────────────────┘
                       │ Inline CSS + CSP │
                       └──────────────────┘
```

## Requirements

- **macOS** - Uses the `open` command to launch the browser
- **curl** - For downloading web content (pre-installed on macOS)
- **jq** - For JSON parsing (`brew install jq`)
- **python3** - For HTML/CSS post-processing (pre-installed on most recent macOS versions)
- **Internet connectivity** - Must be able to reach at least one configured CORS proxy
- **Proxy/SSL support** - If behind corporate firewall, ensure curl can access HTTPS endpoints

## Installation

### Local Installation

```bash
# Download the script
curl -O https://raw.githubusercontent.com/Enelass/page-fetcher/main/download_page.sh
chmod +x download_page.sh

# Optional: Install globally
sudo cp download_page.sh /usr/local/bin/download_page
```

### Remote Execution

Run directly without downloading:

```bash
curl -s https://raw.githubusercontent.com/Enelass/page-fetcher/main/download_page.sh | bash -s -- "https://example.com"
```

## Usage

### Basic Usage

```bash
./download_page.sh "https://example.com"
```

### Global Installation Usage

```bash
download_page "https://example.com"
```

### Remote Execution

```bash
curl -s https://raw.githubusercontent.com/Enelass/page-fetcher/main/download_page.sh | bash -s -- "https://www.reddit.com/r/programming"
```

### Proxy Configuration

Configure the proxy order with `PROXY_CHAIN`. The first proxy that returns usable HTML is used for the page and same-origin resources:

```bash
PROXY_CHAIN="codetabs allorigins" ./download_page.sh "https://example.com"
```

Comma-separated values are also accepted:

```bash
PROXY_CHAIN="allorigins,codetabs" ./download_page.sh "https://example.com"
```

Built-in proxy adapters:
- `codetabs` - Uses `https://api.codetabs.com/v1/proxy/?quest=...`
- `allorigins` - Uses `https://api.allorigins.win/get` for pages and `/raw` for resources

Optional endpoint overrides:

```bash
CODETABS_URL="https://api.codetabs.com/v1/proxy/" \
ALLORIGINS_URL="https://api.allorigins.win" \
./download_page.sh "https://example.com"
```

## How It Works

The script uses public CORS proxies as a best-effort way to fetch HTML and resources when direct access is blocked or not browser-friendly. It:

1. Sends the target URL through the configured `PROXY_CHAIN`
2. Receives a proxy-specific response and extracts usable HTML
3. Processes the HTML to remove anti-scraping measures
4. Rewrites same-origin resource URLs to use the successful proxy
5. Downloads linked stylesheets and inlines them into the saved page
6. Adds appropriate security headers for cross-origin resource loading
7. Saves the processed file to `/tmp` with a timestamp
8. Opens the file in your default browser

## Output

Files are saved to `/tmp` with the format:
```
/tmp/domain.com_YYYYMMDD_HHMMSS.html
```

The script outputs the full path of the saved file for reference.

## Progress Indicators

The script shows colored progress indicators:
- `[1/4] Downloading page via CORS proxy...`
- `[2/4] Validating downloaded HTML...`
- `[3/4] Removing anti-scraping redirects...`
- `[4/4] Rewriting resource URLs for proxy...`

## Error Handling

The script includes comprehensive error handling for:
- Missing URL argument
- Network connectivity issues
- Missing jq dependency
- Missing python3 dependency
- JSON parsing failures
- Proxy-chain failures with the last HTTP status and response body
- File system errors

## Security Considerations

**Important Security Notice**: This tool downloads static web page content only and does not execute JavaScript or create persistent network connections. It is not designed to evade network restrictions or bypass security policies.

### Technical Security
- The script uses third-party public CORS proxies
- Requests go through the configured proxy chain
- Content Security Policy headers are added to allow cross-origin resources
- No sensitive data is stored or transmitted beyond the target URL
- Downloads are limited to static HTML content - no active code execution
- Files are saved locally to `/tmp` with no network exposure

### Responsible Usage
**User Responsibility**: It is your responsibility to use this tool reasonably and ethically. Do not use this tool to:
- Access malicious or prohibited content
- Bypass corporate security policies or network restrictions
- Download copyrighted material without permission
- Circumvent website terms of service
- Access content that violates local laws or regulations

This tool is intended for legitimate research, development, and educational purposes only. Users must comply with all applicable laws, regulations, and website terms of service when using this tool.

## Limitations

- Requires internet access to at least one configured CORS proxy
- Public CORS proxies can be rate-limited, flaky, or unavailable
- Proxied JavaScript and dynamic app behavior may not work reliably from a local file
- Some dynamic content may not render properly
- JavaScript-heavy sites may have limited functionality
- Large pages may take 20-30 seconds to process

## Troubleshooting

**Images not loading initially**: Refresh the browser page once or twice. This is due to browser caching behavior with cross-origin resources.

**jq command not found**: Install jq with `brew install jq`

**Network errors**: Check internet connectivity and ensure at least one configured CORS proxy is accessible

**Proxy failures**: Try a different chain, for example `PROXY_CHAIN=allorigins,codetabs`, or retry later if public proxies are returning `520`, `522`, or `500`.

**Corporate firewall**: Ensure curl can access HTTPS endpoints and the configured proxy hosts are not blocked

## License

MIT License - Feel free to use, modify, and distribute.
