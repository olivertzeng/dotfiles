#!/bin/bash

# Set default shift amount to 1 and list to 1
list=${1:-1}
shift=${2:-1}

# Check if the shift amount is an integer
if ! [[ $shift =~ ^-?[0-9]+$ ]]; then
	echo "Error: Shift amount must be an integer"
	exit 1
fi

# Define directories and album names
declare -A directories
directories[1]="Music/topgrade"
directories[0]="Music/kyuKurarin"

# Check if list is a valid option (0 or 1)
if ! [[ $list =~ ^[01]$ ]]; then
	echo "Error: List must be 0 or 1"
	exit 1
fi

# Get the directory and album name based on the list option
directory=${directories[$list]}
album_name=$([ $list -eq 1 ] && echo "topgrade" || echo "kyuKurarin")

# Loop through m4a files in the specified directory
for file in "$directory"/*.m4a; do
	# Check if file exists
	if [ ! -f "$file" ]; then
		continue
	fi

	track_number=$(ffprobe -v quiet -print_format json -show_entries format_tags=track -of default=noprint_wrappers=1:nokey=1 "$file")

	# Check if track number is available
	if [ -z "$track_number" ]; then
		echo "Warning: Track number not found for $file"
		continue
	fi

	# Calculate the new track number
	new_track_number=$((track_number + shift))
	tageditor set album=$album_name track=$new_track_number --force-rewrite --files "$file"
	rm "$directory"/*.bak
done
