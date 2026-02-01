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
DRY_RUN=false
MAKE_BACKUP=false

# Arrays for custom output
declare -a OUTPUT_FILES

# Statistics
total_processed=0
total_skipped=0
total_failed=0
declare -a failed_files

# Colors
if [ -t 1 ]; then
	RED='\033[0;31m'
	YELLOW='\033[1;33m'
	GREEN='\033[0;32m'
	BLUE='\033[0;34m'
	CYAN='\033[0;36m'
	NC='\033[0m'
else
	RED='' YELLOW='' GREEN='' BLUE='' CYAN='' NC=''
fi

# Usage
usage() {
	cat <<EOF
Usage: $0 [-c] [-r] [-j [MODE]] [-h] [-n] [-b] [-f] [files...] [-o output_files...]
EOF
	exit 0
}

# Check dependencies
check_dependencies() {
	local missing=()
	if ! command -v opencc >/dev/null 2>&1; then missing+=("opencc"); fi
	if ! command -v python3 >/dev/null 2>&1; then missing+=("python3"); fi
	if ! python3 -c "from PIL import Image" 2>/dev/null; then missing+=("python3-PIL/Pillow"); fi

	if [ ${#missing[@]} -gt 0 ]; then
		echo -e "${RED}Error: Missing required dependencies: ${missing[*]}${NC}" >&2
		exit 1
	fi
}

# Parse options
FORCE_CONTINUE=false
while getopts ":crj:hHnbf" opt; do
	case $opt in
	c) USE_CONTROVERSIAL=true ;;
	r) REVERSE_MODE=true ;;
	j)
		if [ -z "$OPTARG" ] || [[ "$OPTARG" == -* ]]; then
			JSON_MODE="o"
			if [[ "$OPTARG" == -* ]]; then ((OPTIND--)); fi
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
	n) DRY_RUN=true ;;
	b) MAKE_BACKUP=true ;;
	f) FORCE_CONTINUE=true ;;
	:)
		echo -e "${RED}Error: Option -$OPTARG requires an argument${NC}" >&2
		exit 1
		;;
	\?)
		echo -e "${RED}Error: Invalid option -$OPTARG${NC}" >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

# Check dependencies
check_dependencies

# Parse -o arguments
input_args=()
output_args=()
found_o=false
for arg in "$@"; do
	if [ "$arg" = "-o" ]; then
		found_o=true
		CUSTOM_OUTPUT=true
		continue
	fi
	if [ "$found_o" = true ]; then output_args+=("$arg"); else input_args+=("$arg"); fi
done

