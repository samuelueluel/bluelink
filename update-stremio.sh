#!/usr/bin/env bash
# Script to update Stremio in arch-box and download the matching server.js
set -euo pipefail

BOX="arch-box"

echo "=== Updating Stremio in $BOX ==="
distrobox enter --name "$BOX" -- bash -c '
  set -euo pipefail
  yay -Sy --noconfirm stremio-enhanced-bin
'

echo "=== Detecting required server.js URL ==="
SERVER_URL=$(distrobox enter --name "$BOX" -- bash -c '
  if [ -f /usr/lib/stremio-enhanced/app.asar ]; then
    strings /usr/lib/stremio-enhanced/app.asar | grep -o -E "https://dl.strem.io/server/v4\.[0-9]+\.[0-9]+/desktop/server.js" | sort -V | tail -n 1
  fi
')

if [ -z "$SERVER_URL" ]; then
  echo "❌ Error: Could not extract server.js URL from app.asar inside the container."
  exit 1
fi

echo "Found required server URL: $SERVER_URL"

# Extract the version from the URL for version.txt
SERVER_VERSION=$(echo "$SERVER_URL" | grep -o -E "v4\.[0-9]+\.[0-9]+")
echo "Version: $SERVER_VERSION"

echo "=== Downloading server.js ==="
mkdir -p "$HOME/.config/stremio-enhanced/streamingserver"
wget -O "$HOME/.config/stremio-enhanced/streamingserver/server.js" "$SERVER_URL"
echo -n "$SERVER_VERSION" > "$HOME/.config/stremio-enhanced/streamingserver/version.txt"

echo "=== Stremio update complete ==="
