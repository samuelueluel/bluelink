#!/usr/bin/env bash
set -euo pipefail

echo "=== Adding Flathub Beta ==="
flatpak remote-add --if-not-exists flathub-beta https://flathub.org/beta-repo/flathub-beta.flatpakrepo

echo ""
echo "=== Installing Stremio (beta) ==="
flatpak install -y flathub-beta com.stremio.Stremio

echo ""
echo "Done."
