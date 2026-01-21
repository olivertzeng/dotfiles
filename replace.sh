#!/bin/bash

# Define the replacement rules
MAP_FILE="dict.txt"

# Parse rules into array: map=(from1 to1 from2 to2 ...)
map=()
while IFS=$'\t' read -r from to || [ -n "$from" ]; do
	# tab 分隔，不用再檢查
	from="${from//[[:space:]]}"
	to="${to//[[:space:]]}"
	[ -z "$from" ] && continue
	[[ "$from" =~ ^# ]] && continue
	map+=("$from" "$to")
done < "$MAP_FILE"

if [ $((${#map[@]} % 2)) -ne 0 ]; then
	echo "Error: invalid rules" >&2
	exit 1
fi

# Helper: escape for sed
escape_sed() {
	printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

# Determine input files:
# - If one argument provided: use that file (error if not exists)
# - If no argument: find all *.json excluding *TW.json in current directory; error if none found
input_files=()
if [ $# -ge 1 ]; then
	input_file="$1"
	if [ ! -f "$input_file" ]; then
		echo "Error: Input file '$input_file' not found" >&2
		exit 1
	fi
	input_files+=("$input_file")
else
	# shellglob for *.json excluding *TW.json
	shopt -s nullglob
	for f in *.json *.txt; do
		case "$f" in
		*TW.json | *TW.txt ) continue ;;
		*) input_files+=("$f") ;;
		esac
	done
	shopt -u nullglob

	if [ ${#input_files[@]} -eq 0 ]; then
		echo "Error: no .json .txt files found (excluding *TW.json *TW.txt)" >&2
		exit 1
	fi
fi

# Process each input file
for input_file in "${input_files[@]}"; do
	output_file="${input_file%.*}TW.${input_file##*.}"
	opencc -i "$input_file" -o "$output_file" -c s2twp

	# Apply replacements
	for ((i = 0; i < ${#map[@]}; i += 2)); do
		src="$(escape_sed "${map[i]}")"
		dst="$(escape_sed "${map[i + 1]}")"
		if sed --version >/dev/null 2>&1; then
			sed -i "s|$src|$dst|g" "$output_file"
		else
			sed -i '' "s|$src|$dst|g" "$output_file"
		fi
	done

	echo "Wrote: $output_file"
done
