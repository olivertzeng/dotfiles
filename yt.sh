#!/usr/bin/env bash
set -eo pipefail

# ============================================================
# yt.sh - YouTube Playlist Smart Downloader
# ============================================================

PARALLEL_JOBS=10
CONFIG_PATH="$HOME/.config/yt-dlp/config"
INDEX_FILE=".yt_index.json"
TIMEOUT=120
# beilu: 優化 - 將延遲從 0.5 改為 0.1，大幅加快檢查速度
SB_API_DELAY=0.1

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

# 從 SponsorBlock API 獲取段落並計算 hash
get_sb_hash() {
	local video_id="$1"
	local api_url="https://sponsor.ajay.app/api/skipSegments?videoID=${video_id}&categories=%5B%22sponsor%22%2C%22selfpromo%22%2C%22interaction%22%2C%22intro%22%2C%22outro%22%2C%22preview%22%2C%22music_offtopic%22%2C%22filler%22%5D"

	local response
	response=$(curl -s -f "$api_url" 2>/dev/null) || {
		# 404 或錯誤表示無段落，返回固定 hash
		echo "no_segments"
		return 0
	}

	# 無內容或空陣列
	if [[ -z "$response" || "$response" == "[]" ]]; then
		echo "no_segments"
		return 0
	fi

	# 排序並計算 hash（只取 segment 和 category 資訊）
	local normalized
	normalized=$(echo "$response" | jq -c 'sort_by(.segment[0]) | [.[] | {segment, category}]' 2>/dev/null) || {
		echo "no_segments"
		return 0
	}

	echo "$normalized" | sha256sum | cut -d' ' -f1
}

# 獲取已存儲的 sb_hash
get_stored_sb_hash() {
	local video_id="$1"
	local index_file="$PWD/$INDEX_FILE"

	if [[ ! -f "$index_file" ]]; then
		echo ""
		return 0
	fi

	jq -r --arg id "$video_id" '.songs[] | select(.id == $id) | .sb_hash // empty' "$index_file" 2>/dev/null || echo ""
}

save_index() {
	local album_name="$1"
	local playlist_url="$2"

	local songs_json="["
	local first=true

	shopt -s nullglob
	for file in "$PWD"/*.m4a; do
		[[ -f "$file" ]] || continue

		local vid track filename sb_hash
		filename=$(basename "$file")
		vid=$(extract_video_id "$filename")
		track=$(ffprobe -v quiet -show_entries format_tags=track \
			-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
		track=${track:-0}

		# 從現有索引獲取 sb_hash，若無則為空
		sb_hash=$(get_stored_sb_hash "$vid")

		if [[ -n "$vid" ]]; then
			$first || songs_json+=","
			first=false
			if [[ -n "$sb_hash" ]]; then
				songs_json+="{\"id\":\"$vid\",\"track\":$track,\"file\":\"$filename\",\"sb_hash\":\"$sb_hash\"}"
			else
				songs_json+="{\"id\":\"$vid\",\"track\":$track,\"file\":\"$filename\"}"
			fi
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

# 更新單個歌曲的 sb_hash
update_sb_hash_in_index() {
	local video_id="$1"
	local new_hash="$2"
	local index_file="$PWD/$INDEX_FILE"

	if [[ ! -f "$index_file" ]]; then
		return 1
	fi

	local tmp_file
	tmp_file=$(mktemp)

	jq --arg id "$video_id" --arg hash "$new_hash" \
		'(.songs[] | select(.id == $id)) .sb_hash = $hash' \
		"$index_file" >"$tmp_file" && mv "$tmp_file" "$index_file"
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

# 檢查並重新下載 SponsorBlock 變化的歌曲
check_and_redownload_sponsorblock() {
	local album_name="$1"

	# beilu: 計算總檔案數，用於顯示進度
	local total_files
	total_files=$(ls "$PWD"/*.m4a 2>/dev/null | wc -l)
	local current_index=0

	# 使用 -n 不換行，方便後續覆蓋
	echo -ne "\033[1;34mℹ️  Checking SponsorBlock segments... (0/$total_files)\033[0m"

	local to_redownload=()
	local redownload_info=() # 存儲 "vid|track|file" 格式

	shopt -s nullglob
	for file in "$PWD"/*.m4a; do
		[[ -f "$file" ]] || continue

		# beilu: 更新進度計數
		current_index=$((current_index + 1))
		echo -ne "\r\033[1;34mℹ️  Checking SponsorBlock segments... ($current_index/$total_files)\033[0m"

		local filename vid track stored_hash current_hash
		filename=$(basename "$file")
		vid=$(extract_video_id "$filename")

		[[ -z "$vid" ]] && continue

		track=$(ffprobe -v quiet -show_entries format_tags=track \
			-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
		track=${track:-1}

		stored_hash=$(get_stored_sb_hash "$vid")

		# 加入延遲避免 rate limit
		sleep "$SB_API_DELAY"
		current_hash=$(get_sb_hash "$vid")

		# 首次運行（無 stored_hash）或 hash 變化
		if [[ -z "$stored_hash" || "$stored_hash" != "$current_hash" ]]; then
			to_redownload+=("$vid")
			redownload_info+=("$vid|$track|$file|$current_hash")
		fi
	done
	shopt -u nullglob

	# beilu: 檢查完成，換行
	echo ""

	local count=${#to_redownload[@]}

	if [[ $count -eq 0 ]]; then
		log_ok "No SponsorBlock changes detected"
		return 0
	fi

	log_info "Found $count songs with SponsorBlock changes, redownloading..."

	for info in "${redownload_info[@]}"; do
		IFS='|' read -r vid track old_file new_hash <<<"$info"

		log_info "  Redownloading: $vid (track $track)"

		# 刪除舊檔案
		rm -f "$old_file"

		# 下載新檔案
		if download_single "$vid" "$track" "$album_name"; then
			# 更新索引中的 sb_hash
			update_sb_hash_in_index "$vid" "$new_hash"
			log_ok "  Done: $vid"
		else
			log_error "  Failed: $vid"
		fi
	done

	# 清理 .bak 檔案
	rm -f "$PWD"/*.bak 2>/dev/null || true

	log_ok "SponsorBlock redownload complete"
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

	# 7. 檢查 SponsorBlock 變化並重新下載
	echo ""
	check_and_redownload_sponsorblock "$album_name"

	# 8. 更新索引
	echo ""
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
