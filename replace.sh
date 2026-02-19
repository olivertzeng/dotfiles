#!/bin/bash

# ==============================================================================
# replace.sh - Advanced Chinese Converter & PNG Metadata Tool
# Refactored with fd + rg for performance
# Credit for PNG metadata handling: https://github.com/IlllllIII/png_to_json
# ==============================================================================

set -o pipefail

# ------------------------------------------------------------------------------
# User Configuration
# ------------------------------------------------------------------------------

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

SUPPORTED_EXTENSIONS=(
    "txt" "json" "jsonl" "md" "po" "strings"
    "png" "PNG"
    "yaml" "yml" "xyaml"
    "js" "mjs"
    "html" "css" "scss"
)

# Parallel job count (0 = auto-detect CPU cores).
PARALLEL_JOBS=0

# ------------------------------------------------------------------------------
# Script Setup
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
MAP_FILE="$SCRIPT_DIR/dict.txt"
CONTROVERSIAL_FILE="$SCRIPT_DIR/controversial.txt"

# Flags.
USE_CONTROVERSIAL=false
REVERSE_MODE=false
JSON_MODE=""
AMEND_MODE=false
INCLUDE_HIDDEN=false
RESPECT_GITIGNORE=true
UNIFY_MODE=false
CUSTOM_OUTPUT=false
DRY_RUN=false
MAKE_BACKUP=false
PARALLEL_MODE=false
FORCE_CONTINUE=false
INPLACE_MODE=false
RECURSIVE_MODE=false
NO_CONFIRM=false
QUIET_MODE=false
AUTO_STAGE=false
LOG_FILE=""

declare -a OUTPUT_FILES
declare -a failed_files=()
declare -A dir_stats

# Counters.
total_processed=0
total_skipped=0
total_failed=0
current_file_idx=0
total_file_count=0

# ------------------------------------------------------------------------------
# Colors
# ------------------------------------------------------------------------------

if [ -t 1 ]; then
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' YELLOW='' GREEN='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

log_write() {
    [ -n "$LOG_FILE" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log_info() {
    [ "$QUIET_MODE" = false ] && echo -e "$@"
    log_write "INFO: $*"
}

log_error() {
    echo -e "${RED}$*${NC}" >&2
    log_write "ERROR: $*"
}

log_warn() {
    [ "$QUIET_MODE" = false ] && echo -e "${YELLOW}$*${NC}"
    log_write "WARN: $*"
}

log_success() {
    [ "$QUIET_MODE" = false ] && echo -e "${GREEN}$*${NC}"
    log_write "SUCCESS: $*"
}

show_progress() {
    [ "$QUIET_MODE" = true ] && return
    local current="$1" total="$2" file="$3"
    local percent=$((current * 100 / total))
    local bar_width=30
    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))

    printf "\r${CYAN}[%3d%%]${NC} [${GREEN}%s${DIM}%s${NC}] %s" \
        "$percent" \
        "$(printf '#%.0s' $(seq 1 $filled 2>/dev/null) 2>/dev/null)" \
        "$(printf '.%.0s' $(seq 1 $empty 2>/dev/null) 2>/dev/null)" \
        "$(basename "$file")"
}

clear_progress() {
    [ "$QUIET_MODE" = true ] && return
    printf "\r\033[K"
}

# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
    cat <<EOF
${CYAN}${BOLD}Advanced Chinese Converter & PNG Metadata Tool${NC}
Uses fd + rg for fast file discovery and content matching.

${BOLD}Usage:${NC} $SCRIPT_NAME [OPTIONS] [files...]

${BOLD}Conversion Options:${NC}
  ${GREEN}-c${NC}              Enable controversial replacements
  ${GREEN}-r${NC}              Reverse mode: TW -> CN (default: CN -> TW)
  ${GREEN}-i${NC}              In-place mode: overwrite original files
                    Also translates filenames (删除.txt -> 刪除.txt)
  ${GREEN}-R${NC}              Recursive: process directories recursively
                    (auto-enabled when input is a directory)
  ${GREEN}-u${NC}              Unify: force -TW/-CN suffix on output

${BOLD}PNG Operations:${NC}
  ${GREEN}-j [MODE]${NC}       PNG extraction: o(riginal), c(n), t(w)
                    cn/tw modes also translate filename
  ${GREEN}-a${NC}              Amend mode: combine PNG + JSON into character card
                    Usage: -a <file1> <file2> [-o output.png]

${BOLD}File Handling:${NC}
  ${GREEN}-H${NC}              Include hidden files
  ${GREEN}-g${NC}              Respect .gitignore (default: on)
  ${GREEN}-b${NC}              Create backup (.bak)
  ${GREEN}-o [files]${NC}      Specify output filenames
  ${GREEN}-s, --stage${NC}     Auto git-stage processed files

${BOLD}Execution:${NC}
  ${GREEN}-n${NC}              Dry-run (no changes made)
  ${GREEN}-p${NC}              Parallel processing (faster for many files)
  ${GREEN}-f${NC}              Force continue on errors
  ${GREEN}-q, --quiet${NC}     Quiet mode (errors only)
  ${GREEN}-l, --log FILE${NC}  Write log to file
  ${GREEN}--no-confirm${NC}    Skip confirmation prompt for -i -R

${BOLD}Help:${NC}
  ${GREEN}--help${NC}          Show this help

${BOLD}Examples:${NC}
  $SCRIPT_NAME -i file.txt                 In-place convert (CN->TW)
  $SCRIPT_NAME -i -r file.txt              In-place convert (TW->CN)
  $SCRIPT_NAME ./zh-CN/                    Copy to ./zh-TW/ with converted files
  $SCRIPT_NAME -i ./zh-CN/                 In-place convert with dir rename
  $SCRIPT_NAME -i -R -p ./dir/             Parallel recursive conversion
  $SCRIPT_NAME -i -R -b -s ./dir/          With backup and auto-stage
  $SCRIPT_NAME -a image.png data.json      Combine into character card

