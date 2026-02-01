#!/bin/bash

# Credit for PNG metadata handling: https://github.com/IlllllIII/png_to_json

# ==========================================
# 使用者配置區 (User Configuration)
# ==========================================

declare -a BLACKLIST=(
	"node_modules"
	".git"
	".DS_Store"
	"*.bak"
	"*.tmp"
	"dist"
	"build"
	"__pycache__"
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
INCLUDE_HIDDEN=false
RESPECT_GITIGNORE=false
UNIFY_MODE=false
CUSTOM_OUTPUT=false
DRY_RUN=false
MAKE_BACKUP=false
PARALLEL_MODE=false

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
  ${GREEN}-u${NC}            Unify: force -TW/-CN suffix
  ${GREEN}-g${NC}            Respect .gitignore
  ${GREEN}-h${NC}            Include hidden files
  ${GREEN}-n${NC}            Dry-run
  ${GREEN}-b${NC}            Create backup (.bak)
  ${GREEN}-f${NC}            Force continue on errors
  ${GREEN}-p${NC}            Parallel processing (faster for many files)
  ${GREEN}-o [files]${NC}    Specify output filenames
  ${GREEN}--help${NC}        Show this help

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

FORCE_CONTINUE=false
while getopts ":crj:hHnbfgup-:" opt; do
	[ "$opt" = "-" ] && { [ "${OPTARG}" = "help" ] && usage || exit 1; }
	case $opt in
	c) USE_CONTROVERSIAL=true ;;
	r) REVERSE_MODE=true ;;
	j) case "$OPTARG" in o | original) JSON_MODE="o" ;; c | cn) JSON_MODE="cn" ;; t | tw) JSON_MODE="tw" ;; *) JSON_MODE="o" ;; esac ;;
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
	[ ${#input_args[@]} -eq 0 ] || [ ${#output_args[@]} -ne ${#input_args[@]} ] && {
		echo -e "${RED}Invalid -o usage${NC}" >&2
		exit 1
	}
	OUTPUT_FILES=("${output_args[@]}")
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
    elif act == "check_chinese":
        k, d = read_png(sys.argv[2])
        sys.exit(0 if d and check_json_chinese(d) else 1)
PYTHON_SCRIPT
)

# ==========================================
# 輔助函數 (保持不變或小幅優化)
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

	# Debug (可移除)
	# echo "DEBUG: filename=$filename, basename=$basename, ext=$ext" >&2

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

process_png_to_json() {
	local input="$1" mode="$2" custom="$3" output base="${input%.*}"

	[ -n "$custom" ] && output="$custom" || case "$mode" in
	o) output="${base}.json" ;;
	cn) output=$(generate_output_filename "${base}.json" true) ;;
	tw) output=$(generate_output_filename "${base}.json" false) ;;
	esac

	[ "$DRY_RUN" = true ] && {
		echo -e "${BLUE}[DRY]${NC} $input -> $output"
		return 0
	}

	# 優化: 使用整合的 Python 腳本檢測中文
	if ! python3 -c "$PNG_HANDLER" check_chinese "$input" 2>/dev/null; then
		echo -e "${YELLOW}Skip (no Chinese): $input${NC}"
		return 0
	fi

	[ -f "$output" ] && [ "$MAKE_BACKUP" = true ] && cp "$output" "${output}.bak"
	python3 -c "$PNG_HANDLER" extract_raw "$input" "$output" 2>/dev/null || {
		echo -e "${RED}Error: $input${NC}" >&2
		return 1
	}

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
	# 導出必要變量供子進程使用
	export REVERSE_MODE UNIFY_MODE MAKE_BACKUP DRY_RUN USE_CONTROVERSIAL
	export SED_SCRIPT_FILE SED_SCRIPT_FILE_REV
	export MAP_FILE CONTROVERSIAL_FILE
	process_file "$1" ""
}

export -f process_file process_file_parallel apply_replacements file_contains_chinese
export -f generate_output_filename translate_string check_overwrite make_temp_with_ext
export -f contains_chinese should_skip_file has_supported_extension counterpart_exists
export PNG_HANDLER

# ==========================================
# 主程序
# ==========================================

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
	# 使用 GNU Parallel
	[ "$PARALLEL_JOBS" -eq 0 ] && PARALLEL_JOBS=$(nproc 2>/dev/null || echo 4)
	printf '%s\n' "${input_files[@]}" | parallel -j "$PARALLEL_JOBS" process_file_parallel {}
elif [ "$PARALLEL_MODE" = true ] && [ ${#input_files[@]} -gt 1 ]; then
	# Fallback: 使用 xargs
	[ "$PARALLEL_JOBS" -eq 0 ] && PARALLEL_JOBS=$(nproc 2>/dev/null || echo 4)
	printf '%s\0' "${input_files[@]}" | xargs -0 -P "$PARALLEL_JOBS" -I {} bash -c 'process_file_parallel "$@"' _ {}
else
	# 序列處理
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
