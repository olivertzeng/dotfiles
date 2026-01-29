#!/bin/bash

# Credit for PNG metadata handling: https://github.com/IlllllIII/png_to_json

# Get script directory for finding dict files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
MAP_FILE="$SCRIPT_DIR/dict.txt"
CONTROVERSIAL_FILE="$SCRIPT_DIR/controversial.txt"

# Supported extensions for auto-discovery
SUPPORTED_EXTENSIONS=("txt" "json" "jsonl" "md" "po" "strings" "png" "PNG")

# Flags
USE_CONTROVERSIAL=false
REVERSE_MODE=false
JSON_MODE="" # "", "o", "cn", "tw"
INCLUDE_HIDDEN=false
CUSTOM_OUTPUT=false

# Arrays for custom output
declare -a OUTPUT_FILES

# Usage
usage() {
	cat <<EOF
Usage: $0 [-c] [-r] [-j [MODE]] [-h] [files...] [-o output_files...]

Options:
  -c          Enable controversial replacements (auto-enabled for PNG)
  -r          Reverse mode: TW -> CN conversion
  -j [MODE]   PNG to JSON extraction mode (default: o):
              o, original  - Extract JSON without conversion
              c, cn        - Extract and convert to Simplified Chinese
              t, tw        - Extract and convert to Traditional Chinese
  -h          Include hidden files (dotfiles) when auto-discovering files
              (only works when no specific files are provided)
  -o          Specify output filenames (must match number of input files)

Auto-detection:
  When no files are specified, the script:
  - Converts Simplified -> Traditional (or reverse with -r)
  - Skips if counterpart file already exists (e.g., both 依樱.png and 依櫻.png)

Supported file types for auto-discovery:
  .txt .json .jsonl .md .po .strings .png

Examples:
  $0                              # Auto-detect and convert files
  $0 -h                           # Include hidden files
  $0 file.json                    # Convert specific file
  $0 *.json                       # Convert all JSON files
  $0 -r                           # Reverse: convert TW to CN
  $0 character.png                # Convert PNG character card
  $0 -j character.png             # Extract original JSON from PNG
  $0 a.png -o b.png               # Convert a.png, output as b.png
  $0 a.png b.png -o c.png d.png   # a.png->c.png, b.png->d.png
EOF
	exit 0
}

# Parse options - handle -j with optional argument
while getopts ":crj:hH" opt; do
	case $opt in
	c) USE_CONTROVERSIAL=true ;;
	r) REVERSE_MODE=true ;;
	j)
		if [ -z "$OPTARG" ] || [[ "$OPTARG" == -* ]]; then
			JSON_MODE="o"
			if [[ "$OPTARG" == -* ]]; then
				((OPTIND--))
			fi
		else
			case "$OPTARG" in
			o | original) JSON_MODE="o" ;;
			c | cn) JSON_MODE="cn" ;;
			t | tw) JSON_MODE="tw" ;;
			*)
				JSON_MODE="o"
				((OPTIND--))
				;;
			esac
		fi
		;;
	h | H) INCLUDE_HIDDEN=true ;;
	:)
		if [ "$OPTARG" = "j" ]; then
			JSON_MODE="o"
		else
			echo "Error: Option -$OPTARG requires an argument" >&2
			exit 1
		fi
		;;
	\?)
		# Could be -o, let it pass through
		if [ "$OPTARG" != "o" ]; then
			echo "Error: Invalid option -$OPTARG" >&2
			usage
		else
			((OPTIND--))
			break
		fi
		;;
	esac
done
shift $((OPTIND - 1))

# Show help if --help
for arg in "$@"; do
	if [ "$arg" = "--help" ]; then
		usage
	fi
done

# Parse remaining arguments for -o flag
input_args=()
output_args=()
found_o=false

for arg in "$@"; do
	if [ "$arg" = "-o" ]; then
		found_o=true
		CUSTOM_OUTPUT=true
		continue
	fi

	if [ "$found_o" = true ]; then
		output_args+=("$arg")
	else
		input_args+=("$arg")
	fi
done

