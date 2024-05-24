#! /usr/bin/sh

# ==============================================================

# "Colors"
plasma-apply-colorscheme GruvboxColors
plasma-apply-colorscheme -a palegreen

# "Cursors"
plasma-apply-cursortheme Bibata-Rainbow-Modern >/dev/null 2>&1

# "Icons" (full path!)
/usr/lib/plasma-changeicons BeautyLine >/dev/null 2>&1

# Activate Linux
killall activate-linux >/dev/null 2>&1
activate-linux -t "啟用 Arch Linux" -m "移至 [設定] 以啟用 Arch Linux" -G -d
kvantummanager --set Gruvbox-Dark-Brown
plasma-apply-wallpaperimage ~/.local/share/wallpapers/boiling-microsoft-dark.png
