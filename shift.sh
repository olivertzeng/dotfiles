#!/usr/bin/env bash

# ------------------------------------------------------------
# Usage: ./shift.sh <album_folder> [shift_amount]
#   <album_folder>   Name of the folder inside ~/Music
#   [shift_amount]   Integer to add to each track number (default: 1)
# ------------------------------------------------------------

album_folder=${1:-topgrade}          # default album if none supplied
shift_amount=${2:-1}                 # default shift = +1

if ! [[ $shift_amount =~ ^-?[0-9]+$ ]]; then
    echo "Error: shift amount must be an integer"
    exit 1
fi

music_dir="${HOME}/Music"
album_dir="${music_dir}/${album_folder}"

if [[ ! -d "$album_dir" ]]; then
    echo "Error: album folder '$album_folder' does not exist under $music_dir"
    exit 1
fi

shopt -s nullglob   # make the for‑loop skip if no matches
for file in "$album_dir"/*.m4a; do
    track_number=$(ffprobe -v quiet -print_format json \
        -show_entries format_tags=track \
        -of default=noprint_wrappers=1:nokey=1 "$file")
    if [[ -z $track_number ]]; then
        echo "Warning: no track number in $file – skipping"
        continue
    fi
    new_track=$((track_number + shift_amount))
    tageditor set album="$album_folder" track="$new_track" \
        --force-rewrite --files "$file"
    rm -f "$album_dir"/*.bak
done

echo "Done. Processed files in '$album_dir' with shift $shift_amount."