${BOLD}Supported Extensions:${NC}
  ${YELLOW}${SUPPORTED_EXTENSIONS[*]}${NC}

${BOLD}Blacklist:${NC}
  ${YELLOW}${BLACKLIST[*]}${NC}
EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Dependency Check
# ------------------------------------------------------------------------------

check_dependencies() {
    local missing=()

    command -v opencc >/dev/null 2>&1 || missing+=("opencc")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1 || missing+=("fd")
    command -v rg >/dev/null 2>&1 || missing+=("ripgrep")
    python3 -c "from PIL import Image" 2>/dev/null || missing+=("python3-pillow")

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Install with: pacman -S ${missing[*]}"
        exit 1
    fi
}

get_fd_cmd() {
    if command -v fd >/dev/null 2>&1; then
        echo "fd"
    elif command -v fdfind >/dev/null 2>&1; then
        echo "fdfind"
    else
        echo ""
    fi
}

FD_CMD=""

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------

# Parse long options first.
args=()
for arg in "$@"; do
    case "$arg" in
        --no-confirm) NO_CONFIRM=true ;;
        --help) usage ;;
        --quiet) QUIET_MODE=true ;;
        --stage) AUTO_STAGE=true ;;
        --log)
            args+=("$arg")
            ;;
        --log=*)
            LOG_FILE="${arg#*=}"
            ;;
        *)
            args+=("$arg")
            ;;
    esac
done
set -- "${args[@]}"

while getopts ":crj:aHgnbfupRiqsl:-:" opt; do
    case $opt in
        c) USE_CONTROVERSIAL=true ;;
        r) REVERSE_MODE=true ;;
        j)
            case "$OPTARG" in
                o|original) JSON_MODE="o" ;;
                c|cn) JSON_MODE="cn" ;;
                t|tw) JSON_MODE="tw" ;;
                *) JSON_MODE="o" ;;
            esac
            ;;
        a) AMEND_MODE=true ;;
        H) INCLUDE_HIDDEN=true ;;
        g) RESPECT_GITIGNORE=true ;;
        n) DRY_RUN=true ;;
        b) MAKE_BACKUP=true ;;
        f) FORCE_CONTINUE=true ;;
        u) UNIFY_MODE=true ;;
        p) PARALLEL_MODE=true ;;
        i) INPLACE_MODE=true ;;
        R) RECURSIVE_MODE=true ;;
        q) QUIET_MODE=true ;;
        s) AUTO_STAGE=true ;;
        l) LOG_FILE="$OPTARG" ;;
        -)
            case "$OPTARG" in
                log)
                    LOG_FILE="${!OPTIND}"
                    OPTIND=$((OPTIND + 1))
                    ;;
            esac
            ;;
        :)
            log_error "Option -$OPTARG requires an argument"
            exit 1
            ;;
        \?)
            log_error "Invalid option: -$OPTARG"
            exit 1
            ;;
    esac
done
shift $((OPTIND - 1))

# Initialize log file.
if [ -n "$LOG_FILE" ]; then
    echo "# replace.sh log - $(date)" > "$LOG_FILE"
    log_write "Started with args: $*"
fi

check_dependencies
FD_CMD=$(get_fd_cmd)

# Parse -o arguments.
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

