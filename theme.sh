#!/bin/bash

location=$(curl -s 'https://ipinfo.io/json' | jq -r '.loc')
lat=$(echo $location | cut -d, -f1)
lon=$(echo $location | cut -d, -f2)
lat_dir="N"
lon_dir="E"
if awk "BEGIN {exit !($lat < 0)}"; then lat_dir="S"; fi
if awk "BEGIN {exit !($lon < 0)}"; then lon_dir="W"; fi

if [ "$(sunwait poll ${lat}${lat_dir} ${lon}${lon_dir})" = "DAY" ]; then
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
