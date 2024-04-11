#! /usr/bin/sh

# ==============================================================

# "Colors"
plasma-apply-colorscheme 'Gruvbox Light - Red two-tone 3'
plasma-apply-colorscheme -a palegreen

# "Cursors"
plasma-apply-cursortheme oreo_spark_lime_cursors

# "Icons" (full path!)
/usr/lib/plasma-changeicons BeautySolar

# Kvantum
kvantummanager --set Gruvbox_Light_Green

# Activate Linux
killall activate-linux 2&> /dev/null
activate-linux -t "啟用 Arch Linux" -m "移至 [設定] 以啟用 Arch Linux" -G -d