# Validate -o usage.
if [ "$CUSTOM_OUTPUT" = true ]; then
    if [ "$AMEND_MODE" = true ]; then
        if [ ${#input_args[@]} -eq 2 ] && [ ${#output_args[@]} -eq 1 ]; then
            OUTPUT_FILES=("${output_args[@]}")
        else
            log_error "Amend mode with -o requires: -a <png> <json> -o <output.png>"
            exit 1
        fi
    else
        if [ ${#input_args[@]} -eq 0 ] || [ ${#output_args[@]} -ne ${#input_args[@]} ]; then
            log_error "Invalid -o usage: must provide equal input and output files"
            exit 1
        fi
        OUTPUT_FILES=("${output_args[@]}")
    fi
fi

# In-place conflicts with custom output.
if [ "$INPLACE_MODE" = true ] && [ "$CUSTOM_OUTPUT" = true ]; then
    log_error "Error: -i (in-place) and -o (custom output) are mutually exclusive"
    exit 1
fi

# Verify dict.txt exists.
if [ ! -f "$MAP_FILE" ]; then
    log_error "Error: dict.txt not found at $MAP_FILE"
    exit 1
fi

# Set parallel jobs.
if [ "$PARALLEL_JOBS" -eq 0 ]; then
    PARALLEL_JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
fi

# Auto-enable recursive mode if any input is a directory
for arg in "${input_args[@]}"; do
    if [ -d "$arg" ]; then
        RECURSIVE_MODE=true
        break
    fi
done

# ------------------------------------------------------------------------------
# Precompiled sed Scripts
# ------------------------------------------------------------------------------

SED_SCRIPT_FILE=""
SED_SCRIPT_FILE_REV=""

build_sed_script() {
    local reverse="$1"
    local tmpfile
    tmpfile=$(mktemp)

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

            local src dst
            if [ "$reverse" = true ]; then
                src=$(printf '%s' "$to" | sed 's/[&/\]/\\&/g')
                dst=$(printf '%s' "$from" | sed 's/[&/\]/\\&/g')
            else
                src=$(printf '%s' "$from" | sed 's/[&/\]/\\&/g')
                dst=$(printf '%s' "$to" | sed 's/[&/\]/\\&/g')
            fi

            echo "s|${src}|${dst}|g" >> "$tmpfile"
        done < "$file"
    done

    echo "$tmpfile"
}

SED_SCRIPT_FILE=$(build_sed_script false)
SED_SCRIPT_FILE_REV=$(build_sed_script true)

cleanup() {
    rm -f "$SED_SCRIPT_FILE" "$SED_SCRIPT_FILE_REV" 2>/dev/null
    [ -n "$LOG_FILE" ] && log_write "Finished"
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# Chinese Detection
# ------------------------------------------------------------------------------

file_contains_chinese() {
    local file="$1"
    rg -q '[\x{4e00}-\x{9fff}]' "$file" 2>/dev/null
}

string_contains_chinese() {
    local str="$1"
    echo "$str" | rg -q '[\x{4e00}-\x{9fff}]' 2>/dev/null
}

# ------------------------------------------------------------------------------
# Replacement Functions
# ------------------------------------------------------------------------------

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

apply_replacements_string() {
    local input="$1"
    local reverse="${2:-false}"
    local script_file

    [ "$reverse" = true ] && script_file="$SED_SCRIPT_FILE_REV" || script_file="$SED_SCRIPT_FILE"

    if [ -s "$script_file" ]; then
        echo "$input" | sed -f "$script_file"
    else
        echo "$input"
    fi
}

# ------------------------------------------------------------------------------
# PNG Handler
# ------------------------------------------------------------------------------

PNG_HANDLER=$(cat <<'PYTHON_SCRIPT'
import sys
import json
import base64
from PIL import Image, PngImagePlugin

def read_png(path):
    with Image.open(path) as img:
        for k, v in img.text.items():
            try:
                return k, json.loads(base64.b64decode(v))
            except:
                continue
    return None, None

def write_png(orig, out, key, data):
    with Image.open(orig) as img:
        meta = PngImagePlugin.PngInfo()
        encoded = base64.b64encode(json.dumps(data, ensure_ascii=False).encode()).decode()
        meta.add_text(key, encoded)
        img.save(out, pnginfo=meta)

def embed_raw(png_path, json_path, out_path, key="chara"):
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    with Image.open(png_path) as img:
        if img.mode in ('RGBA', 'LA') or (img.mode == 'P' and 'transparency' in img.info):
            clean_img = Image.new('RGBA', img.size)
            clean_img.paste(img)
        else:
            clean_img = Image.new('RGB', img.size)
            clean_img.paste(img)
        meta = PngImagePlugin.PngInfo()
        encoded = base64.b64encode(json.dumps(data, ensure_ascii=False).encode()).decode()
        meta.add_text(key, encoded)
        clean_img.save(out_path, format='PNG', pnginfo=meta)

def has_chinese(text):
    return any('\u4e00' <= c <= '\u9fff' for c in str(text))

def check_json_chinese(data):
    if isinstance(data, str):
        return has_chinese(data)
    if isinstance(data, dict):
        return any(check_json_chinese(v) for v in data.values())
    if isinstance(data, list):
        return any(check_json_chinese(v) for v in data)
    return False

if __name__ == "__main__":
    action = sys.argv[1]

    if action == "extract" or action == "extract_raw":
        k, d = read_png(sys.argv[2])
        if d:
            out_data = {"_png_key": k, "data": d} if action == "extract" else d
            with open(sys.argv[3], 'w', encoding='utf-8') as f:
                json.dump(out_data, f, indent=4, ensure_ascii=False)
        else:
            sys.exit(1)

    elif action == "embed":
        with open(sys.argv[3], 'r', encoding='utf-8') as f:
            wrapper = json.load(f)
        write_png(sys.argv[2], sys.argv[4],
                  wrapper.get("_png_key", "chara"),
                  wrapper.get("data", wrapper))

    elif action == "embed_raw":
        key = sys.argv[5] if len(sys.argv) > 5 else "chara"
        embed_raw(sys.argv[2], sys.argv[3], sys.argv[4], key)

    elif action == "check_chinese":
        k, d = read_png(sys.argv[2])
        sys.exit(0 if d and check_json_chinese(d) else 1)

    elif action == "get_key":
        k, d = read_png(sys.argv[2])
        print(k if k else "chara")
PYTHON_SCRIPT
)

# ------------------------------------------------------------------------------
# Filename Translation
# ------------------------------------------------------------------------------

translate_string() {
    local input="$1"
    local reverse="${2:-false}"
    local result="$input"

    if [ "$reverse" = true ]; then
        result=$(apply_replacements_string "$result" true)
        result=$(echo "$result" | opencc -c tw2s)
    else
        result=$(echo "$result" | opencc -c s2tw)
        result=$(apply_replacements_string "$result" false)
    fi

    echo "$result"
}

translate_filename_inplace() {
    local filepath="$1"
    local reverse="${2:-false}"

    local dir
    dir=$(dirname "$filepath")
    local filename
    filename=$(basename "$filepath")

    local ext=""
    local base=""

    if [[ "$filename" == *.* ]]; then
        ext=".${filename##*.}"
        base="${filename%.*}"
    else
        base="$filename"
    fi

    local new_base
    if [ "$reverse" = true ]; then
        new_base=$(apply_replacements_string "$base" true)
        new_base=$(echo "$new_base" | opencc -c tw2s)
    else
        new_base=$(echo "$base" | opencc -c s2tw)
        new_base=$(apply_replacements_string "$base" false)
    fi

    if [ "$dir" = "." ]; then
        echo "${new_base}${ext}"
    else
        echo "${dir}/${new_base}${ext}"
    fi
}

# Translate path (including directory names)
translate_path() {
    local filepath="$1"
    local reverse="${2:-false}"

    local dir filename ext base
    dir=$(dirname "$filepath")
    filename=$(basename "$filepath")

    if [[ "$filename" == *.* ]]; then
        ext=".${filename##*.}"
        base="${filename%.*}"
    else
        ext=""
        base="$filename"
    fi

    # Translate the base filename
    local new_base
    new_base=$(translate_string "$base" "$reverse")

    # Translate directory path
    local new_dir
    if [ "$dir" = "." ]; then
        new_dir="."
    else
        new_dir=$(translate_string "$dir" "$reverse")
    fi

    if [ "$new_dir" = "." ]; then
        echo "${new_base}${ext}"
    else
        echo "${new_dir}/${new_base}${ext}"
    fi
}

generate_output_filename() {
    local input_file="$1"
    local reverse="${2:-false}"

    local dir filename ext base has_ext new_base
    dir=$(dirname "$input_file")
    filename=$(basename "$input_file")

    if [[ "$filename" == *.* ]]; then
        ext="${filename##*.}"
        base="${filename%.*}"
        has_ext=true
    else
        base="$filename"
        has_ext=false
    fi

    local patterns_tw=("zh_TW:zh_CN" "zh-TW:zh-CN" "zh_tw:zh_cn" "zh-tw:zh-cn" "_TW:_CN" "_tw:_cn" "-TW:-CN" "-tw:-cn" "TW:CN")
    local patterns_cn=("zh_CN:zh_TW" "zh-CN:zh-TW" "zh_cn:zh_tw" "zh-cn:zh-tw" "_CN:_TW" "_cn:_tw" "-CN:-TW" "-cn:-tw" "CN:TW")

    local patterns
    [ "$reverse" = true ] && patterns=("${patterns_tw[@]}") || patterns=("${patterns_cn[@]}")

    # First, try to translate the whole path (for directory rename without -i)
    if [ "$INPLACE_MODE" = false ]; then
        local translated_path
        translated_path=$(translate_path "$input_file" "$reverse")

        # If path changed, use it
        if [ "$translated_path" != "$input_file" ]; then
            echo "$translated_path"
            return
        fi
    fi

    # Then try pattern matching on base filename
    new_base=""
    for p in "${patterns[@]}"; do
        local from="${p%:*}"
        local to="${p#*:}"
        if [[ "$base" =~ ^(.*)${from}$ ]]; then
            new_base="${BASH_REMATCH[1]}${to}"
            break
        fi
    done

    if [ -z "$new_base" ]; then
        local translated
        translated=$(translate_string "$base" "$reverse")

        for strip_ext in json txt md yaml yml; do
            translated="${translated%.${strip_ext}}"
        done

        local suffix
        [ "$reverse" = true ] && suffix="-CN" || suffix="-TW"

        if [ "$UNIFY_MODE" = true ]; then
            new_base="${translated}${suffix}"
        elif [ "$translated" != "$base" ]; then
            new_base="$translated"
        else
            new_base="${base}${suffix}"
        fi
    fi

    if [ "$has_ext" = true ]; then
        [[ "$new_base" == *."${ext}" ]] && new_base="${new_base%.*}"
        [ "$dir" = "." ] && echo "${new_base}.${ext}" || echo "${dir}/${new_base}.${ext}"
    else
        [ "$dir" = "." ] && echo "${new_base}" || echo "${dir}/${new_base}"
    fi
}

# ------------------------------------------------------------------------------
# File Filtering
# ------------------------------------------------------------------------------

should_skip_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")
    local base="${filename%.*}"

    case "$filename" in
        dict.txt|controversial.txt|"$SCRIPT_NAME"|*.bak)
            return 0
        ;;
    esac

    for p in "${BLACKLIST[@]}"; do
        [[ "$filepath" == *"/$p/"* ]] && return 0
        [[ "$filepath" == *"/$p" ]] && return 0
        [[ "$filename" == $p ]] && return 0
    done

    if [ "$RESPECT_GITIGNORE" = true ]; then
        if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git check-ignore -q "$filepath" 2>/dev/null && return 0
        fi
    fi

    if [ "$INPLACE_MODE" = false ]; then
        if [ "$REVERSE_MODE" = false ]; then
            [[ "$base" =~ (zh[-_]?[Tt][Ww]|[-_][Tt][Ww]|TW)$ ]] && return 0
        else
            [[ "$base" =~ (zh[-_]?[Cc][Nn]|[-_][Cc][Nn]|CN)$ ]] && return 0
        fi
    fi

    return 1
}

should_skip_dir() {
    local dirpath="$1"
    local dirname
    dirname=$(basename "$dirpath")

    for p in "${BLACKLIST[@]}"; do
        [[ "$dirname" == $p ]] && return 0
    done

    if [ "$RESPECT_GITIGNORE" = true ]; then
        if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git check-ignore -q "$dirpath" 2>/dev/null && return 0
        fi
    fi

    return 1
}

has_supported_extension() {
    local file="$1"
    local ext="${file##*.}"

    [ "$file" = "$ext" ] && return 1

    for supported in "${SUPPORTED_EXTENSIONS[@]}"; do
        [ "$ext" = "$supported" ] && return 0
    done

    return 1
}

counterpart_exists() {
    local file="$1"
    local reverse="${2:-false}"
    local output
    output=$(generate_output_filename "$file" "$reverse")
    [ -f "$output" ]
}

# ------------------------------------------------------------------------------
# File Collection (using fd)
# ------------------------------------------------------------------------------

collect_files_recursive() {
    local target="$1"

    if [ -d "$target" ]; then
        local ext_args=()
        for ext in "${SUPPORTED_EXTENSIONS[@]}"; do
            ext_args+=(-e "$ext")
        done

        local exclude_args=()
        for bl in "${BLACKLIST[@]}"; do
            exclude_args+=(--exclude "$bl")
        done

        local fd_opts=(--type f)
        [ "$INCLUDE_HIDDEN" = true ] && fd_opts+=(--hidden)
        [ "$RESPECT_GITIGNORE" = false ] && fd_opts+=(--no-ignore)

        $FD_CMD "${fd_opts[@]}" "${ext_args[@]}" "${exclude_args[@]}" . "$target" 2>/dev/null | \
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            should_skip_file "$file" && continue
            echo "$file"
        done

    elif [ -f "$target" ]; then
        echo "$target"
    fi
}

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

check_overwrite() {
    local input="$1"
    local output="$2"

    local r1 r2
    r1=$(realpath -m "$input" 2>/dev/null || echo "$input")
    r2=$(realpath -m "$output" 2>/dev/null || echo "$output")

    if [ "$r1" = "$r2" ]; then
        log_warn "Overwriting: $input"
        [ "$MAKE_BACKUP" = true ] && cp "$output" "${output}.bak"
        echo "self"
    elif [ -f "$output" ]; then
        log_warn "Overwriting: $output"
        [ "$MAKE_BACKUP" = true ] && cp "$output" "${output}.bak"
        echo "other"
    else
        echo "none"
    fi
}

make_temp_with_ext() {
    local ext="$1"
    local tmpfile

    if tmpfile=$(mktemp --suffix=".$ext" 2>/dev/null); then
        echo "$tmpfile"
    else
        tmpfile=$(mktemp)
        mv "$tmpfile" "$tmpfile.$ext"
        echo "$tmpfile.$ext"
    fi
}

# ------------------------------------------------------------------------------
# Git Integration
# ------------------------------------------------------------------------------

is_inside_git_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

get_git_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

auto_stage_file() {
    local file="$1"
    if [ "$AUTO_STAGE" = true ] && is_inside_git_repo; then
        git add "$file" 2>/dev/null && log_write "Staged: $file"
    fi
}

all_chinese_files_staged() {
    local files=("$@")

    is_inside_git_repo || return 1

    local git_root
    git_root=$(get_git_root)
    [ -z "$git_root" ] && return 1

    local staged_files
    staged_files=$(git diff --cached --name-only 2>/dev/null)
    [ -z "$staged_files" ] && return 1

    local chinese_count=0
    local staged_count=0

    for file in "${files[@]}"; do
        local ext="${file##*.}"
        local has_chinese=false

        if [ "$ext" = "png" ] || [ "$ext" = "PNG" ]; then
            python3 -c "$PNG_HANDLER" check_chinese "$file" 2>/dev/null && has_chinese=true
        else
            file_contains_chinese "$file" && has_chinese=true
        fi

        local basename_file
        basename_file=$(basename "$file")
        string_contains_chinese "$basename_file" && has_chinese=true

        if [ "$has_chinese" = true ]; then
            ((++chinese_count))

            local abs_path rel_path
            abs_path=$(realpath -m "$file" 2>/dev/null || echo "$file")
            rel_path="${abs_path#$git_root/}"

            if echo "$staged_files" | grep -qF "$rel_path"; then
                ((++staged_count))
            fi
        fi
    done

    [ "$chinese_count" -gt 0 ] && [ "$chinese_count" -eq "$staged_count" ]
}

# ------------------------------------------------------------------------------
# Confirmation Prompt
# ------------------------------------------------------------------------------

prompt_confirmation() {
    local file_count="$1"
    shift
    local files=("$@")

    echo -e "\n${BOLD}${YELLOW}⚠ WARNING: In-place recursive mode${NC}"
    echo -e "${CYAN}This will modify ${BOLD}$file_count${NC}${CYAN} files in-place.${NC}\n"

    local show_count=10
    echo -e "${BOLD}Files to process:${NC}"

    for i in "${!files[@]}"; do
        if [ "$i" -ge "$show_count" ]; then
            local remaining=$((${#files[@]} - show_count))
            echo -e "  ${YELLOW}... and $remaining more${NC}"
            break
        fi

        local file="${files[$i]}"
        local new_name
        new_name=$(translate_filename_inplace "$file" "$REVERSE_MODE")

        if [ "$file" != "$new_name" ]; then
            echo -e "  ${file} ${BLUE}→${NC} $(basename "$new_name")"
        else
            echo -e "  ${file}"
        fi
    done

    echo ""
    if [ "$MAKE_BACKUP" = true ]; then
        echo -e "${GREEN}✓ Backups enabled (.bak)${NC}"
    else
        echo -e "${YELLOW}✗ No backups${NC}"
    fi
    echo ""

    while true; do
        echo -e "${BOLD}Proceed?${NC} [${GREEN}y${NC}]es / [${RED}N${NC}]o / [${CYAN}b${NC}]ackup+yes"
        read -r -n 1 reply
        echo ""

        case "$reply" in
            y|Y)
                return 0
                ;;
            b|B)
                MAKE_BACKUP=true
                echo -e "${GREEN}✓ Backups enabled${NC}"
                return 0
                ;;
            n|N|"")
                return 1
                ;;
            *)
                echo -e "${YELLOW}Invalid input.${NC}"
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Directory Renaming
# ------------------------------------------------------------------------------

rename_directories_recursive() {
    local target="$1"
    local dirs=()

    # Collect all subdirectories
    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        dirs+=("$dir")
    done < <($FD_CMD --type d . "$target" 2>/dev/null)

    [ ${#dirs[@]} -eq 0 ] && return 0

    # Sort by depth (deepest first)
    local sorted=()
    while IFS= read -r line; do
        sorted+=("$line")
    done < <(printf '%s\n' "${dirs[@]}" | awk -F'/' '{print NF, $0}' | sort -rn | cut -d' ' -f2-)

    for dir in "${sorted[@]}"; do
        should_skip_dir "$dir" && continue

        local parent base new_name new_path
        parent=$(dirname "$dir")
        base=$(basename "$dir")
        new_name=$(translate_string "$base" "$REVERSE_MODE")

        [ "$new_name" = "$base" ] && continue

        if [ "$parent" = "." ]; then
            new_path="$new_name"
        else
            new_path="$parent/$new_name"
        fi

        if [ -d "$new_path" ] && [ "$new_path" != "$dir" ]; then
            # Merge if target exists
            mv "$dir"/* "$new_path"/ 2>/dev/null
            rmdir "$dir" 2>/dev/null
            log_success "Merged dir: $dir ${BLUE}→${NC} $new_path"
        else
            mv "$dir" "$new_path"
            log_success "Renamed dir: $dir ${BLUE}→${NC} $new_path"
        fi

        auto_stage_file "$new_path"
    done
}

# ------------------------------------------------------------------------------
# Amend Mode
# ------------------------------------------------------------------------------

process_amend() {
    local file1="$1"
    local file2="$2"
    local custom_output="${3:-}"

    local png_file="" json_file=""

    if [[ "$file1" =~ \.[pP][nN][gG]$ ]] && [[ "$file2" =~ \.[jJ][sS][oO][nN]$ ]]; then
        png_file="$file1"
        json_file="$file2"
    elif [[ "$file2" =~ \.[pP][nN][gG]$ ]] && [[ "$file1" =~ \.[jJ][sS][oO][nN]$ ]]; then
        png_file="$file2"
        json_file="$file1"
    else
        log_error "Error: -a requires one PNG and one JSON file"
        return 1
    fi

    [ ! -f "$png_file" ] && { log_error "PNG not found: $png_file"; return 1; }
    [ ! -f "$json_file" ] && { log_error "JSON not found: $json_file"; return 1; }

    local output
    if [ -n "$custom_output" ]; then
        output="$custom_output"
    else
        local json_dir json_base
        json_dir=$(dirname "$json_file")
        json_base=$(basename "$json_file")
        json_base="${json_base%.json}"
        json_base="${json_base%.JSON}"
        [ "$json_dir" = "." ] && output="${json_base}.png" || output="${json_dir}/${json_base}.png"
    fi

    [ "$DRY_RUN" = true ] && {
        log_info "${BLUE}[DRY]${NC} Amend: $png_file + $json_file -> $output"
        return 0
    }

    if [ -f "$output" ]; then
        log_warn "Overwriting: $output"
        [ "$MAKE_BACKUP" = true ] && cp "$output" "${output}.bak"
    fi

    python3 -c "$PNG_HANDLER" embed_raw "$png_file" "$json_file" "$output" "chara" 2>/dev/null || {
        log_error "Failed to embed metadata"
        return 1
    }

    log_success "Created: $output"
    auto_stage_file "$output"
    return 0
}

# ------------------------------------------------------------------------------
# PNG to JSON
# ------------------------------------------------------------------------------

process_png_to_json() {
    local input="$1"
    local mode="$2"
    local custom="${3:-}"

    local dir filename base output
    dir=$(dirname "$input")
    filename=$(basename "$input")
    base="${filename%.*}"

    if [ -n "$custom" ]; then
        output="$custom"
    else
        case "$mode" in
            o)
                [ "$dir" = "." ] && output="${base}.json" || output="${dir}/${base}.json"
                ;;
            cn)
                local new_base
                new_base=$(apply_replacements_string "$base" true)
                new_base=$(echo "$new_base" | opencc -c tw2s)
                [ "$dir" = "." ] && output="${new_base}.json" || output="${dir}/${new_base}.json"
                ;;
            tw)
                local new_base
                new_base=$(echo "$base" | opencc -c s2tw)
                new_base=$(apply_replacements_string "$new_base" false)
                [ "$dir" = "." ] && output="${new_base}.json" || output="${dir}/${new_base}.json"
                ;;
        esac
    fi

    [ "$DRY_RUN" = true ] && {
        log_info "${BLUE}[DRY]${NC} $input -> $output"
        return 0
    }

    python3 -c "$PNG_HANDLER" check_chinese "$input" 2>/dev/null || {
        log_warn "Skip (no Chinese): $input"
        return 0
    }

    [ -f "$output" ] && [ "$MAKE_BACKUP" = true ] && cp "$output" "${output}.bak"

    python3 -c "$PNG_HANDLER" extract_raw "$input" "$output" 2>/dev/null || {
        log_error "Error extracting: $input"
        return 1
    }

    if [ "$mode" = "tw" ]; then
        local tmpfile
        tmpfile=$(mktemp)
        opencc -i "$output" -o "$tmpfile" -c s2tw
        mv "$tmpfile" "$output"
        apply_replacements "$output"
    elif [ "$mode" = "cn" ]; then
        apply_replacements "$output"
        local tmpfile
        tmpfile=$(mktemp)
        opencc -i "$output" -o "$tmpfile" -c tw2s
        mv "$tmpfile" "$output"
    fi

    log_success "Wrote: $output"
    auto_stage_file "$output"
    return 0
}

# ------------------------------------------------------------------------------
# In-Place File Processing
# ------------------------------------------------------------------------------

process_file_inplace() {
    local input="$1"
    local ext="${input##*.}"

    local new_path
    new_path=$(translate_filename_inplace "$input" "$REVERSE_MODE")

    local filename_changed=false
    [ "$input" != "$new_path" ] && filename_changed=true

    [ "$DRY_RUN" = true ] && {
        if [ "$filename_changed" = true ]; then
            log_info "${BLUE}[DRY]${NC} In-place: $input ${BLUE}→${NC} $(basename "$new_path")"
        else
            log_info "${BLUE}[DRY]${NC} In-place: $input"
        fi
        return 0
    }

    local has_content_chinese=false
    if [ "$ext" = "png" ] || [ "$ext" = "PNG" ]; then
        python3 -c "$PNG_HANDLER" check_chinese "$input" 2>/dev/null && has_content_chinese=true
    else
        file_contains_chinese "$input" && has_content_chinese=true
    fi

    if [ "$has_content_chinese" = false ] && [ "$filename_changed" = false ]; then
        log_warn "Skip (no Chinese): $input"
        return 0
    fi

    [ "$MAKE_BACKUP" = true ] && cp "$input" "${input}.bak"

    if [ "$has_content_chinese" = true ]; then
        local temp_out
        temp_out=$(make_temp_with_ext "$ext")

        if [ "$ext" = "png" ] || [ "$ext" = "PNG" ]; then
            local t_json t_conv
            t_json=$(mktemp --suffix=.json 2>/dev/null || mktemp)
            t_conv="${t_json}_conv.json"

            python3 -c "$PNG_HANDLER" extract "$input" "$t_json" 2>/dev/null || {
                rm -f "$t_json" "$temp_out"
                log_error "Error extracting: $input"
                return 1
            }

            if [ "$REVERSE_MODE" = true ]; then
                cp "$t_json" "$t_conv"
                apply_replacements "$t_conv"
                local tmpfile
                tmpfile=$(mktemp)
                opencc -i "$t_conv" -o "$tmpfile" -c tw2s
                mv "$tmpfile" "$t_conv"
            else
                opencc -i "$t_json" -o "$t_conv" -c s2tw
                apply_replacements "$t_conv"
            fi

            python3 -c "$PNG_HANDLER" embed "$input" "$t_conv" "$temp_out" 2>/dev/null
            rm -f "$t_json" "$t_conv"
        else
            if [ "$REVERSE_MODE" = true ]; then
                cp "$input" "$temp_out"
                apply_replacements "$temp_out"
                local tmpfile
                tmpfile=$(mktemp)
                opencc -i "$temp_out" -o "$tmpfile" -c tw2s
                mv "$tmpfile" "$temp_out"
            else
                opencc -i "$input" -o "$temp_out" -c s2tw
                apply_replacements "$temp_out"
            fi
        fi

        mv "$temp_out" "$new_path"

        if [ "$filename_changed" = true ] && [ "$input" != "$new_path" ]; then
            rm -f "$input"
        fi
    else
        mv "$input" "$new_path"
    fi

    # Track directory stats.
    local dir
    dir=$(dirname "$input")
    ((++dir_stats["$dir"])) 2>/dev/null || dir_stats["$dir"]=1

    if [ "$filename_changed" = true ]; then
        clear_progress
        log_success "Updated: $input ${BLUE}→${NC} $new_path"
    else
        clear_progress
        log_success "Updated: $input"
    fi

    auto_stage_file "$new_path"
    return 0
}

# ------------------------------------------------------------------------------
# Standard File Processing
# ------------------------------------------------------------------------------

process_file() {
    local input="$1"
    local custom="${2:-}"

    if [ "$INPLACE_MODE" = true ]; then
        process_file_inplace "$input"
        return $?
    fi

    local ext="${input##*.}"
    local output

    [ -n "$custom" ] && output="$custom" || output=$(generate_output_filename "$input" "$REVERSE_MODE")

    [ "$DRY_RUN" = true ] && {
        log_info "${BLUE}[DRY]${NC} $input -> $output"
        return 0
    }

    if [ "$ext" = "png" ] || [ "$ext" = "PNG" ]; then
        python3 -c "$PNG_HANDLER" check_chinese "$input" 2>/dev/null || {
            log_warn "Skip (no Chinese): $input"
            return 0
        }
    else
        file_contains_chinese "$input" || {
            log_warn "Skip (no Chinese): $input"
            return 0
        }
    fi

    local overwrite_type actual temp_out=""
    overwrite_type=$(check_overwrite "$input" "$output")
    actual="$output"

    [ "$overwrite_type" = "self" ] && {
        temp_out=$(make_temp_with_ext "$ext")
        actual="$temp_out"
    }

    if [ "$ext" = "png" ] || [ "$ext" = "PNG" ]; then
        local t_json t_conv
        t_json=$(mktemp --suffix=.json 2>/dev/null || mktemp)
        t_conv="${t_json}_conv.json"

        python3 -c "$PNG_HANDLER" extract "$input" "$t_json" 2>/dev/null || {
            rm -f "$t_json"
            return 1
        }

        if [ "$REVERSE_MODE" = true ]; then
            cp "$t_json" "$t_conv"
            apply_replacements "$t_conv"
            local tmpfile
            tmpfile=$(mktemp)
            opencc -i "$t_conv" -o "$tmpfile" -c tw2s
            mv "$tmpfile" "$t_conv"
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
            local tmpfile
            tmpfile=$(mktemp)
            opencc -i "$actual" -o "$tmpfile" -c tw2s
            mv "$tmpfile" "$actual"
        else
            opencc -i "$input" -o "$actual" -c s2tw
            apply_replacements "$actual"
        fi
    fi

    [ "$overwrite_type" = "self" ] && mv "$temp_out" "$output"

    # Create output directory if needed
    local out_dir
    out_dir=$(dirname "$output")
    if [ "$out_dir" != "." ] && [ ! -d "$out_dir" ]; then
        mkdir -p "$out_dir"
    fi

    [ "$overwrite_type" = "self" ] && mv "$temp_out" "$output"

    local dir
    dir=$(dirname "$input")
    ((++dir_stats["$dir"])) 2>/dev/null || dir_stats["$dir"]=1

    clear_progress
    log_success "Wrote: $input ${BLUE}→${NC} $output"
    auto_stage_file "$output"
    return 0
}

# ------------------------------------------------------------------------------
# Parallel Processing
# ------------------------------------------------------------------------------

export_for_parallel() {
    export REVERSE_MODE UNIFY_MODE MAKE_BACKUP DRY_RUN INPLACE_MODE
    export QUIET_MODE AUTO_STAGE LOG_FILE FORCE_CONTINUE
    export SED_SCRIPT_FILE SED_SCRIPT_FILE_REV
    export PNG_HANDLER FD_CMD
    export RED YELLOW GREEN BLUE CYAN BOLD DIM NC
    export -f process_file process_file_inplace
    export -f apply_replacements apply_replacements_string
    export -f file_contains_chinese string_contains_chinese
    export -f generate_output_filename translate_string translate_filename_inplace translate_path
    export -f check_overwrite make_temp_with_ext should_skip_file
    export -f has_supported_extension counterpart_exists
    export -f log_info log_error log_warn log_success log_write
    export -f show_progress clear_progress
    export -f is_inside_git_repo get_git_root auto_stage_file
}

process_file_parallel_wrapper() {
    process_file "$1" ""
}

export -f process_file_parallel_wrapper

run_parallel() {
    local files=("$@")
    local jobs="$PARALLEL_JOBS"

    export_for_parallel

    if command -v parallel >/dev/null 2>&1; then
        printf '%s\n' "${files[@]}" | parallel -j "$jobs" --bar process_file_parallel_wrapper {}
    else
        printf '%s\0' "${files[@]}" | xargs -0 -P "$jobs" -I {} bash -c 'process_file_parallel_wrapper "$@"' _ {}
    fi
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

# Handle amend mode.
if [ "$AMEND_MODE" = true ]; then
    if [ ${#input_args[@]} -ne 2 ]; then
        log_error "Error: -a requires exactly 2 files (PNG + JSON)"
        exit 1
    fi

    custom_out=""
    [ "$CUSTOM_OUTPUT" = true ] && [ ${#OUTPUT_FILES[@]} -ge 1 ] && custom_out="${OUTPUT_FILES[0]}"

    if process_amend "${input_args[0]}" "${input_args[1]}" "$custom_out"; then
        log_info "\n${CYAN}Done.${NC}"
        exit 0
    else
        log_error "\nFailed."
        exit 1
    fi
fi

# Collect input files.
input_files=()

if [ "$RECURSIVE_MODE" = true ]; then
    if [ ${#input_args[@]} -ge 1 ]; then
        for arg in "${input_args[@]}"; do
            while IFS= read -r file; do
                [ -n "$file" ] && input_files+=("$file")
            done < <(collect_files_recursive "$arg")
        done
    else
        while IFS= read -r file; do
            [ -n "$file" ] && input_files+=("$file")
        done < <(collect_files_recursive ".")
    fi
elif [ ${#input_args[@]} -ge 1 ]; then
    for arg in "${input_args[@]}"; do
        [ -f "$arg" ] && input_files+=("$arg")
    done
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
fi

# Check if we have files to process.
if [ ${#input_files[@]} -eq 0 ]; then
    log_warn "No files to process"
    exit 0
fi

total_file_count=${#input_files[@]}

# Confirmation for in-place recursive mode.
if [ "$INPLACE_MODE" = true ] && [ "$RECURSIVE_MODE" = true ] && [ "$NO_CONFIRM" = false ] && [ "$DRY_RUN" = false ]; then
    skip_confirm=false

    if all_chinese_files_staged "${input_files[@}"; then
        log_success "✓ All Chinese files are git staged - skipping confirmation"
        skip_confirm=true
    fi

    if [ "$skip_confirm" = false ]; then
        if ! prompt_confirmation "${#input_files[@]}" "${input_files[@]}"; then
            log_warn "Aborted."
            exit 0
        fi
    fi
fi

# Status output.
log_info "${CYAN}Processing ${#input_files[@]} file(s)...${NC}"
[ "$INPLACE_MODE" = true ] && log_info "${YELLOW}Mode: In-place${NC}"
[ "$RECURSIVE_MODE" = true ] && log_info "${YELLOW}Mode: Recursive${NC}"
[ "$PARALLEL_MODE" = true ] && log_info "${YELLOW}Mode: Parallel ($PARALLEL_JOBS jobs)${NC}"
[ "$DRY_RUN" = true ] && log_info "${BLUE}Mode: Dry-run${NC}"

# Process files.
if [ "$PARALLEL_MODE" = true ] && [ ${#input_files[@]} -gt 1 ]; then
    run_parallel "${input_files[@]}"
    log_info "\n${CYAN}Done.${NC} (parallel mode - see individual results above)"
else
    for idx in "${!input_files[@]}"; do
        input="${input_files[$idx]}"
        custom=""
        [ "$CUSTOM_OUTPUT" = true ] && custom="${OUTPUT_FILES[$idx]}"

        show_progress "$((idx + 1))" "$total_file_count" "$input"

        if [ -n "$JSON_MODE" ]; then
            if [[ "$input" =~ \.[pP][nN][gG]$ ]]; then
                if process_png_to_json "$input" "$JSON_MODE" "$custom"; then
                    ((++total_processed))
                else
                    ((++total_failed))
                    failed_files+=("$input")
                fi
            else
                ((++total_skipped))
            fi
        else
            if [ "$INPLACE_MODE" = false ] && [ ${#input_args[@]} -eq 0 ]; then
                if counterpart_exists "$input" "$REVERSE_MODE"; then
                    clear_progress
                    log_warn "Skip (exists): $input"
                    ((++total_skipped))
                    continue
                fi
            fi

            if process_file "$input" "$custom"; then
                ((++total_processed))
            else
                ((++total_failed))
                failed_files+=("$input")
                [ "$FORCE_CONTINUE" = false ] && [ "$total_failed" -gt 0 ] && break
            fi
        fi
    done

    clear_progress

    # Rename directories in recursive in-place mode.
    if [ "$INPLACE_MODE" = true ] && [ "$RECURSIVE_MODE" = true ]; then
        processed_dirs=()
        for arg in "${input_args[@]}"; do
            [ -d "$arg" ] || continue
            skip=false
            for pd in "${processed_dirs[@]}"; do
                [[ "$arg" == "$pd" || "$arg" == "$pd/"* ]] && skip=true && break
            done
            [ "$skip" = true ] && continue
            processed_dirs+=("$arg")
            rename_directories_recursive "$arg"
        done
    fi

    # Summary.
    echo ""
    log_info "${CYAN}═══════════════════════════════════════${NC}"
    log_info "${CYAN}Summary${NC}"
    log_info "${CYAN}═══════════════════════════════════════${NC}"
    log_info "  Processed: ${GREEN}$total_processed${NC}"
    log_info "  Skipped:   ${YELLOW}$total_skipped${NC}"
    log_info "  Failed:    ${RED}$total_failed${NC}"

    # Directory breakdown.
    if [ ${#dir_stats[@]} -gt 1 ]; then
        echo ""
        log_info "${BOLD}By directory:${NC}"
        for d in "${!dir_stats[@]}"; do
            log_info "  $d: ${dir_stats[$d]} files"
        done
    fi

    # Failed files.
    if [ "${#failed_files[@]}" -gt 0 ]; then
        echo ""
        log_error "Failed files:"
        for f in "${failed_files[@]}"; do
            log_error "  $f"
        done
    fi
fi

exit 0
