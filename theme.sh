#!/bin/bash

killall activate-linux >/dev/null 2>&1
activate-linux -t "啟用 Arch Linux" -m "移至 [設定] 以啟用 Arch Linux" -G -d
# Get the location from the location.sh script
location=$(curl -s 'https://ipinfo.io/json' | jq -r '.loc')

# Use sunwait to get the sunrise and sunset times
sunrise=$(sunwait sunrise $location)
sunset=$(sunwait sunset $location)

# Execute your script between sunrise and sunset
if [ "$sunrise" -lt "$SECONDS" ] && [ "$SECONDS" -lt "$sunset" ]; then
	plasma-apply-colorscheme 'Gruvbox Light - Red two-tone 3'
	plasma-apply-cursortheme miku-cursor-linux >/dev/null 2>&1
	/usr/lib/plasma-changeicons BeautySolar >/dev/null 2>&1
	kvantummanager --set Gruvbox_Light_Green
	plasma-apply-wallpaperimage ~/.local/share/wallpapers/boiling-microsoft-light.png
else
	plasma-apply-colorscheme GruvboxColors
	plasma-apply-cursortheme Bibata-Rainbow-Modern >/dev/null 2>&1
	/usr/lib/plasma-changeicons BeautyLine >/dev/null 2>&1
	kvantummanager --set Gruvbox-Dark-Brown
	plasma-apply-wallpaperimage ~/.local/share/wallpapers/boiling-microsoft-dark.png
fi
