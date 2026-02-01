#!/usr/bin/env bash
set -eo pipefail # 移除 -u，避免關聯陣列問題

# ============================================================
# yt.sh - YouTube Playlist Smart Downloader
# ============================================================

PARALLEL_JOBS=10
CONFIG_PATH="$HOME/.config/yt-dlp/config"
INDEX_FILE=".yt_index.json"
TIMEOUT=120

declare -A ALIASES=(
	["homebrew"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v"
	["h"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v"
	["topgrade"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft"
	["t"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft"
	["kyuKurarin"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp"
	["k"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp"
)

declare -A DIR_ALIASES=(
	["homebrew"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v"
	["topgrade"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft"
	["kyuKurarin"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp"
)

log_info() { echo -e "\033[1;34mℹ️  $*\033[0m"; }
log_ok() { echo -e "\033[1;32m✅ $*\033[0m"; }
log_warn() { echo -e "\033[1;33m⚠️  $*\033[0m"; }
log_error() { echo -e "\033[1;31m❌ $*\033[0m"; }

show_help() {
	cat <<'EOF'
Usage: yt.sh [url|alias]

Aliases:
  homebrew, h   - Homebrew playlist
  topgrade, t   - Topgrade playlist
  kyuKurarin, k - kyuKurarin playlist

Examples:
  yt.sh h
  yt.sh https://youtube.com/playlist?list=...
  cd ~/Music/homebrew && yt.sh
EOF
}

resolve_url() {
	local input="$1"
	if [[ -n "${ALIASES[$input]:-}" ]]; then
		echo "${ALIASES[$input]}"
		return 0
	fi
	if [[ "$input" =~ ^https?:// ]] || [[ "$input" =~ youtube\.com ]] || [[ "$input" =~ youtu\.be ]]; then
		echo "$input"
		return 0
	fi
	return 1
}

detect_from_directory() {
	local current_dir
	current_dir=$(basename "$PWD")
	if [[ -n "${DIR_ALIASES[$current_dir]:-}" ]]; then
		echo "${DIR_ALIASES[$current_dir]}"
		return 0
	fi
	return 1
}

extract_video_id() {
	local filename="$1"
	if [[ "$filename" =~ \[([a-zA-Z0-9_-]{11})\]\.[^.]+$ ]]; then
		echo "${BASH_REMATCH[1]}"
	fi
}

save_index() {
	local album_name="$1"
	local playlist_url="$2"

	local songs_json="["
	local first=true

	shopt -s nullglob
	for file in "$PWD"/*.m4a; do
		[[ -f "$file" ]] || continue

		local vid track filename
		filename=$(basename "$file")
		vid=$(extract_video_id "$filename")
		track=$(ffprobe -v quiet -show_entries format_tags=track \
			-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
		track=${track:-0}

		if [[ -n "$vid" ]]; then
			$first || songs_json+=","
			first=false
			songs_json+="{\"id\":\"$vid\",\"track\":$track,\"file\":\"$filename\"}"
		fi
	done
	shopt -u nullglob

	songs_json+="]"

	jq -n \
		--arg album "$album_name" \
		--arg url "$playlist_url" \
		--arg updated "$(date -Iseconds)" \
		--argjson songs "$songs_json" \
		'{album: $album, url: $url, updated: $updated, songs: $songs}' \
		>"$PWD/$INDEX_FILE"
}

download_single() {
	local video_id="$1"
	local track_num="$2"
	local album_name="$3"
	local url="https://www.youtube.com/watch?v=${video_id}"

	if yt-dlp --config-location "$CONFIG_PATH" \
		--parse-metadata "${album_name}:%(meta_album)s" \
		--parse-metadata "${track_num}:%(meta_track)s" \
		"$url" 2>/dev/null; then
		return 0
	fi

	local archive_url="https://web.archive.org/web/${url}"
	if yt-dlp --config-location "$CONFIG_PATH" \
		--parse-metadata "${album_name}:%(meta_album)s" \
		--parse-metadata "${track_num}:%(meta_track)s" \
		"$archive_url" 2>/dev/null; then
		return 0
	fi

	return 1
}

sync_playlist() {
	local url="$1"

	log_info "Fetching remote playlist..."

	local tmp_json
	tmp_json=$(mktemp)

	if ! timeout "$TIMEOUT" yt-dlp --flat-playlist -j "$url" >"$tmp_json" 2>/dev/null; then
		log_error "Failed to fetch playlist (timeout or error)"
		rm -f "$tmp_json"
		exit 1
	fi

	if [[ ! -s "$tmp_json" ]]; then
		log_error "Empty response from yt-dlp"
		rm -f "$tmp_json"
		exit 1
	fi

	local album_name
	album_name=$(head -1 "$tmp_json" | jq -r '.playlist_title // empty')

	if [[ -z "$album_name" || "$album_name" == "null" ]]; then
		album_name=$(basename "$PWD")
		log_warn "Could not get playlist title, using directory name: $album_name"
	fi

	# 使用臨時檔案存放關聯陣列資料
	local remote_data
	remote_data=$(mktemp)

	local remote_count=0
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		local vid idx
		vid=$(echo "$line" | jq -r '.id // empty')
		[[ -z "$vid" ]] && vid=$(echo "$line" | jq -r '.url // empty' | grep -oE '[a-zA-Z0-9_-]{11}' | head -1)
		idx=$(echo "$line" | jq -r '.playlist_index // empty')

		if [[ -n "$vid" && -n "$idx" && "$idx" != "null" ]]; then
			echo "remote|$vid|$idx" >>"$remote_data"
			remote_count=$((remote_count + 1))
		fi
	done <"$tmp_json"

	rm -f "$tmp_json"

	log_info "Album: $album_name"
	log_info "Directory: $PWD"
	log_ok "Found $remote_count songs in remote playlist"
	echo ""

	# 2. 收集本地資料
	log_info "Scanning local files..."

	local local_count=0
	shopt -s nullglob
	for file in "$PWD"/*.m4a; do
		[[ -f "$file" ]] || continue
		local vid track
		vid=$(extract_video_id "$(basename "$file")")
		if [[ -n "$vid" ]]; then
			track=$(ffprobe -v quiet -show_entries format_tags=track \
				-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
			track=${track:-0}
			echo "local|$vid|$track|$file" >>"$remote_data"
			local_count=$((local_count + 1))
		fi
	done
	shopt -u nullglob

	log_ok "Found $local_count songs locally"

	# 3. 分析差異
	local to_download_file
	to_download_file=$(mktemp)

	local orphan_count=0
	local download_count=0
	local need_shift=0

	# 找出需要下載的（遠端有，本地沒有）
	while IFS='|' read -r type vid idx; do
		[[ "$type" != "remote" ]] && continue
		if ! grep -q "^local|$vid|" "$remote_data"; then
			echo "$vid|$idx" >>"$to_download_file"
			download_count=$((download_count + 1))
		fi
	done <"$remote_data"

	# 找出孤兒（本地有，遠端沒有）
	while IFS='|' read -r type vid track file; do
		[[ "$type" != "local" ]] && continue
		if ! grep -q "^remote|$vid|" "$remote_data"; then
			orphan_count=$((orphan_count + 1))
		fi
	done <"$remote_data"

	# 計算 shift
	while IFS='|' read -r type vid track file; do
		[[ "$type" != "local" ]] && continue
		local remote_idx
		remote_idx=$(grep "^remote|$vid|" "$remote_data" 2>/dev/null | cut -d'|' -f3)
		if [[ -n "$remote_idx" ]]; then
			if ((remote_idx > track)); then
				local diff=$((remote_idx - track))
				((diff > need_shift)) && need_shift=$diff
			fi
		fi
	done <"$remote_data"

	log_info "To download: $download_count"
	log_info "Local orphans: $orphan_count"
	log_info "Need shift: $need_shift"
	echo ""

	# 4. Shift
	if ((need_shift > 0)); then
		log_info "Shifting existing tracks by +$need_shift..."

		local shift_list
		shift_list=$(mktemp)

		shopt -s nullglob
		for file in "$PWD"/*.m4a; do
			[[ -f "$file" ]] || continue
			local track
			track=$(ffprobe -v quiet -show_entries format_tags=track \
				-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
			track=${track:-0}
			echo "${track}|${file}" >>"$shift_list"
		done
		shopt -u nullglob

		sort -t'|' -k1 -n -r "$shift_list" | while IFS='|' read -r track file; do
			local new_track=$((track + need_shift))
			tageditor set track="$new_track" --force-rewrite --files "$file" 2>/dev/null || true
			echo "  $track → $new_track: $(basename "$file")"
		done

		rm -f "$shift_list"
		rm -f "$PWD"/*.bak 2>/dev/null || true
		log_ok "Shift complete"
		echo ""
	fi

	# 5. 並行下載
	if [[ -s "$to_download_file" ]]; then
		log_info "Starting parallel download (jobs: $PARALLEL_JOBS)..."

		# 加入 album_name
		local download_list
		download_list=$(mktemp)
		while IFS='|' read -r vid idx; do
			echo "$vid|$idx|$album_name" >>"$download_list"
		done <"$to_download_file"

		export -f download_single
		export CONFIG_PATH

		parallel --colsep '\|' -j "$PARALLEL_JOBS" \
			"download_single {1} {2} {3}" <"$download_list" || true

		rm -f "$download_list"
		log_ok "Download complete"
		echo ""
	else
		log_ok "Nothing to download"
	fi

	rm -f "$to_download_file"
	rm -f "$remote_data"

	# 6. 最終 Reindex
	log_info "Final reindex..."

	local reindex_list
	reindex_list=$(mktemp)

	shopt -s nullglob
	for file in "$PWD"/*.m4a; do
		[[ -f "$file" ]] || continue
		local track
		track=$(ffprobe -v quiet -show_entries format_tags=track \
			-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
		track=${track:-0}
		echo "${track}|${file}" >>"$reindex_list"
	done
	shopt -u nullglob

	local index=1
	sort -t'|' -k1 -n "$reindex_list" | while IFS='|' read -r track file; do
		tageditor set album="$album_name" track="$index" --force-rewrite --files "$file" 2>/dev/null || true
		echo "  Track $index: $(basename "$file")"
		index=$((index + 1))
	done

	rm -f "$reindex_list"
	rm -f "$PWD"/*.bak 2>/dev/null || true

	# 7. 更新索引
	log_info "Updating index..."
	save_index "$album_name" "$url"

	echo ""
	log_ok "Sync complete!"
}

main() {
	local url=""

	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		show_help
		exit 0
	fi

	if [[ -n "${1:-}" ]]; then
		url=$(resolve_url "$1") || {
			log_error "Unknown alias or invalid URL: $1"
			show_help
			exit 1
		}
	else
		url=$(detect_from_directory) || {
			log_error "No argument and directory doesn't match any alias."
			log_info "Current directory: $(basename "$PWD")"
			show_help
			exit 1
		}
		log_ok "Auto-detected from directory: $(basename "$PWD")"
	fi

	sync_playlist "$url"
}

main "$@"
