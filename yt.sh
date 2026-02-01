#!/bin/bash

# ========== 配置區 ==========
PARALLEL_JOBS=10
CONFIG_PATH="$HOME/.config/yt-dlp/config"

# 別名定義：alias|short|url
declare -A ALIASES=(
    ["homebrew"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v"
    ["h"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v"
    ["topgrade"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft"
    ["t"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft"
    ["kyuKurarin"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp"
    ["k"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp"
)

# 目錄名對應（僅全名，用於自動檢測）
declare -A DIR_ALIASES=(
    ["homebrew"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v"
    ["topgrade"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft"
    ["kyuKurarin"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp"
)

# ========== 函數區 ==========

show_help() {
    echo "Usage: $0 [url|alias]"
    echo ""
    echo "Aliases:"
    echo "  homebrew, h  - Homebrew playlist"
    echo "  topgrade, t  - Topgrade playlist"
    echo "  kyuKurarin, k - kyuKurarin playlist"
    echo ""
    echo "Examples:"
    echo "  $0 h"
    echo "  $0 homebrew"
    echo "  $0 https://youtube.com/playlist?list=..."
    echo ""
    echo "Auto-detect: Run without arguments in a directory named 'homebrew', 'topgrade', or 'kyuKurarin'"
}

resolve_url() {
    local input="$1"

    # 檢查是否是別名
    if [[ -n "${ALIASES[$input]}" ]]; then
        echo "${ALIASES[$input]}"
        return 0
    fi

    # 檢查是否是 URL（包含 http 或 youtube）
    if [[ "$input" =~ ^https?:// ]] || [[ "$input" =~ youtube\.com ]] || [[ "$input" =~ youtu\.be ]]; then
        echo "$input"
        return 0
    fi

    return 1
}

detect_from_directory() {
    local current_dir
    current_dir=$(basename "$PWD")

    if [[ -n "${DIR_ALIASES[$current_dir]}" ]]; then
        echo "${DIR_ALIASES[$current_dir]}"
        return 0
    fi

    return 1
}

download_playlist() {
    local url="$1"

    echo "🎵 Starting parallel download (jobs: $PARALLEL_JOBS)"
    echo "📂 Download directory: $PWD"
    echo "🔗 URL: $url"
    echo ""

    yt-dlp --flat-playlist -j "$url" 2>/dev/null | \
    jq -r '[.url, (.playlist_index | tostring), .playlist_title] | @tsv' | \
    parallel --colsep '\t' -j "$PARALLEL_JOBS" \
        yt-dlp \
        --config-location "$CONFIG_PATH" \
        --parse-metadata "'album:{3}'" \
        --parse-metadata "'track_number:{2}'" \
        '{1}'
}

# ========== 主程式 ==========

main() {
    local url=""

    if [[ -n "$1" ]]; then
        # 有參數：解析別名或 URL
        url=$(resolve_url "$1")
        if [[ -z "$url" ]]; then
            echo "❌ Error: Unknown alias or invalid URL: $1"
            echo ""
            show_help
            exit 1
        fi
    else
        # 無參數：嘗試從目錄名檢測
        url=$(detect_from_directory)
        if [[ -z "$url" ]]; then
            echo "❌ Error: No argument provided and current directory doesn't match any alias."
            echo "📂 Current directory: $(basename "$PWD")"
            echo ""
            show_help
            exit 1
        fi
        echo "✅ Auto-detected from directory name: $(basename "$PWD")"
    fi

    download_playlist "$url"
}

main "$@"