# Validate -o
if [ "$CUSTOM_OUTPUT" = true ]; then
	if [ ${#input_args[@]} -eq 0 ] || [ ${#output_args[@]} -eq 0 ] || [ ${#output_args[@]} -ne ${#input_args[@]} ]; then
		echo -e "${RED}Error: Invalid -o usage. Count must match.${NC}" >&2
		exit 1
	fi
	OUTPUT_FILES=("${output_args[@]}")
fi

if [ ! -f "$MAP_FILE" ]; then
	echo -e "${RED}Error: dict.txt not found at $SCRIPT_DIR${NC}" >&2
	exit 1
fi

# Parse rules
load_rules() {
	local file="$1"
	local reverse="$2"
	[ ! -f "$file" ] && return

	while IFS=$'\t' read -r from to marker || [ -n "$from" ]; do
		[ -z "$from" ] && continue
		[[ "$from" =~ ^[[:space:]]*# ]] && continue

		from="$(echo "$from" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		to="$(echo "$to" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		marker="$(echo "$marker" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

		[ -z "$from" ] || [ -z "$to" ] && continue

		# Logic for -> (Forward only) and <- (Reverse only)
		if [ "$reverse" = true ] && [ "$marker" = "->" ]; then continue; fi
		if [ "$reverse" = false ] && [ "$marker" = "<-" ]; then continue; fi

		if [ "$reverse" = true ]; then
			map+=("$to" "$from")
		else
			map+=("$from" "$to")
		fi
	done <"$file"
}

# Load rules wrapper
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

escape_sed() { printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'; }
contains_chinese() { python3 -c "import sys; sys.exit(0 if any('\u4e00' <= c <= '\u9fff' for c in sys.argv[1]) else 1)" "$1" 2>/dev/null; }

# Helper to apply replacements from memory
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

# Translate string (for filenames) - Logic matched with process_file
translate_string() {
	local input="$1"
	local reverse="$2"
	local result="$input"

	# Load temp map just for this string (inefficient but safe)
	local temp_map=()
	local files=("$MAP_FILE")
	if [ "$USE_CONTROVERSIAL" = true ]; then files+=("$CONTROVERSIAL_FILE"); fi

	for f in "${files[@]}"; do
		[ ! -f "$f" ] && continue
		while IFS=$'\t' read -r from to marker || [ -n "$from" ]; do
			[ -z "$from" ] && continue
			[[ "$from" =~ ^[[:space:]]*# ]] && continue
			from="$(echo "$from" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
			to="$(echo "$to" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
			marker="$(echo "$marker" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
			[ -z "$from" ] || [ -z "$to" ] && continue

			if [ "$reverse" = true ] && [ "$marker" = "->" ]; then continue; fi
			if [ "$reverse" = false ] && [ "$marker" = "<-" ]; then continue; fi

			if [ "$reverse" = true ]; then temp_map+=("$to" "$from"); else temp_map+=("$from" "$to"); fi
		done <"$f"
	done

	# EXECUTION ORDER FIX
	if [ "$reverse" = true ]; then
		# Reverse (TW->CN): Dict Replace -> OpenCC tw2s
		for ((i = 0; i < ${#temp_map[@]}; i += 2)); do
			src="${temp_map[i]}"
			dst="${temp_map[i + 1]}"
			result="${result//$src/$dst}"
		done
		result=$(echo "$result" | opencc -c tw2s)
	else
		# Normal (CN->TW): OpenCC s2tw -> Dict Replace
		result=$(echo "$result" | opencc -c s2tw)
		for ((i = 0; i < ${#temp_map[@]}; i += 2)); do
			src="${temp_map[i]}"
			dst="${temp_map[i + 1]}"
			result="${result//$src/$dst}"
		done
	fi
	echo "$result"
}

should_skip_file() {
	local filename="$1"
	local basename="${filename%.*}"
	case "$filename" in dict.txt | controversial.txt | "$SCRIPT_NAME" | *.bak) return 0 ;; esac

	if [ "$REVERSE_MODE" = false ]; then
		if [[ "$basename" =~ zh_TW$ ]] || [[ "$basename" =~ zh-TW$ ]] || [[ "$basename" =~ TW$ ]]; then return 0; fi
	else
		if [[ "$basename" =~ zh_CN$ ]] || [[ "$basename" =~ zh-CN$ ]] || [[ "$basename" =~ CN$ ]]; then return 0; fi
	fi
	return 1
}

has_supported_extension() {
	local filename="$1"
	local ext="${filename##*.}"
	[ "$filename" = "$ext" ] && return 1
	for supported in "${SUPPORTED_EXTENSIONS[@]}"; do
		if [ "$ext" = "$supported" ]; then return 0; fi
	done
	return 1
}

generate_output_filename() {
	local input_file="$1"
	local reverse="$2"
	local dir=$(dirname "$input_file")
	local filename=$(basename "$input_file")
	local ext="${filename##*.}"
	local basename="${filename%.*}"
	local has_ext=true
	if [ "$filename" = "$ext" ]; then
		basename="$filename"
		has_ext=false
	fi

	local new_basename

	# Handle filename patterns
	if [ "$reverse" = true ]; then
		if [[ "$basename" =~ ^(.*)zh_TW$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh_CN"
		elif [[ "$basename" =~ ^(.*)zh-TW$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh-CN"
		elif [[ "$basename" =~ ^(.*)zh$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh_CN"
		elif [[ "$basename" =~ ^(.*)TW$ ]]; then
			new_basename="${BASH_REMATCH[1]}CN"
		elif contains_chinese "$basename"; then
			local translated=$(translate_string "$basename" true)
			new_basename="$translated"
			[ "$translated" == "$basename" ] && new_basename="${basename}CN"
		else new_basename="${basename}CN"; fi
	else
		if [[ "$basename" =~ ^(.*)zh_CN$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh_TW"
		elif [[ "$basename" =~ ^(.*)zh-CN$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh-TW"
		elif [[ "$basename" =~ ^(.*)zh$ ]]; then
			new_basename="${BASH_REMATCH[1]}zh_TW"
		elif [[ "$basename" =~ ^(.*)CN$ ]]; then
			new_basename="${BASH_REMATCH[1]}TW"
		elif contains_chinese "$basename"; then
			local translated=$(translate_string "$basename" false)
			new_basename="$translated"
			[ "$translated" == "$basename" ] && new_basename="${basename}TW"
		else new_basename="${basename}TW"; fi
	fi

	if [ "$has_ext" = true ]; then
		[ "$dir" = "." ] && echo "${new_basename}.${ext}" || echo "${dir}/${new_basename}.${ext}"
	else
		[ "$dir" = "." ] && echo "${new_basename}" || echo "${dir}/${new_basename}"
	fi
}

counterpart_exists() {
	local output_file=$(generate_output_filename "$1" "$2")
	[ -f "$output_file" ]
}

check_overwrite() {
	local input="$1"
	local output="$2"
	local real1=$(realpath -m "$input" 2>/dev/null || echo "$input")
	local real2=$(realpath -m "$output" 2>/dev/null || echo "$output")

	if [ "$real1" = "$real2" ]; then
		echo -e "${YELLOW}Warning: overwriting input file '$input'${NC}" >&2
		if [ "$MAKE_BACKUP" = true ]; then cp "$output" "${output}.bak"; fi
		echo "self"
	elif [ -f "$output" ]; then
		echo -e "${YELLOW}Warning: overwriting existing file '$output'${NC}" >&2
		if [ "$MAKE_BACKUP" = true ]; then cp "$output" "${output}.bak"; fi
		echo "other"
	else
		echo "none"
	fi
}

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

PNG_HANDLER=$(
	cat <<'PYTHON_SCRIPT'
import sys, json, base64
from PIL import Image, PngImagePlugin
def read_png(path):
    with Image.open(path) as img:
        for k, v in img.text.items():
            try: return k, json.loads(base64.b64decode(v))
            except: continue
    return None, None
def write_png(orig, out, key, data):
    with Image.open(orig) as img:
        meta = PngImagePlugin.PngInfo()
        meta.add_text(key, base64.b64encode(json.dumps(data, ensure_ascii=False).encode('utf-8')).decode('ascii'))
        img.save(out, pnginfo=meta)
if __name__ == "__main__":
    act = sys.argv[1]
    if act == "extract" or act == "extract_raw":
        k, d = read_png(sys.argv[2])
        if d:
            with open(sys.argv[3], 'w', encoding='utf-8') as f:
                json.dump({"_png_key": k, "data": d} if act == "extract" else d, f, indent=4, ensure_ascii=False)
        else: sys.exit(1)
    elif act == "embed":
        with open(sys.argv[3], 'r', encoding='utf-8') as f: w = json.load(f)
        write_png(sys.argv[2], sys.argv[4], w.get("_png_key", "chara"), w.get("data", w))
PYTHON_SCRIPT
)

process_png_to_json() {
	local input="$1"
	local mode="$2"
	local custom="$3"
	local output

	if [ -n "$custom" ]; then
		output="$custom"
	else
		local base="${input%.*}"
		if [ "$mode" = "o" ]; then
			output="${base}.json"
		elif [ "$mode" = "cn" ]; then
			output=$(generate_output_filename "${base}.json" true)
		elif [ "$mode" = "tw" ]; then output=$(generate_output_filename "${base}.json" false); fi
	fi

	if [ "$DRY_RUN" = true ]; then
		echo -e "${BLUE}[DRY]${NC} Extract: $input -> $output"
		return 0
	fi
	if [ -f "$output" ] && [ "$MAKE_BACKUP" = true ]; then cp "$output" "${output}.bak"; fi

	if ! python3 -c "$PNG_HANDLER" extract_raw "$input" "$output" 2>&1; then
		echo -e "${RED}Error extracting $input${NC}" >&2
		return 1
	fi

	# PNG JSON EXECUTION ORDER FIX
	if [ "$mode" = "tw" ]; then
		# Normal: OpenCC -> Dict
		local tmp=$(mktemp)
		opencc -i "$output" -o "$tmp" -c s2tw
		mv "$tmp" "$output"
		load_all_rules false
		apply_replacements "$output"
	elif [ "$mode" = "cn" ]; then
		# Reverse: Dict -> OpenCC
		load_all_rules true
		apply_replacements "$output"
		local tmp=$(mktemp)
		opencc -i "$output" -o "$tmp" -c tw2s
		mv "$tmp" "$output"
	fi
	echo -e "${GREEN}Wrote: $output${NC}"
}

process_file() {
	local input="$1"
	local custom="$2"
	local output
	if [ -n "$custom" ]; then output="$custom"; else output=$(generate_output_filename "$input" "$REVERSE_MODE"); fi

	if [ "$DRY_RUN" = true ]; then
		echo -e "${BLUE}[DRY]${NC} Convert: $input -> $output"
		return 0
	fi

	local type=$(check_overwrite "$input" "$output")
	local actual="$output"
	local temp_out=""
	if [ "$type" = "self" ]; then
		temp_out=$(make_temp_with_ext "${input##*.}")
		actual="$temp_out"
	fi

	local ext="${input##*.}"
	if [ "$ext" = "png" ] || [ "$ext" = "PNG" ]; then
		local t_json=$(mktemp --suffix=.json)
		local t_conv="${t_json}_conv.json"
		if ! python3 -c "$PNG_HANDLER" extract "$input" "$t_json" 2>&1; then
			rm "$t_json"
			return 1
		fi

		# PNG EMBED EXECUTION ORDER FIX
		if [ "$REVERSE_MODE" = true ]; then
			# Reverse: Dict -> OpenCC
			cp "$t_json" "$t_conv"
			apply_replacements "$t_conv"
			local t_cc=$(mktemp)
			opencc -i "$t_conv" -o "$t_cc" -c tw2s
			mv "$t_cc" "$t_conv"
		else
			# Normal: OpenCC -> Dict
			opencc -i "$t_json" -o "$t_conv" -c s2tw
			apply_replacements "$t_conv"
		fi

		python3 -c "$PNG_HANDLER" embed "$input" "$t_conv" "$actual" 2>&1
		rm "$t_json" "$t_conv"
	else
		# TEXT FILE EXECUTION ORDER FIX
		if [ "$REVERSE_MODE" = true ]; then
			# Reverse: Dict -> OpenCC
			cp "$input" "$actual"
			apply_replacements "$actual"
			local t_cc=$(mktemp)
			opencc -i "$actual" -o "$t_cc" -c tw2s
			mv "$t_cc" "$actual"
		else
			# Normal: OpenCC -> Dict
			opencc -i "$input" -o "$actual" -c s2tw
			apply_replacements "$actual"
		fi
	fi

	if [ "$type" = "self" ]; then mv "$temp_out" "$output"; fi
	echo -e "${GREEN}Wrote: $output${NC}"
}

# Auto-discovery
input_files=()
if [ ${#input_args[@]} -ge 1 ]; then
	for arg in "${input_args[@]}"; do [ -f "$arg" ] && input_files+=("$arg"); done
else
	[ "$CUSTOM_OUTPUT" = true ] && exit 1
	shopt -s nullglob
	[ "$INCLUDE_HIDDEN" = true ] && shopt -s dotglob
	for f in *; do
		[ -d "$f" ] && continue
		should_skip_file "$f" && continue
		has_supported_extension "$f" || continue
		input_files+=("$f")
	done
	shopt -u nullglob
	[ "$INCLUDE_HIDDEN" = true ] && shopt -u dotglob
	[ ${#input_files[@]} -eq 0 ] && exit 1
fi

# Main Loop
for idx in "${!input_files[@]}"; do
	input="${input_files[$idx]}"
	custom=""
	[ "$CUSTOM_OUTPUT" = true ] && custom="${OUTPUT_FILES[$idx]}"

	if [ -n "$JSON_MODE" ]; then
		if [[ "$input" =~ \.[pP][nN][gG]$ ]]; then
			process_png_to_json "$input" "$JSON_MODE" "$custom"
		else ((total_skipped++)); fi
	else
		if [ ${#input_args[@]} -eq 0 ] && counterpart_exists "$input" "$REVERSE_MODE"; then
			echo -e "${YELLOW}Skipping (exists): $input${NC}"
			((total_skipped++))
			continue
		fi
		if process_file "$input" "$custom"; then ((total_processed++)); else ((total_failed++)); fi
	fi
done

echo -e "\n${CYAN}Summary:${NC} Processed: $total_processed, Skipped: $total_skipped, Failed: $total_failed"
