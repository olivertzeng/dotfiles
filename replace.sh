#!/bin/bash

# Credit for PNG metadata handling: https://github.com/IlllllIII/png_to_json

# ==========================================
# 使用者配置區 (User Configuration)
# ==========================================

declare -a BLACKLIST=(
	"*.bak"
	"*.tmp"
	".DS_Store"
	".git"
	"LICENSE"
	"__pycache__"
	"build"
	"dist"
	"node_modules"
)

# 並行處理數量 (0 = 使用 CPU 核心數)
PARALLEL_JOBS=0

# ==========================================
# 腳本邏輯開始 (Script Logic)
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
MAP_FILE="$SCRIPT_DIR/dict.txt"
CONTROVERSIAL_FILE="$SCRIPT_DIR/controversial.txt"

SUPPORTED_EXTENSIONS=("txt" "json" "jsonl" "md" "po" "strings" "png" "PNG")

# Flags
USE_CONTROVERSIAL=false
REVERSE_MODE=false
JSON_MODE=""
AMEND_MODE=false
INCLUDE_HIDDEN=false
RESPECT_GITIGNORE=false
UNIFY_MODE=false
CUSTOM_OUTPUT=false
DRY_RUN=false
MAKE_BACKUP=false
PARALLEL_MODE=false
FORCE_CONTINUE=false

declare -a OUTPUT_FILES

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

usage() {
	cat <<EOF
${CYAN}Advanced Chinese Converter & PNG Metadata Tool${NC}

Usage: $0 [OPTIONS] [files...]

Options:
  ${GREEN}-c${NC}            Enable controversial replacements
  ${GREEN}-r${NC}            Reverse mode: TW -> CN (default: CN -> TW)
  ${GREEN}-j [MODE]${NC}     PNG extraction: o(riginal), c(n), t(w)
                  cn/tw modes also translate filename
  ${GREEN}-a${NC}            Amend mode: combine PNG + JSON into character card
                  Output filename uses JSON's name (clears old metadata)
                  Usage: -a <file1> <file2> [-o output.png]
  ${GREEN}-u${NC}            Unify: force -TW/-CN suffix
  ${GREEN}-g${NC}            Respect .gitignore
  ${GREEN}-h${NC}            Include hidden files
  ${GREEN}-n${NC}            Dry-run
  ${GREEN}-b${NC}            Create backup (.bak)
  ${GREEN}-f${NC}            Force continue on errors
  ${GREEN}-p${NC}            Parallel processing (faster for many files)
  ${GREEN}-o [files]${NC}    Specify output filenames
  ${GREEN}--help${NC}        Show this help

Examples:
  $0 -j tw card.png              Extract & translate to TW (filename too)
  $0 -a avatar.png char.json     Combine into char.png (uses JSON name)
  $0 -a avatar.png data.json -o out.png   Combine into out.png (preserves original)
  $0 -a -c img.png data.json     Amend with controversial dict

Blacklist: ${YELLOW}${BLACKLIST[*]}${NC}
EOF
	exit 0
}

check_dependencies() {
	local missing=()
	command -v opencc >/dev/null 2>&1 || missing+=("opencc")
	command -v python3 >/dev/null 2>&1 || missing+=("python3")
	python3 -c "from PIL import Image" 2>/dev/null || missing+=("Pillow")

	if [ ${#missing[@]} -gt 0 ]; then
		echo -e "${RED}Missing: ${missing[*]}${NC}" >&2
		exit 1
	fi
}

while getopts ":crj:ahHnbfgup-:" opt; do
	[ "$opt" = "-" ] && { [ "${OPTARG}" = "help" ] && usage || exit 1; }
	case $opt in
	c) USE_CONTROVERSIAL=true ;;
	r) REVERSE_MODE=true ;;
	j) case "$OPTARG" in
		o | original) JSON_MODE="o" ;;
		c | cn) JSON_MODE="cn" ;;
		t | tw) JSON_MODE="tw" ;;
		*) JSON_MODE="o" ;;
		esac ;;
	a) AMEND_MODE=true ;;
	h | H) INCLUDE_HIDDEN=true ;;
	g) RESPECT_GITIGNORE=true ;;
	u) UNIFY_MODE=true ;;
	n) DRY_RUN=true ;;
	b) MAKE_BACKUP=true ;;
	f) FORCE_CONTINUE=true ;;
	p) PARALLEL_MODE=true ;;
	:)
		echo -e "${RED}Option -$OPTARG requires argument${NC}" >&2
		exit 1
		;;
	\?)
		echo -e "${RED}Invalid option -$OPTARG${NC}" >&2
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

