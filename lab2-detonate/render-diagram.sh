#!/usr/bin/env bash
# render-diagram.sh — regenerate architecture.png from architecture.mmd.
# Uses @mermaid-js/mermaid-cli (via npx) and a system Chrome/Chromium for Puppeteer
# (so it never downloads its own browser). Run from anywhere.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

command -v npx >/dev/null 2>&1 || { echo "need Node/npx" >&2; exit 1; }

# Find a usable browser for Puppeteer.
CHROME=""
for c in google-chrome google-chrome-stable chromium chromium-browser; do
  if command -v "$c" >/dev/null 2>&1; then CHROME="$(command -v "$c")"; break; fi
done
[[ -n "$CHROME" ]] || { echo "no chrome/chromium found for Puppeteer" >&2; exit 1; }

cfg="$(mktemp)"; trap 'rm -f "$cfg"' EXIT
printf '{ "executablePath": "%s", "args": ["--no-sandbox","--disable-gpu"] }\n' "$CHROME" > "$cfg"

echo ">> rendering architecture.mmd -> architecture.png (browser: $CHROME)"
PUPPETEER_SKIP_DOWNLOAD=1 PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=1 \
  npx -y @mermaid-js/mermaid-cli@latest \
    -i architecture.mmd -o architecture.png -p "$cfg" -b white -s 2
echo ">> wrote $(du -h architecture.png | cut -f1) architecture.png"
