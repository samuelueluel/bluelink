#!/usr/bin/env bash
# NOTE: Tailscale must be set up manually after running this script — run `tailscale up` and authenticate via the printed URL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX="arch-box"
SKIP_DISTROBOX=false

for arg in "$@"; do
  case "$arg" in
    --skip-distrobox) SKIP_DISTROBOX=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ── Error trap ────────────────────────────────────────────────────────────────
trap 'echo ""; echo "❌ FAILED at line $LINENO: $BASH_COMMAND"; exit 1' ERR

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

# ── Auto-login ────────────────────────────────────────────────────────────────
echo ""
echo "=== Enabling auto-login for $USER ==="
sudo tee /etc/gdm/custom.conf > /dev/null << EOF || echo "WARNING: could not set auto-login (skipping — configure manually if needed)"
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

echo ""
echo "=== Refreshing font cache ==="
fc-cache -f

# ── Ptyxis: terminal font ─────────────────────────────────────────────────────
echo ""
echo "=== Setting Ptyxis font to JetBrains Mono Nerd Font ==="
if gsettings list-schemas 2>/dev/null | grep -q "org.gnome.Ptyxis"; then
  PTYXIS_PROFILES=$(gsettings get org.gnome.Ptyxis profiles 2>/dev/null \
    | tr -d "[]' " | tr ',' '\n') || PTYXIS_PROFILES=""
  if [ -z "$PTYXIS_PROFILES" ]; then
    echo "No Ptyxis profiles found — open Ptyxis once and rerun to apply font"
  else
    for _PROFILE in $PTYXIS_PROFILES; do
      [ -z "$_PROFILE" ] && continue
      _PATH="org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$_PROFILE/"
      gsettings set "$_PATH" use-system-font false
      gsettings set "$_PATH" custom-font 'JetBrainsMono Nerd Font 12'
      echo "  Set font on profile $_PROFILE"
    done
  fi
else
  echo "Ptyxis not found — skipping font config"
fi

# ── Arch distrobox ────────────────────────────────────────────────────────────
echo ""
if $SKIP_DISTROBOX; then
  echo "=== Skipping distrobox setup (--skip-distrobox) ==="
else
  echo "=== Removing existing distrobox and exports ==="
  distrobox rm --force --yes "$BOX" 2>/dev/null || true
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
fi

# ── Fedora distrobox (RustDesk) ───────────────────────────────────────────────
echo ""
echo "=== Removing existing fedora-box and exports ==="
distrobox rm --force --yes fedora-box 2>/dev/null || true
rm -f "$HOME/.local/share/applications/"*rustdesk* 2>/dev/null || true
rm -f "$HOME/.local/bin/"*rustdesk* 2>/dev/null || true

echo ""
echo "=== Creating Fedora distrobox ==="
distrobox create --name fedora-box --image fedora:latest --yes

echo ""
echo "=== Installing RustDesk in fedora-box ==="
distrobox enter --name fedora-box -- bash -c '
  set -euo pipefail
  sudo dnf install -y wget
  RUSTDESK_VER=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
    | grep "tag_name" | sed 's/.*"v\([^"]*\)".*/\1/')
  wget -O /tmp/rustdesk.rpm \
    "https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VER}/rustdesk-${RUSTDESK_VER}-0.x86_64.rpm"
  sudo dnf install -y /tmp/rustdesk.rpm
'

echo ""
echo "=== Enabling RustDesk service ==="
distrobox enter --name fedora-box -- bash -c '
  set -euo pipefail
  sudo systemctl enable --now rustdesk
'

echo ""
echo "=== Exporting RustDesk as native app ==="
distrobox enter --name fedora-box -- distrobox-export --app rustdesk

# ── Flatpaks ──────────────────────────────────────────────────────────────────
echo ""
echo "=== Installing Flatpaks ==="
flatpak install -y flathub org.kde.gwenview

echo ""
echo "Done."
