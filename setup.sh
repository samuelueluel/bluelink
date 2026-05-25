#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX="arch-box"

# ── GNOME: power / display / cursor ───────────────────────────────────────────
echo "=== Configuring GNOME settings ==="

# Disable sleep, suspend, idle dim
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false

# Disable screen blank and auto-lock (manual screensaver still works)
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver lock-enabled false

# Display scale 300%
gsettings set org.gnome.desktop.interface scaling-factor 3

# Larger cursor (2× the default 24px)
gsettings set org.gnome.desktop.interface cursor-size 48

# ── Ptyxis: terminal font ─────────────────────────────────────────────────────
echo ""
echo "=== Setting Ptyxis font to JetBrains Mono Nerd Font ==="
# Fonts are installed by brew bundle above, but that runs later — this block
# is idempotent so rerunning after brew is fine.
PTYXIS_PROFILES=$(gsettings get org.gnome.Ptyxis profiles 2>/dev/null \
  | tr -d "[]' " | tr ',' '\n')
for _PROFILE in $PTYXIS_PROFILES; do
  [ -z "$_PROFILE" ] && continue
  _PATH="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$_PROFILE/"
  gsettings set "$_PATH" use-system-font false
  gsettings set "$_PATH" custom-font 'JetBrainsMono Nerd Font 12'
done

# ── Auto-login ────────────────────────────────────────────────────────────────
echo ""
echo "=== Enabling auto-login for $USER ==="
sudo tee /etc/gdm/custom.conf > /dev/null << EOF
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=$USER
EOF

# ── Dotfiles ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Installing dotfiles ==="
cp "$SCRIPT_DIR/dot_zshrc" "$HOME/.zshrc"
mkdir -p "$HOME/.config"
cp "$SCRIPT_DIR/dot_config/starship.toml" "$HOME/.config/starship.toml"

# ── Homebrew ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Setting up Homebrew ==="
if ! command -v brew &>/dev/null; then
  echo "Homebrew not found — installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

echo ""
echo "=== Installing Brew packages ==="
brew bundle --file="$SCRIPT_DIR/Brewfile"

# ── Arch distrobox ────────────────────────────────────────────────────────────
echo ""
echo "=== Removing existing distrobox and exports ==="
distrobox stop "$BOX" 2>/dev/null || true
distrobox rm --force "$BOX" 2>/dev/null || true
rm -f "$HOME/.local/share/applications/"*stremio* 2>/dev/null || true
rm -f "$HOME/.local/bin/"*stremio* 2>/dev/null || true
rm -rf "$HOME/.config/stremio-enhanced" 2>/dev/null || true

echo ""
echo "=== Creating Arch Linux distrobox ==="
distrobox create --name "$BOX" --image archlinux:latest --yes

echo ""
echo "=== Installing yay ==="
distrobox enter --name "$BOX" -- bash -c '
  set -euo pipefail
  sudo pacman -Syu --noconfirm
  sudo pacman -S --noconfirm base-devel git
  cd /tmp
  rm -rf yay-bin
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si --noconfirm
'

echo ""
echo "=== Installing Stremio and codecs ==="
distrobox enter --name "$BOX" -- bash -c '
  set -euo pipefail
  yay -S --noconfirm stremio-enhanced-bin ffmpeg gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
'

echo ""
echo "=== Downloading Stremio server.js ==="
distrobox enter --name "$BOX" -- bash -c '
  set -euo pipefail
  mkdir -p "$HOME/.config/stremio-enhanced/streamingserver"
  wget -O "$HOME/.config/stremio-enhanced/streamingserver/server.js" \
    "https://dl.strem.io/server/v4.20.18/desktop/server.js"
'

echo ""
echo "=== Exporting Stremio as native app ==="
distrobox enter --name "$BOX" -- distrobox-export --app stremio-enhanced

# ── Flatpaks ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Installing Flatpaks ==="
flatpak install -y flathub org.gnome.eog

echo ""
echo "Done."
