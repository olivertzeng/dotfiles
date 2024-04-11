#! /usr/bin/sh

# ==============================================================

# "Colors"
plasma-apply-colorscheme GruvboxColors
plasma-apply-colorscheme -a palegreen

# "Cursors"
plasma-apply-cursortheme oreo_spark_violet_cursors

# "Icons" (full path!)
/usr/lib/plasma-changeicons BeautyLine

# Activate Linux
killall activate-linux 2&> /dev/null
activate-linux -t "啟用 Arch Linux" -m "移至 [設定] 以啟用 Arch Linux" -G -d
kvantummanager --set Gruvbox-Dark-Brown
