#!/bin/bash
# ==============================================================================
# Description: System backup and restoration utility for Arch Linux environments.
#              Handles Docker volumes, native/AUR packages, and custom directories.
# ==============================================================================

set -e

# ==========================================
# 0. PRIVILEGE AND ENVIRONMENT VALIDATION
# ==========================================
if [ -z "$SUDO_USER" ]; then
    echo "Error: This script must be executed with sudo privileges."
    echo "Root access is required for volume operations and external drive modifications."
    exit 1
fi

REAL_USER="$SUDO_USER"
REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

echo "Notice: Operating on behalf of user '$REAL_USER' (Home: $REAL_HOME)"

# ==========================================
# GLOBAL CONFIGURATION
# ==========================================
BACKUP_BASE="/run/media/olivertzeng/Aburi1"
DOCKER_COMPOSE_DIR="$REAL_HOME/docker"
ZSH_HIST_FILE="$REAL_HOME/.zsh_history"
MODS_DIR="$REAL_HOME/.local/share/casual-pre-loader/mods/addons"

# ==========================================
# FUNCTION: BACKUP
# ==========================================
do_backup() {
    local backup_dest="${BACKUP_BASE}/backup_$(date +%Y%m%d_%H%M)"

    echo "------------------------------------------"
    echo " Initiating Backup Protocol"
    echo "------------------------------------------"

    mkdir -p "$backup_dest/volumes"
    echo "[1/5] Initialized backup directory at $backup_dest"

    echo "[2/5] Extracting package lists..."
    if [ -f "$ZSH_HIST_FILE" ]; then
        awk -F ';' '{print $NF}' "$ZSH_HIST_FILE" | \
        grep -E '^(pacin|yain|yay -S|sudo pacman -S) ' | \
        sed -E 's/^(pacin|yain|yay -S|sudo pacman -S) //' | \
        grep -E -v '^(pacrem|yarem|yay -R|sudo pacman -R) ' | \
        tr ' ' '\n' | grep -v '^-' | grep -v '^sudo$' | grep -v '^$' | sort -u > "$backup_dest/history_pacman_aur.txt"

        awk -F ';' '{print $NF}' "$ZSH_HIST_FILE" | \
        grep -E '^pip install ' | \
        sed -E 's/^pip install //' | \
        grep -E -v '^pip uninstall ' | \
        tr ' ' '\n' | grep -v '^-' | grep -v '^$' | sort -u > "$backup_dest/history_pip.txt"
        echo "      Zsh history parsing completed."
    else
        echo "      Warning: $ZSH_HIST_FILE not found."
    fi

    pacman -Qqe > "$backup_dest/native_pacman_aur.txt"
    sudo -u "$REAL_USER" pip freeze > "$backup_dest/native_pip.txt" 2>/dev/null || echo "pip not installed" > "$backup_dest/native_pip.txt"
    echo "      Native package lists exported."

    echo "[3/5] Processing Docker Named Volumes..."
    if systemctl is-active --quiet docker; then
        local running_containers
        running_containers=$(docker ps -q)
        if [ -n "$running_containers" ]; then
            docker stop $running_containers
        fi

        local volumes
        volumes=$(docker volume ls -q)
        for vol in $volumes; do
            echo "      Archiving volume: $vol"
            docker run --rm \
                -v "$vol":/source_vol:ro \
                -v "$backup_dest/volumes":/backup_dest \
                alpine tar -cpf "/backup_dest/${vol}.tar" -C /source_vol .
        done
    else
        echo "      Warning: Docker daemon is inactive. Skipping volume backup."
    fi

    echo "[4/5] Archiving Docker bind mounts..."
    if systemctl is-active --quiet docker; then
        systemctl stop docker docker.socket
    fi

    if [ -d "$DOCKER_COMPOSE_DIR" ]; then
        tar --zstd -cpf "$backup_dest/docker_bind_mounts.tar.zst" "$DOCKER_COMPOSE_DIR"
        echo "      $DOCKER_COMPOSE_DIR archived."
    else
        echo "      Warning: $DOCKER_COMPOSE_DIR not found."
    fi

    systemctl start docker || true

    echo "[5/5] Archiving application modifications..."
    if [ -d "$MODS_DIR" ]; then
        tar --zstd -cpf "$backup_dest/casual_addons.tar.zst" -C "$REAL_HOME" ".local/share/casual-pre-loader/mods/addons"
        echo "      Modifications archived."
    else
        echo "      Warning: $MODS_DIR not found. Skipping."
    fi

    echo "------------------------------------------"
    echo " Backup completed successfully."
    echo " Destination: $backup_dest"
    echo "------------------------------------------"
}

