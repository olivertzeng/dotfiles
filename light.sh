#! /usr/bin/sh

# ==============================================================

# "Colors"
plasma-apply-colorscheme 'Gruvbox Light - Red two-tone 3'
plasma-apply-colorscheme -a palegreen

# "Cursors"
plasma-apply-cursortheme miku-cursor-linux >/dev/null 2>&1

# "Icons" (full path!)
/usr/lib/plasma-changeicons BeautySolar >/dev/null 2>&1

# Kvantum
kvantummanager --set Gruvbox_Light_Green

# Activate Linux
killall activate-linux >/dev/null 2>&1
activate-linux -t "啟用 Arch Linux" -m "移至 [設定] 以啟用 Arch Linux" -G -d
plasma-apply-wallpaperimage ~/.local/share/wallpapers/boiling-microsoft-light.png