check_dependencies

# Parse -o arguments
input_args=() output_args=() found_o=false
for arg in "$@"; do
	[ "$arg" = "-o" ] && {
		found_o=true
		CUSTOM_OUTPUT=true
		continue
	}
	[ "$found_o" = true ] && output_args+=("$arg") || input_args+=("$arg")
done

if [ "$CUSTOM_OUTPUT" = true ]; then
	# For amend mode, we expect 2 inputs and 1 output
	if [ "$AMEND_MODE" = true ]; then
		if [ ${#input_args[@]} -eq 2 ] && [ ${#output_args[@]} -eq 1 ]; then
			OUTPUT_FILES=("${output_args[@]}")
		else
			echo -e "${RED}Amend mode with -o requires: -a <png> <json> -o <output.png>${NC}" >&2
			exit 1
		fi
	else
		[ ${#input_args[@]} -eq 0 ] || [ ${#output_args[@]} -ne ${#input_args[@]} ] && {
			echo -e "${RED}Invalid -o usage${NC}" >&2
			exit 1
		}
		OUTPUT_FILES=("${output_args[@]}")
	fi
fi

[ ! -f "$MAP_FILE" ] && {
	echo -e "${RED}dict.txt not found${NC}" >&2
	exit 1
}

# ==========================================
# 優化 1: 預編譯 sed 腳本 (一次性替換)
# ==========================================
SED_SCRIPT_FILE=""
SED_SCRIPT_FILE_REV=""

build_sed_script() {
	local reverse="$1"
	local tmpfile=$(mktemp)
	local files=("$MAP_FILE")
	[ "$USE_CONTROVERSIAL" = true ] && [ -f "$CONTROVERSIAL_FILE" ] && files+=("$CONTROVERSIAL_FILE")

	for file in "${files[@]}"; do
		while IFS=$'\t' read -r from to marker || [ -n "$from" ]; do
			[ -z "$from" ] && continue
			[[ "$from" =~ ^[[:space:]]*# ]] && continue
			from="${from#"${from%%[![:space:]]*}"}"
			from="${from%"${from##*[![:space:]]}"}"
			to="${to#"${to%%[![:space:]]*}"}"
			to="${to%"${to##*[![:space:]]}"}"
			marker="${marker#"${marker%%[![:space:]]*}"}"
			marker="${marker%"${marker##*[![:space:]]}"}"
			[ -z "$from" ] || [ -z "$to" ] && continue

			[ "$reverse" = true ] && [ "$marker" = "->" ] && continue
			[ "$reverse" = false ] && [ "$marker" = "<-" ] && continue

			# Escape for sed
			local src dst
			if [ "$reverse" = true ]; then
				src=$(printf '%s' "$to" | sed 's/[&/\]/\\&/g')
				dst=$(printf '%s' "$from" | sed 's/[&/\]/\\&/g')
			else
				src=$(printf '%s' "$from" | sed 's/[&/\]/\\&/g')
				dst=$(printf '%s' "$to" | sed 's/[&/\]/\\&/g')
			fi
			echo "s|${src}|${dst}|g" >>"$tmpfile"
		done <"$file"
	done
	echo "$tmpfile"
}

# Build both scripts upfront
SED_SCRIPT_FILE=$(build_sed_script false)
SED_SCRIPT_FILE_REV=$(build_sed_script true)

cleanup_sed_scripts() {
	rm -f "$SED_SCRIPT_FILE" "$SED_SCRIPT_FILE_REV" 2>/dev/null
}
trap cleanup_sed_scripts EXIT

# ==========================================
# 優化 2: 用 grep 檢測中文 (比 Python 快 10x)
# ==========================================
file_contains_chinese() {
	# 使用 grep 檢測 CJK 字符範圍，比 Python 快得多
	LC_ALL=C grep -qP '[\x{4e00}-\x{9fff}]' "$1" 2>/dev/null && return 0
	# Fallback for systems without PCRE grep
	grep -q '[一-龥]' "$1" 2>/dev/null && return 0
	# Final fallback to Python (slower but reliable)
	python3 -c "
import sys
with open(sys.argv[1], 'r', encoding='utf-8', errors='ignore') as f:
    for chunk in iter(lambda: f.read(8192), ''):
        if any('\u4e00' <= c <= '\u9fff' for c in chunk): sys.exit(0)
sys.exit(1)" "$1" 2>/dev/null
}

contains_chinese() {
	[[ "$1" =~ [一-龥] ]] && return 0
	python3 -c "import sys; sys.exit(0 if any('\u4e00'<=c<='\u9fff' for c in sys.argv[1]) else 1)" "$1" 2>/dev/null
}

# ==========================================
# 優化 3: 使用預編譯 sed 腳本進行批量替換
# ==========================================
apply_replacements() {
	local file="$1"
	local script_file
	[ "$REVERSE_MODE" = true ] && script_file="$SED_SCRIPT_FILE_REV" || script_file="$SED_SCRIPT_FILE"

	if [ -s "$script_file" ]; then
		if sed --version >/dev/null 2>&1; then
			sed -i -f "$script_file" "$file"
		else
			sed -i '' -f "$script_file" "$file"
		fi
	fi
}

# Apply replacements to a string (for filename translation)
apply_replacements_string() {
	local input="$1" reverse="$2"
	local script_file
	[ "$reverse" = true ] && script_file="$SED_SCRIPT_FILE_REV" || script_file="$SED_SCRIPT_FILE"

	if [ -s "$script_file" ]; then
		echo "$input" | sed -f "$script_file"
	else
		echo "$input"
	fi
}

# ==========================================
# 優化 4: 整合 Python 腳本 (減少進程啟動)
# ==========================================
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
        meta.add_text(key, base64.b64encode(json.dumps(data, ensure_ascii=False).encode()).decode())
        img.save(out, pnginfo=meta)

def embed_raw(png_path, json_path, out_path, key="chara"):
    """Embed JSON file into PNG, completely clearing all existing metadata"""
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    with Image.open(png_path) as img:
        # Convert to RGB/RGBA to strip all metadata, then back to original mode
        # This ensures NO old metadata is carried over
        if img.mode in ('RGBA', 'LA') or (img.mode == 'P' and 'transparency' in img.info):
            # Preserve transparency
            clean_img = Image.new('RGBA', img.size)
            clean_img.paste(img)
        else:
            clean_img = Image.new('RGB', img.size)
            clean_img.paste(img)

        # Create fresh metadata with only our data
        meta = PngImagePlugin.PngInfo()
        encoded = base64.b64encode(json.dumps(data, ensure_ascii=False).encode()).decode()
        meta.add_text(key, encoded)

        # Save as PNG with only our metadata
        clean_img.save(out_path, format='PNG', pnginfo=meta)

def has_chinese(text):
    return any('\u4e00' <= c <= '\u9fff' for c in str(text))

def check_json_chinese(data):
    if isinstance(data, str): return has_chinese(data)
    if isinstance(data, dict): return any(check_json_chinese(v) for v in data.values())
    if isinstance(data, list): return any(check_json_chinese(v) for v in data)
    return False

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
    elif act == "embed_raw":
        # embed_raw <png_path> <json_path> <output_path> [key]
        key = sys.argv[5] if len(sys.argv) > 5 else "chara"
        embed_raw(sys.argv[2], sys.argv[3], sys.argv[4], key)
    elif act == "check_chinese":
        k, d = read_png(sys.argv[2])
        sys.exit(0 if d and check_json_chinese(d) else 1)
    elif act == "get_key":
        # Get the metadata key from existing PNG
        k, d = read_png(sys.argv[2])
        print(k if k else "chara")
    elif act == "list_keys":
        # List all metadata keys in PNG (for debugging)
        with Image.open(sys.argv[2]) as img:
            for k in img.text.keys():
                print(k)
PYTHON_SCRIPT
)

# ==========================================
# 輔助函數
# ==========================================

translate_string() {
	local input="$1" reverse="$2" result="$input"
	local script_file
	[ "$reverse" = true ] && script_file="$SED_SCRIPT_FILE_REV" || script_file="$SED_SCRIPT_FILE"

	if [ "$reverse" = true ]; then
		[ -s "$script_file" ] && result=$(echo "$result" | sed -f "$script_file")
		result=$(echo "$result" | opencc -c tw2s)
	else
		result=$(echo "$result" | opencc -c s2tw)
		[ -s "$script_file" ] && result=$(echo "$result" | sed -f "$script_file")
	fi
	echo "$result"
}

# Translate filename (basename only, preserving directory and extension)
translate_filename() {
	local filepath="$1" mode="$2"
	local dir=$(dirname "$filepath")
	local filename=$(basename "$filepath")
	local ext="${filename##*.}"
	local basename="${filename%.*}"
	local new_basename

	if [ "$mode" = "tw" ]; then
		# CN -> TW: opencc first, then dict replacements
		new_basename=$(echo "$basename" | opencc -c s2tw)
		new_basename=$(apply_replacements_string "$new_basename" false)
	elif [ "$mode" = "cn" ]; then
		# TW -> CN: dict replacements first, then opencc
		new_basename=$(apply_replacements_string "$basename" true)
		new_basename=$(echo "$new_basename" | opencc -c tw2s)
	else
		new_basename="$basename"
	fi

	if [ "$dir" = "." ]; then
		echo "${new_basename}.${ext}"
	else
		echo "${dir}/${new_basename}.${ext}"
	fi
}

should_skip_file() {
	local filename="$1" basename="${filename%.*}"
	case "$filename" in dict.txt | controversial.txt | "$SCRIPT_NAME" | *.bak) return 0 ;; esac
	for p in "${BLACKLIST[@]}"; do [[ "$filename" == $p ]] || [[ "$(basename "$filename")" == $p ]] && return 0; done
	[ "$RESPECT_GITIGNORE" = true ] && command -v git >/dev/null && git check-ignore -q "$filename" 2>/dev/null && return 0

	if [ "$REVERSE_MODE" = false ]; then
		[[ "$basename" =~ (zh[-_]?[Tt][Ww]|[-_][Tt][Ww]|TW)$ ]] && return 0
	else
		[[ "$basename" =~ (zh[-_]?[Cc][Nn]|[-_][Cc][Nn]|CN)$ ]] && return 0
	fi
	return 1
}

has_supported_extension() {
	local ext="${1##*.}"
	[ "$1" = "$ext" ] && return 1
	for s in "${SUPPORTED_EXTENSIONS[@]}"; do [ "$ext" = "$s" ] && return 0; done
	return 1
}

generate_output_filename() {
	local input_file="$1" reverse="$2"
	local dir filename ext basename has_ext new_basename

	dir=$(dirname "$input_file")
	filename=$(basename "$input_file")

	# 安全解析副檔名
	if [[ "$filename" == *.* ]]; then
		ext="${filename##*.}"
		basename="${filename%.*}"
		has_ext=true
	else
		ext=""
		basename="$filename"
		has_ext=false
	fi

	local patterns_tw=("zh_TW:zh_CN" "zh-TW:zh-CN" "zh_tw:zh_cn" "zh-tw:zh-cn" "_TW:_CN" "_tw:_cn" "-TW:-CN" "-tw:-cn" "zh:zh_CN" "TW:CN")
	local patterns_cn=("zh_CN:zh_TW" "zh-CN:zh-TW" "zh_cn:zh_tw" "zh-cn:zh-tw" "_CN:_TW" "_cn:_tw" "-CN:-TW" "-cn:-tw" "zh:zh_TW" "CN:TW")
	local patterns
	[ "$reverse" = true ] && patterns=("${patterns_tw[@]}") || patterns=("${patterns_cn[@]}")

	new_basename=""
	for p in "${patterns[@]}"; do
		local from="${p%:*}" to="${p#*:}"
		if [[ "$basename" =~ ^(.*)${from}$ ]]; then
			new_basename="${BASH_REMATCH[1]}${to}"
			break
		fi
	done

	if [ -z "$new_basename" ]; then
		local translated
		translated=$(translate_string "$basename" "$reverse")

		# 安全檢查：確保翻譯結果不包含副檔名
		translated="${translated%.json}"
		translated="${translated%.txt}"
		translated="${translated%.md}"

		local suffix
		[ "$reverse" = true ] && suffix="-CN" || suffix="-TW"

		if [ "$UNIFY_MODE" = true ]; then
			new_basename="${translated}${suffix}"
		else
			if [ "$translated" != "$basename" ]; then
				new_basename="$translated"
			else
				new_basename="${basename}${suffix}"
			fi
		fi
	fi

	# 組合輸出
	if [ "$has_ext" = true ]; then
		if [[ "$new_basename" == *.${ext} ]]; then
			new_basename="${new_basename%.*}"
		fi

		if [ "$dir" = "." ]; then
			echo "${new_basename}.${ext}"
		else
			echo "${dir}/${new_basename}.${ext}"
		fi
	else
		if [ "$dir" = "." ]; then
			echo "${new_basename}"
		else
			echo "${dir}/${new_basename}"
		fi
	fi
}

counterpart_exists() { [ -f "$(generate_output_filename "$1" "$2")" ]; }

check_overwrite() {
	local input="$1" output="$2"
	local r1=$(realpath -m "$input" 2>/dev/null || echo "$input")
	local r2=$(realpath -m "$output" 2>/dev/null || echo "$output")
	if [ "$r1" = "$r2" ]; then
		echo -e "${YELLOW}Overwriting: $input${NC}" >&2
		[ "$MAKE_BACKUP" = true ] && cp "$output" "${output}.bak"
		echo "self"
	elif [ -f "$output" ]; then
		echo -e "${YELLOW}Overwriting: $output${NC}" >&2
		[ "$MAKE_BACKUP" = true ] && cp "$output" "${output}.bak"
		echo "other"
	else echo "none"; fi
}

make_temp_with_ext() {
	local t
	t=$(mktemp --suffix=".$1" 2>/dev/null) || {
		t=$(mktemp)
		mv "$t" "$t.$1"
		t="$t.$1"
	}
	echo "$t"
}

# ==========================================
# 處理函數
# ==========================================

# Amend mode: Combine PNG + JSON into character card PNG
process_amend() {
	local file1="$1" file2="$2" custom_output="$3"
	local png_file="" json_file=""

	# Auto-detect which is PNG and which is JSON
	if [[ "$file1" =~ \.[pP][nN][gG]$ ]] && [[ "$file2" =~ \.[jJ][sS][oO][nN]$ ]]; then
		png_file="$file1"
		json_file="$file2"
	elif [[ "$file2" =~ \.[pP][nN][gG]$ ]] && [[ "$file1" =~ \.[jJ][sS][oO][nN]$ ]]; then
		png_file="$file2"
		json_file="$file1"
	else
		echo -e "${RED}Error: -a requires one PNG and one JSON file${NC}" >&2
		echo -e "${YELLOW}Got: $file1, $file2${NC}" >&2
		return 1
	fi

	# Validate files exist
	[ ! -f "$png_file" ] && {
		echo -e "${RED}PNG file not found: $png_file${NC}" >&2
		return 1
	}
	[ ! -f "$json_file" ] && {
		echo -e "${RED}JSON file not found: $json_file${NC}" >&2
		return 1
	}

	# Determine output filename
	local output
	if [ -n "$custom_output" ]; then
		output="$custom_output"
	else
		# Use JSON's basename with .png extension
		local json_dir=$(dirname "$json_file")
		local json_basename=$(basename "$json_file" .json)
		json_basename=$(basename "$json_basename" .JSON)
		if [ "$json_dir" = "." ]; then
			output="${json_basename}.png"
		else
			output="${json_dir}/${json_basename}.png"
		fi
	fi

	[ "$DRY_RUN" = true ] && {
		echo -e "${BLUE}[DRY]${NC} Amend: $png_file + $json_file -> $output"
		return 0
	}

	# Check for overwrite and backup if needed
	if [ -f "$output" ]; then
		echo -e "${YELLOW}Overwriting: $output${NC}" >&2
		[ "$MAKE_BACKUP" = true ] && cp "$output" "${output}.bak"
	fi

	# Use "chara" as default key (standard for character cards)
	local key="chara"

	# Embed JSON into PNG (this completely clears old metadata)
	python3 -c "$PNG_HANDLER" embed_raw "$png_file" "$json_file" "$output" "$key" 2>/dev/null || {
		echo -e "${RED}Failed to embed JSON into PNG${NC}" >&2
		return 1
	}

	echo -e "${GREEN}Created: $output${NC} (from $png_file + $json_file, old metadata cleared)"
	return 0
}

process_png_to_json() {
	local input="$1" mode="$2" custom="$3" output base

	# Get base without extension
	local dir=$(dirname "$input")
	local filename=$(basename "$input")
	local basename="${filename%.*}"

	if [ -n "$custom" ]; then
		output="$custom"
	else
		case "$mode" in
		o)
			# Original mode: no translation
			if [ "$dir" = "." ]; then
				output="${basename}.json"
			else
				output="${dir}/${basename}.json"
			fi
			;;
		cn)
			# Translate filename to CN (TW -> CN)
			local new_basename=$(apply_replacements_string "$basename" true)
			new_basename=$(echo "$new_basename" | opencc -c tw2s)
			if [ "$dir" = "." ]; then
				output="${new_basename}.json"
			else
				output="${dir}/${new_basename}.json"
			fi
			;;
		tw)
			# Translate filename to TW (CN -> TW)
			local new_basename=$(echo "$basename" | opencc -c s2tw)
			new_basename=$(apply_replacements_string "$new_basename" false)
			if [ "$dir" = "." ]; then
				output="${new_basename}.json"
			else
				output="${dir}/${new_basename}.json"
			fi
			;;
		esac
	fi

	[ "$DRY_RUN" = true ] && {
		echo -e "${BLUE}[DRY]${NC} $input -> $output"
		return 0
	}

	# Check for Chinese content in PNG
	if ! python3 -c "$PNG_HANDLER" check_chinese "$input" 2>/dev/null; then
		echo -e "${YELLOW}Skip (no Chinese): $input${NC}"
		return 0
	fi

	[ -f "$output" ] && [ "$MAKE_BACKUP" = true ] && cp "$output" "${output}.bak"

	# Extract JSON from PNG
	python3 -c "$PNG_HANDLER" extract_raw "$input" "$output" 2>/dev/null || {
		echo -e "${RED}Error extracting: $input${NC}" >&2
		return 1
	}

	# Translate content if needed
	if [ "$mode" = "tw" ]; then
		local t=$(mktemp)
		opencc -i "$output" -o "$t" -c s2tw
		mv "$t" "$output"
		apply_replacements "$output"
	elif [ "$mode" = "cn" ]; then
		apply_replacements "$output"
		local t=$(mktemp)
		opencc -i "$output" -o "$t" -c tw2s
		mv "$t" "$output"
	fi

	echo -e "${GREEN}Wrote: $output${NC}"
}

process_file() {
	local input="$1" custom="$2" output ext="${input##*.}"
	[ -n "$custom" ] && output="$custom" || output=$(generate_output_filename "$input" "$REVERSE_MODE")
	[ "$DRY_RUN" = true ] && {
		echo -e "${BLUE}[DRY]${NC} $input -> $output"
		return 0
	}

	# 檢查中文
	if [ "$ext" = "png" ] || [ "$ext" = "PNG" ]; then
		python3 -c "$PNG_HANDLER" check_chinese "$input" 2>/dev/null || {
			echo -e "${YELLOW}Skip (no Chinese): $input${NC}"
			return 0
		}
	else
		file_contains_chinese "$input" || {
			echo -e "${YELLOW}Skip (no Chinese): $input${NC}"
			return 0
		}
	fi

	local type=$(check_overwrite "$input" "$output") actual="$output" temp_out=""
	[ "$type" = "self" ] && {
		temp_out=$(make_temp_with_ext "$ext")
		actual="$temp_out"
	}

	if [ "$ext" = "png" ] || [ "$ext" = "PNG" ]; then
		local t_json=$(mktemp --suffix=.json) t_conv="${t_json}_conv.json"
		python3 -c "$PNG_HANDLER" extract "$input" "$t_json" 2>/dev/null || {
			rm -f "$t_json"
			return 1
		}

		if [ "$REVERSE_MODE" = true ]; then
			cp "$t_json" "$t_conv"
			apply_replacements "$t_conv"
			local t=$(mktemp)
			opencc -i "$t_conv" -o "$t" -c tw2s
			mv "$t" "$t_conv"
		else
			opencc -i "$t_json" -o "$t_conv" -c s2tw
			apply_replacements "$t_conv"
		fi
		python3 -c "$PNG_HANDLER" embed "$input" "$t_conv" "$actual" 2>/dev/null
		rm -f "$t_json" "$t_conv"
	else
		if [ "$REVERSE_MODE" = true ]; then
			cp "$input" "$actual"
			apply_replacements "$actual"
			local t=$(mktemp)
			opencc -i "$actual" -o "$t" -c tw2s
			mv "$t" "$actual"
		else
			opencc -i "$input" -o "$actual" -c s2tw
			apply_replacements "$actual"
		fi
	fi

	[ "$type" = "self" ] && mv "$temp_out" "$output"
	echo -e "${GREEN}Wrote: $output${NC}"
}

# ==========================================
# 優化 5: 並行處理支援
# ==========================================
process_file_parallel() {
	export REVERSE_MODE UNIFY_MODE MAKE_BACKUP DRY_RUN USE_CONTROVERSIAL
	export SED_SCRIPT_FILE SED_SCRIPT_FILE_REV
	export MAP_FILE CONTROVERSIAL_FILE
	process_file "$1" ""
}

export -f process_file process_file_parallel apply_replacements apply_replacements_string
export -f file_contains_chinese generate_output_filename translate_string translate_filename
export -f check_overwrite make_temp_with_ext contains_chinese should_skip_file
export -f has_supported_extension counterpart_exists
export PNG_HANDLER

# ==========================================
# 主程序
# ==========================================

# Handle amend mode specially
if [ "$AMEND_MODE" = true ]; then
	if [ ${#input_args[@]} -ne 2 ]; then
		echo -e "${RED}Error: -a mode requires exactly 2 files (PNG and JSON)${NC}" >&2
		echo -e "${YELLOW}Usage: $0 -a <file1> <file2> [-o output.png]${NC}" >&2
		exit 1
	fi

	custom_out=""
	[ "$CUSTOM_OUTPUT" = true ] && [ ${#OUTPUT_FILES[@]} -ge 1 ] && custom_out="${OUTPUT_FILES[0]}"

	if process_amend "${input_args[0]}" "${input_args[1]}" "$custom_out"; then
		echo -e "\n${CYAN}Done.${NC} Amend completed successfully."
	else
		echo -e "\n${RED}Failed.${NC}"
		exit 1
	fi
	exit 0
fi

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
	[ ${#input_files[@]} -eq 0 ] && {
		echo -e "${YELLOW}No files to process${NC}"
		exit 0
	}
fi

echo -e "${CYAN}Processing ${#input_files[@]} file(s)...${NC}"

# 並行或序列處理
if [ "$PARALLEL_MODE" = true ] && [ ${#input_files[@]} -gt 1 ] && command -v parallel >/dev/null 2>&1; then
	[ "$PARALLEL_JOBS" -eq 0 ] && PARALLEL_JOBS=$(nproc 2>/dev/null || echo 4)
	printf '%s\n' "${input_files[@]}" | parallel -j "$PARALLEL_JOBS" process_file_parallel {}
elif [ "$PARALLEL_MODE" = true ] && [ ${#input_files[@]} -gt 1 ]; then
	[ "$PARALLEL_JOBS" -eq 0 ] && PARALLEL_JOBS=$(nproc 2>/dev/null || echo 4)
	printf '%s\0' "${input_args[@]}" | xargs -0 -P "$PARALLEL_JOBS" -I {} bash -c 'process_file_parallel "$@"' _ {}
else
	for idx in "${!input_files[@]}"; do
		input="${input_files[$idx]}"
		custom=""
		[ "$CUSTOM_OUTPUT" = true ] && custom="${OUTPUT_FILES[$idx]}"

		if [ -n "$JSON_MODE" ]; then
			[[ "$input" =~ \.[pP][nN][gG]$ ]] && process_png_to_json "$input" "$JSON_MODE" "$custom" || ((total_skipped++))
		else
			[ ${#input_args[@]} -eq 0 ] && counterpart_exists "$input" "$REVERSE_MODE" && {
				echo -e "${YELLOW}Skip (exists): $input${NC}"
				((total_skipped++))
				continue
			}
			process_file "$input" "$custom" && ((total_processed++)) || ((total_failed++))
		fi
	done
fi

echo -e "\n${CYAN}Done.${NC} Processed: $total_processed, Skipped: $total_skipped, Failed: $total_failed"
