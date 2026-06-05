# Changelog

## v0.2.0 - 2026-06-05

### Added
- Added a configurable CORS proxy chain with Codetabs first and AllOrigins fallback.
- Added support for `PROXY_CHAIN`, `CODETABS_URL`, and `ALLORIGINS_URL` overrides.
- Added stylesheet inlining so saved pages render even when public proxies serve CSS with browser-hostile MIME types.
- Added media URL post-processing for images, video/audio sources, posters, and `srcset`.
- Added clearer proxy failure reporting with the last proxy name, HTTP status, curl exit code, and response snippet.

### Changed
- Page downloads now accept raw HTML from Codetabs as well as JSON-wrapped HTML from AllOrigins.
- Resource rewriting now follows the proxy that successfully fetched the page.
- README now documents proxy configuration, `python3`, and public-proxy limitations.

### Fixed
- Fixed retry handling under `set -e` so failed `curl` calls no longer abort before the retry loop completes.
- Fixed poor local rendering caused by missing or rejected stylesheet loads.