# ==========================================
# FUNCTION: RESTORE
# ==========================================
do_restore() {
    echo "------------------------------------------"
    echo " Initiating Restore Protocol"
    echo "------------------------------------------"

    if [ ! -d "$BACKUP_BASE" ]; then
        echo "Error: Base directory $BACKUP_BASE does not exist."
        exit 1
    fi

    echo "Available backups in $BACKUP_BASE:"
    local options=()
    while IFS= read -r dir; do
        options+=("$dir")
    done < <(ls -1td "$BACKUP_BASE"/backup_* 2>/dev/null)

    if [ ${#options[@]} -eq 0 ]; then
        echo "No backup archives found in $BACKUP_BASE."
        exit 1
    fi

    for i in "${!options[@]}"; do
        echo "[$i] $(basename "${options[$i]}")"
    done

    echo ""
    read -p "Select a backup index to restore (0-$(( ${#options[@]} - 1 ))): " sel_idx

    if ! [[ "$sel_idx" =~ ^[0-9]+$ ]] || [ "$sel_idx" -ge "${#options[@]}" ]; then
        echo "Error: Invalid selection."
        exit 1
    fi

    local backup_src="${options[$sel_idx]}"
    echo "Selected archive: $backup_src"

    echo "[1/4] Restoring system packages..."
    echo "Available package lists:"
    echo "1) Parsed list from .zsh_history (Custom/Historical)"
    echo "2) Native list from pacman -Qqe (System snapshot)"
    read -p "Select list source [1 or 2]: " pkg_choice

    local list_file
    if [ "$pkg_choice" == "1" ]; then
        list_file="$backup_src/history_pacman_aur.txt"
    else
        list_file="$backup_src/native_pacman_aur.txt"
    fi

    if [ -f "$list_file" ]; then
        echo "Initiating package installation..."
        while IFS= read -r pkg; do
            if [ -n "$pkg" ]; then
                echo "Installing: $pkg"
                sudo -u "$REAL_USER" yay -S --needed --noconfirm "$pkg" || echo "      Warning: Failed to install $pkg."
            fi
        done < "$list_file"
    else
        echo "      Warning: Package list not found. Skipping phase."
    fi

    echo "[2/4] Restoring Docker bind mounts..."
    if [ -f "$backup_src/docker_bind_mounts.tar.zst" ]; then
        systemctl stop docker docker.socket || true
        tar --zstd -xpf "$backup_src/docker_bind_mounts.tar.zst" -C /
        echo "      Bind mounts restored."
        systemctl start docker || true
    else
        echo "      Warning: docker_bind_mounts.tar.zst not found."
    fi

    echo "[3/4] Restoring Docker Named Volumes..."
    if [ -d "$backup_src/volumes" ]; then
        for vol_tar in "$backup_src/volumes"/*.tar; do
            [ -f "$vol_tar" ] || continue

            local vol_name
            vol_name=$(basename "$vol_tar" .tar)
            echo "      Restoring volume: $vol_name"

            docker volume create "$vol_name" > /dev/null
            docker run --rm \
                -v "$vol_name":/target_vol \
                -v "$backup_src/volumes":/backup_src:ro \
                alpine tar -xpf "/backup_src/$(basename "$vol_tar")" -C /target_vol
        done
    else
        echo "      Warning: No named volumes directory found."
    fi

    echo "[4/4] Restoring application modifications..."
    if [ -f "$backup_src/casual_addons.tar.zst" ]; then
        sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/.local/share"
        tar --zstd -xpf "$backup_src/casual_addons.tar.zst" -C "$REAL_HOME"
        echo "      Modifications restored."
    else
        echo "      Warning: casual_addons.tar.zst not found."
    fi

    echo "------------------------------------------"
    echo " Restoration completed successfully."
    echo "------------------------------------------"
}

# ==========================================
# CLI ARGUMENT PARSING
# ==========================================
show_help() {
    echo "Usage: sudo $0 [-b | -r | -h]"
    echo "  -b    Execute backup procedure"
    echo "  -r    Execute restore procedure"
    echo "  -h    Display this help message"
}

while getopts "brh" opt; do
    case ${opt} in
        b ) do_backup; exit 0 ;;
        r ) do_restore; exit 0 ;;
        h ) show_help; exit 0 ;;
        \? ) show_help; exit 1 ;;
    esac
done

if [ $OPTIND -eq 1 ]; then
    echo "System Backup and Restoration Utility"
    read -p "Select an action - (b)ackup, (r)estore, or (q)uit [b/r/q]: " user_action

    case "$user_action" in
        b|B|backup ) do_backup ;;
        r|R|restore ) do_restore ;;
        q|Q|quit ) echo "Exited."; exit 0 ;;
        * ) echo "Error: Invalid selection. Exited."; exit 1 ;;
    esac
fi
