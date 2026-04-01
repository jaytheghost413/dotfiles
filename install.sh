#!/bin/bash

set -e

export LC_MESSAGES=C
export LANG=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo." >&2
    exit 1
fi

if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    ACTUAL_USER="$SUDO_USER"
else
    ACTUAL_USER=$(logname 2>/dev/null)
fi

if [ -z "$ACTUAL_USER" ] || [ "$ACTUAL_USER" = "root" ]; then
    echo "ERROR: Could not determine non-root user. Run with sudo from your user."
    exit 1
fi

ACTUAL_USER_HOME=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)

echo "Installing dotfiles for user: $ACTUAL_USER"

echo "[1/5] Installing base-devel and yay..."
pacman -S --needed --noconfirm git base-devel
if ! command -v yay &> /dev/null; then
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd /tmp
    rm -rf yay
fi

echo "[2/5] Setting up Chaotic AUR..."
if ! grep -q "chaotic-aur" /etc/pacman.conf; then
    pacman -Sy --noconfirm chaotic-aur
fi

echo "[3/5] Installing packages..."
PACKAGES_FILE="$SCRIPT_DIR/packages.txt"
if [ -f "$PACKAGES_FILE" ]; then
    mapfile -t PACKAGES < <(pacman -Qsq | comm -12 - <(sort "$PACKAGES_FILE"))
    if [ ${#PACKAGES[@]} -gt 0 ]; then
        pacman -S --noconfirm "${PACKAGES[@]}"
    fi
fi

echo "[4/5] Deploying configs..."
CONFIG_SOURCE="$SCRIPT_DIR/.config"
if [ -d "$CONFIG_SOURCE" ]; then
    for config_dir in "$CONFIG_SOURCE"/*; do
        if [ -d "$config_dir" ]; then
            config_name=$(basename "$config_dir")
            target_dir="$ACTUAL_USER_HOME/.config/$config_name"
            
            if [ -d "$target_dir" ]; then
                backup_suffix=$(date +%Y%m%d%H%M%S)
                cp -r "$target_dir" "$target_dir.bak.$backup_suffix"
                echo "  Backed up $config_name to $target_dir.bak.$backup_suffix"
            fi
            
            cp -r "$config_dir" "$target_dir"
            chown -R "$ACTUAL_USER:$ACTUAL_USER" "$target_dir"
            echo "  Deployed $config_name"
        fi
    done
fi

echo "[5/5] Symlinking user files..."
if [ -f "$SCRIPT_DIR/.bashrc" ]; then
    cp "$SCRIPT_DIR/.bashrc" "$ACTUAL_USER_HOME/.bashrc"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_USER_HOME/.bashrc"
fi

if [ -f "$SCRIPT_DIR/.zshrc" ]; then
    cp "$SCRIPT_DIR/.zshrc" "$ACTUAL_USER_HOME/.zshrc"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_USER_HOME/.zshrc"
fi

if [ -d "$SCRIPT_DIR/Wallpapers" ]; then
    mkdir -p "$ACTUAL_USER_HOME/Pictures"
    cp -r "$SCRIPT_DIR/Wallpapers" "$ACTUAL_USER_HOME/Pictures/"
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_USER_HOME/Pictures"
fi

echo ""
echo "Done! Rebooting in 10 seconds..."
sleep 10
reboot