# Validate -o usage
if [ "$CUSTOM_OUTPUT" = true ]; then
	if [ ${#input_args[@]} -eq 0 ]; then
		echo "Error: -o requires input files to be specified" >&2
		echo "Usage: $0 input_file(s) -o output_file(s)" >&2
		exit 1
	fi

	if [ ${#output_args[@]} -eq 0 ]; then
		echo "Error: -o requires output filenames" >&2
		echo "Usage: $0 input_file(s) -o output_file(s)" >&2
		exit 1
	fi

	if [ ${#output_args[@]} -ne ${#input_args[@]} ]; then
		echo "Error: number of output files (${#output_args[@]}) must match number of input files (${#input_args[@]})" >&2
		echo "Hint: -o cannot be used with glob patterns unless counts match" >&2
		exit 1
	fi

	# Check for conflicts: output file would overwrite a pending input file
	for ((i = 0; i < ${#output_args[@]}; i++)); do
		out="${output_args[i]}"
		for ((j = i + 1; j < ${#input_args[@]}; j++)); do
			in="${input_args[j]}"
			# Resolve to absolute paths for comparison
			out_real=$(realpath -m "$out" 2>/dev/null || echo "$out")
			in_real=$(realpath -m "$in" 2>/dev/null || echo "$in")
			if [ "$out_real" = "$in_real" ]; then
				echo "Error: output file '$out' would overwrite pending input file '$in'" >&2
				echo "Hint: reorder your files so '$in' is processed before it gets overwritten" >&2
				exit 1
			fi
		done
	done

	OUTPUT_FILES=("${output_args[@]}")
fi

# Check required files
if [ ! -f "$MAP_FILE" ]; then
	echo "Error: dict.txt not found at $SCRIPT_DIR" >&2
	exit 1
fi

# Parse rules into array - TAB separated, preserve internal spaces
load_rules() {
	local file="$1"
	local reverse="$2"
	[ ! -f "$file" ] && return
	while IFS=$'\t' read -r from to || [ -n "$from" ]; do
		[ -z "$from" ] && continue
		[[ "$from" =~ ^[[:space:]]*# ]] && continue
		from="$(echo "$from" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		to="$(echo "$to" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		[ -z "$from" ] || [ -z "$to" ] && continue
		if [ "$reverse" = true ]; then
			map+=("$to" "$from")
		else
			map+=("$from" "$to")
		fi
	done <"$file"
}

# Load all rules (dict.txt first, then controversial.txt if enabled)
load_all_rules() {
	local reverse="$1"
	map=()
	load_rules "$MAP_FILE" "$reverse"
	if [ "$USE_CONTROVERSIAL" = true ] && [ -f "$CONTROVERSIAL_FILE" ]; then
		load_rules "$CONTROVERSIAL_FILE" "$reverse"
	fi
}

# Initial load
load_all_rules "$REVERSE_MODE"

# Helper: escape for sed
escape_sed() {
	printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

# Check if string contains Chinese characters
contains_chinese() {
	python3 -c "import sys; sys.exit(0 if any('\u4e00' <= c <= '\u9fff' for c in sys.argv[1]) else 1)" "$1" 2>/dev/null
}

# Translate a string using opencc and dictionary rules
translate_string() {
	local input="$1"
	local reverse="$2"
	local result

	if [ "$reverse" = true ]; then
		result=$(echo "$input" | opencc -c tw2s)
	else
		result=$(echo "$input" | opencc -c s2tw)
	fi

	local temp_map=()
	while IFS=$'\t' read -r from to || [ -n "$from" ]; do
		[ -z "$from" ] && continue
		[[ "$from" =~ ^[[:space:]]*# ]] && continue
		from="$(echo "$from" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		to="$(echo "$to" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		[ -z "$from" ] || [ -z "$to" ] && continue
		if [ "$reverse" = true ]; then
			temp_map+=("$to" "$from")
		else
			temp_map+=("$from" "$to")
		fi
	done <"$MAP_FILE"

	if [ -f "$CONTROVERSIAL_FILE" ]; then
		while IFS=$'\t' read -r from to || [ -n "$from" ]; do
			[ -z "$from" ] && continue
			[[ "$from" =~ ^[[:space:]]*# ]] && continue
			from="$(echo "$from" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
			to="$(echo "$to" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
			[ -z "$from" ] || [ -z "$to" ] && continue
			if [ "$reverse" = true ]; then
				temp_map+=("$to" "$from")
			else
				temp_map+=("$from" "$to")
			fi
		done <"$CONTROVERSIAL_FILE"
	fi

	for ((i = 0; i < ${#temp_map[@]}; i += 2)); do
		src="$(escape_sed "${temp_map[i]}")"
		dst="$(escape_sed "${temp_map[i + 1]}")"
		result=$(echo "$result" | sed "s|$src|$dst|g")
	done

	echo "$result"
}

# Check if file should be skipped based on name patterns
# Check if file should be skipped based on name patterns
should_skip_file() {
	local filename="$1"
	local basename="${filename%.*}"

	case "$filename" in
	dict.txt | controversial.txt) return 0 ;;
	"$SCRIPT_NAME") return 0 ;;
	esac

	# Skip files that look like output files (TW patterns) in normal mode
	if [ "$REVERSE_MODE" = false ]; then
		if [[ "$basename" =~ zh_TW$ ]] ||
			[[ "$basename" =~ zh-TW$ ]] ||
			[[ "$basename" =~ zh_tw$ ]] ||
			[[ "$basename" =~ zh-tw$ ]] ||
			[[ "$basename" =~ TW$ ]]; then
			return 0
		fi
	fi

	# Skip files that look like output files (CN patterns) in reverse mode
	if [ "$REVERSE_MODE" = true ]; then
		if [[ "$basename" =~ zh_CN$ ]] ||
			[[ "$basename" =~ zh-CN$ ]] ||
			[[ "$basename" =~ zh_cn$ ]] ||
			[[ "$basename" =~ zh-cn$ ]] ||
			[[ "$basename" =~ CN$ ]]; then
			return 0
		fi
	fi

	return 1
}

# Generate output filename with translation
generate_output_filename() {
	local input_file="$1"
	local reverse="$2"
	local dir=$(dirname "$input_file")
	local filename=$(basename "$input_file")
	local ext="${filename##*.}"
	local basename
	local has_ext=true

	if [ "$filename" = "$ext" ]; then
		basename="$filename"
		has_ext=false
	else
		basename="${filename%.*}"
	fi

	local new_basename
	local output_filename

	if [ "$reverse" = true ]; then
		# TW -> CN conversion
		if [[ "$basename" =~ ^(.*)zh_TW$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh_CN"
		elif [[ "$basename" =~ ^(.*)zh-TW$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh-CN"
		elif [[ "$basename" =~ ^(.*)zh_tw$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh_cn"
		elif [[ "$basename" =~ ^(.*)zh-tw$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh-cn"
		elif [[ "$basename" =~ ^(.*)zh$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh_CN"
		elif [[ "$basename" =~ ^(.*)TW$ ]]; then
			new_basename="${BASH_REMATCH[1]}CN"
		elif contains_chinese "$basename"; then
			local translated=$(translate_string "$basename" true)
			if [ "$translated" != "$basename" ]; then
				new_basename="$translated"
			else
				new_basename="${basename}CN"
			fi
		else
			new_basename="${basename}CN"
		fi
	else
		# CN -> TW conversion
		if [[ "$basename" =~ ^(.*)zh_CN$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh_TW"
		elif [[ "$basename" =~ ^(.*)zh-CN$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh-TW"
		elif [[ "$basename" =~ ^(.*)zh_cn$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh_tw"
		elif [[ "$basename" =~ ^(.*)zh-cn$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh-tw"
		elif [[ "$basename" =~ ^(.*)zh$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh_TW"
		elif [[ "$basename" =~ ^(.*)CN$ ]]; then
			new_basename="${BASH_REMATCH[1]}TW"
		elif contains_chinese "$basename"; then
			local translated=$(translate_string "$basename" false)
			if [ "$translated" != "$basename" ]; then
				new_basename="$translated"
			else
				new_basename="${basename}TW"
			fi
		else
			new_basename="${basename}TW"
		fi
	fi

	if [ "$has_ext" = true ]; then
		if [ "$dir" = "." ]; then
			output_filename="${new_basename}.${ext}"
		else
			output_filename="${dir}/${new_basename}.${ext}"
		fi
	else
		if [ "$dir" = "." ]; then
			output_filename="${new_basename}"
		else
			output_filename="${dir}/${new_basename}"
		fi
	fi

	echo "$output_filename"
}

# Check if file has supported extension
has_supported_extension() {
	local filename="$1"
	local ext="${filename##*.}"

	if [ "$filename" = "$ext" ]; then
		return 1
	fi

	for supported in "${SUPPORTED_EXTENSIONS[@]}"; do
		if [ "$ext" = "$supported" ]; then
			return 0
		fi
	done
	return 1
}

# Check if counterpart file exists
# Returns 0 if counterpart exists (should skip), 1 otherwise
counterpart_exists() {
	local input_file="$1"
	local reverse="$2"
	local output_file=$(generate_output_filename "$input_file" "$reverse")

	if [ -f "$output_file" ]; then
		return 0
	fi

	return 1
}

# Check if two paths refer to the same file
same_file() {
	local file1="$1"
	local file2="$2"

	local real1=$(realpath -m "$file1" 2>/dev/null || echo "$file1")
	local real2=$(realpath -m "$file2" 2>/dev/null || echo "$file2")

	[ "$real1" = "$real2" ]
}

# Create temp file with .json suffix (cross-platform)
make_temp_json() {
	local temp
	if temp=$(mktemp --suffix=.json 2>/dev/null); then
		echo "$temp"
	else
		temp=$(mktemp)
		mv "$temp" "${temp}.json"
		echo "${temp}.json"
	fi
}

# Create temp file with same extension
make_temp_with_ext() {
	local ext="$1"
	local temp
	if temp=$(mktemp --suffix=".$ext" 2>/dev/null); then
		echo "$temp"
	else
		temp=$(mktemp)
		mv "$temp" "${temp}.${ext}"
		echo "${temp}.${ext}"
	fi
}

# Python script for PNG handling
PNG_HANDLER=$(
	cat <<'PYTHON_SCRIPT'
import sys
import json
from PIL import Image
import base64

def read_png_metadata(image_path):
    with Image.open(image_path) as img:
        metadata = img.text
        for key in metadata:
            try:
                decoded_data = base64.b64decode(metadata[key])
                json_data = json.loads(decoded_data)
                return key, json_data
            except:
                continue
    return None, None

def write_png_with_metadata(original_path, output_path, key, json_data):
    from PIL import PngImagePlugin
    with Image.open(original_path) as img:
        meta = PngImagePlugin.PngInfo()
        json_str = json.dumps(json_data, ensure_ascii=False)
        encoded = base64.b64encode(json_str.encode('utf-8')).decode('ascii')
        meta.add_text(key, encoded)
        img.save(output_path, pnginfo=meta)

if __name__ == "__main__":
    action = sys.argv[1]
    if action == "extract":
        png_path = sys.argv[2]
        json_path = sys.argv[3]
        key, data = read_png_metadata(png_path)
        if data:
            with open(json_path, 'w', encoding='utf-8') as f:
                json.dump({"_png_key": key, "data": data}, f, indent=4, ensure_ascii=False)
            print(f"Extracted: {png_path} -> {json_path}", file=sys.stderr)
        else:
            print(f"No metadata found in {png_path}", file=sys.stderr)
            sys.exit(1)
    elif action == "extract_raw":
        png_path = sys.argv[2]
        json_path = sys.argv[3]
        key, data = read_png_metadata(png_path)
        if data:
            with open(json_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=4, ensure_ascii=False)
            print(f"Extracted: {png_path} -> {json_path}", file=sys.stderr)
        else:
            print(f"No metadata found in {png_path}", file=sys.stderr)
            sys.exit(1)
    elif action == "embed":
        original_png = sys.argv[2]
        json_path = sys.argv[3]
        output_png = sys.argv[4]
        with open(json_path, 'r', encoding='utf-8') as f:
            wrapper = json.load(f)
        key = wrapper.get("_png_key", "chara")
        data = wrapper.get("data", wrapper)
        write_png_with_metadata(original_png, output_png, key, data)
        print(f"Embedded: {json_path} -> {output_png}", file=sys.stderr)
PYTHON_SCRIPT
)

# Apply replacements to a file
apply_replacements() {
	local file="$1"
	for ((i = 0; i < ${#map[@]}; i += 2)); do
		src="$(escape_sed "${map[i]}")"
		dst="$(escape_sed "${map[i + 1]}")"
		if sed --version >/dev/null 2>&1; then
			sed -i "s|$src|$dst|g" "$file"
		else
			sed -i '' "s|$src|$dst|g" "$file"
		fi
	done
}

# Warn if output file exists and handle overwrite
# Returns: "self" if overwriting input, "other" if overwriting different file, "none" if new file
check_overwrite() {
	local input_file="$1"
	local output_file="$2"

	if same_file "$input_file" "$output_file"; then
		echo "Warning: overwriting input file '$input_file'" >&2
		echo "self"
	elif [ -f "$output_file" ]; then
		echo "Warning: overwriting existing file '$output_file'" >&2
		echo "other"
	else
		echo "none"
	fi
}

# Process PNG to JSON only
process_png_to_json() {
	local input_file="$1"
	local mode="$2"
	local custom_output="$3"
	local dir=$(dirname "$input_file")
	local filename=$(basename "$input_file")
	local basename="${filename%.*}"
	local output_json

	if [ -n "$custom_output" ]; then
		output_json="$custom_output"
	else
		case "$mode" in
		o)
			if [ "$dir" = "." ]; then
				output_json="${basename}.json"
			else
				output_json="${dir}/${basename}.json"
			fi
			;;
		cn)
			local temp_input="${input_file%.png}.json"
			temp_input="${temp_input%.PNG}.json"
			output_json=$(generate_output_filename "$temp_input" true)
			;;
		tw)
			local temp_input="${input_file%.png}.json"
			temp_input="${temp_input%.PNG}.json"
			output_json=$(generate_output_filename "$temp_input" false)
			;;
		esac
	fi

	# Check for overwrite (JSON output can't overwrite PNG input, but check other files)
	if [ -f "$output_json" ]; then
		echo "Warning: overwriting existing file '$output_json'" >&2
	fi

	if ! python3 -c "$PNG_HANDLER" extract_raw "$input_file" "$output_json" 2>&1; then
		echo "Error: Failed to extract metadata from $input_file" >&2
		return 1
	fi

	if [ "$mode" = "tw" ]; then
		local temp_file=$(mktemp)
		opencc -i "$output_json" -o "$temp_file" -c s2tw
		mv "$temp_file" "$output_json"
		load_all_rules false
		if [ -f "$CONTROVERSIAL_FILE" ]; then
			load_rules "$CONTROVERSIAL_FILE" false
		fi
		apply_replacements "$output_json"
	elif [ "$mode" = "cn" ]; then
		local temp_file=$(mktemp)
		opencc -i "$output_json" -o "$temp_file" -c tw2s
		mv "$temp_file" "$output_json"
		load_all_rules true
		if [ -f "$CONTROVERSIAL_FILE" ]; then
			load_rules "$CONTROVERSIAL_FILE" true
		fi
		apply_replacements "$output_json"
	fi

	echo "Wrote: $output_json"
}

# Process a single file (PNG to PNG or text to text)
process_file() {
	local input_file="$1"
	local custom_output="$2"
	local filename=$(basename "$input_file")
	local ext="${filename##*.}"
	local output_file
	local overwrite_type
	local temp_output=""

	if [ "$filename" = "$ext" ]; then
		ext=""
	fi

	# Determine output filename
	if [ -n "$custom_output" ]; then
		output_file="$custom_output"
	else
		output_file=$(generate_output_filename "$input_file" "$REVERSE_MODE")
	fi

	# Check for overwrite situations
	overwrite_type=$(check_overwrite "$input_file" "$output_file")

	# If overwriting self or other, use temp file
	if [ "$overwrite_type" = "self" ]; then
		if [ -n "$ext" ]; then
			temp_output=$(make_temp_with_ext "$ext")
		else
			temp_output=$(mktemp)
		fi
	fi

	local actual_output="$output_file"
	if [ "$overwrite_type" = "self" ]; then
		actual_output="$temp_output"
	fi

	if [ "$ext" = "png" ] || [ "$ext" = "PNG" ]; then
		local temp_json=$(make_temp_json)
		local temp_converted_json="${temp_json%.json}_converted.json"

		if [ "$USE_CONTROVERSIAL" = false ] && [ -f "$CONTROVERSIAL_FILE" ]; then
			load_rules "$CONTROVERSIAL_FILE" "$REVERSE_MODE"
		fi

		if ! python3 -c "$PNG_HANDLER" extract "$input_file" "$temp_json" 2>&1; then
			echo "Error: Failed to extract metadata from $input_file" >&2
			rm -f "$temp_json" "$temp_output"
			return 1
		fi

		if [ "$REVERSE_MODE" = true ]; then
			opencc -i "$temp_json" -o "$temp_converted_json" -c tw2s
		else
			opencc -i "$temp_json" -o "$temp_converted_json" -c s2tw
		fi

		apply_replacements "$temp_converted_json"

		python3 -c "$PNG_HANDLER" embed "$input_file" "$temp_converted_json" "$actual_output" 2>&1

		rm -f "$temp_json" "$temp_converted_json"
	else
		if [ "$REVERSE_MODE" = true ]; then
			opencc -i "$input_file" -o "$actual_output" -c tw2s
		else
			opencc -i "$input_file" -o "$actual_output" -c s2tw
		fi

		apply_replacements "$actual_output"
	fi

	# Move temp to final destination if overwriting self
	if [ "$overwrite_type" = "self" ]; then
		mv "$temp_output" "$output_file"
	fi

	echo "Wrote: $output_file"
}

# Track if we're in auto-discovery mode
AUTO_DISCOVER_MODE=false

# Determine input files
input_files=()
if [ ${#input_args[@]} -ge 1 ]; then
	# Files specified on command line - validate they exist
	for arg in "${input_args[@]}"; do
		if [ ! -f "$arg" ]; then
			echo "Error: Input file '$arg' not found" >&2
			exit 1
		fi
		input_files+=("$arg")
	done
else
	# Auto-discover files in current directory
	if [ "$CUSTOM_OUTPUT" = true ]; then
		echo "Error: -o cannot be used without specifying input files" >&2
		exit 1
	fi

	AUTO_DISCOVER_MODE=true
	shopt -s nullglob

	if [ "$INCLUDE_HIDDEN" = true ]; then
		shopt -s dotglob
	fi

	for f in *; do
		[ -d "$f" ] && continue
		should_skip_file "$f" && continue
		has_supported_extension "$f" || continue
		input_files+=("$f")
	done

	shopt -u nullglob
	if [ "$INCLUDE_HIDDEN" = true ]; then
		shopt -u dotglob
	fi

	if [ ${#input_files[@]} -eq 0 ]; then
		echo "Error: no supported files found to process" >&2
		echo "Supported extensions: ${SUPPORTED_EXTENSIONS[*]}" >&2
		echo "Use -h to include hidden files" >&2
		exit 1
	fi
fi

# Process each input file
processed_count=0
skipped_count=0

for ((idx = 0; idx < ${#input_files[@]}; idx++)); do
	input_file="${input_files[idx]}"
	filename=$(basename "$input_file")
	ext="${filename##*.}"

	# Get custom output if specified
	custom_out=""
	if [ "$CUSTOM_OUTPUT" = true ]; then
		custom_out="${OUTPUT_FILES[idx]}"
	fi

	if [ "$filename" = "$ext" ]; then
		ext=""
	fi

	# If JSON mode is set, only process PNG files
	if [ -n "$JSON_MODE" ]; then
		if [ "$ext" = "png" ] || [ "$ext" = "PNG" ]; then
			process_png_to_json "$input_file" "$JSON_MODE" "$custom_out"
			((processed_count++))
		else
			echo "Warning: -j flag only works with PNG files, skipping: $input_file" >&2
			((skipped_count++))
		fi
	else
		# In auto-discover mode, check if counterpart exists
		if [ "$AUTO_DISCOVER_MODE" = true ]; then
			if counterpart_exists "$input_file" "$REVERSE_MODE"; then
				output_file=$(generate_output_filename "$input_file" "$REVERSE_MODE")
				echo "Skipping (counterpart exists): $input_file <-> $output_file"
				((skipped_count++))
				continue
			fi
		fi

		process_file "$input_file" "$custom_out"
		((processed_count++))
	fi
done

# Summary for auto-discover mode
if [ "$AUTO_DISCOVER_MODE" = true ]; then
	echo ""
	echo "Summary: $processed_count file(s) processed, $skipped_count file(s) skipped"
fi
