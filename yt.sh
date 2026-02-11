#!/usr/bin/env bash
set -eo pipefail

# ============================================================
# yt.sh - YouTube Playlist Smart Downloader (Rewritten by Mio)
# ============================================================
# Features:
#   - Parallel processing with progress bars for all operations
#   - Atomic JSON writes with temp file protection
#   - SponsorBlock data stored in index, batch processed at end
#   - Auto file renaming to "NNN - [OriginalFilename].m4a" format
#   - Track number and album metadata management
#   - Wayback Machine fallback for unavailable videos
# ============================================================

# Configuration constants.
readonly PARALLEL_JOBS=10
readonly CONFIG_PATH="$HOME/.config/yt-dlp/config"
readonly INDEX_FILE=".yt_index.json"
readonly TIMEOUT=120
readonly SB_API_DELAY=0.05
readonly SB_PARALLEL_JOBS=20

# Color codes for pretty output.
readonly COLOR_INFO='\033[1;34m'
readonly COLOR_OK='\033[1;32m'
readonly COLOR_WARN='\033[1;33m'
readonly COLOR_ERROR='\033[1;31m'
readonly COLOR_RESET='\033[0m'

# Playlist URL aliases for quick access.
declare -A ALIASES=(
	["homebrew"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v"
	["h"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v"
	["topgrade"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft"
	["t"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft"
	["kyuKurarin"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp"
	["k"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp"
)

# Directory name to URL mapping for auto-detection.
declare -A DIR_ALIASES=(
	["homebrew"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v"
	["topgrade"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft"
	["kyuKurarin"]="https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp"
)

# ============================================================
# Logging Functions
# ============================================================

log_info() { echo -e "${COLOR_INFO}ℹ️  $*${COLOR_RESET}"; }
log_ok() { echo -e "${COLOR_OK}✅ $*${COLOR_RESET}"; }
log_warn() { echo -e "${COLOR_WARN}⚠️  $*${COLOR_RESET}"; }
log_error() { echo -e "${COLOR_ERROR}❌ $*${COLOR_RESET}"; }

# ============================================================
# Help and Usage
# ============================================================

show_help() {
	cat <<'EOF'
Usage: yt.sh [url|alias]

YouTube Playlist Smart Downloader with SponsorBlock integration.

Aliases:
  homebrew, h   - Homebrew playlist
  topgrade, t   - Topgrade playlist
  kyuKurarin, k - kyuKurarin playlist

Features:
  - Parallel downloads with progress bar
  - SponsorBlock segment tracking and auto-redownload
  - Automatic file renaming (NNN - [Filename].m4a)
  - Track metadata management
  - Wayback Machine fallback

Examples:
  yt.sh h
  yt.sh https://youtube.com/playlist?list=...
  cd ~/Music/homebrew && yt.sh

Index file: .yt_index.json (auto-generated)
EOF
}

# ============================================================
# URL Resolution Functions
# ============================================================

# Resolve alias or validate URL input.
resolve_url() {
	local input="$1"

	# Check aliases first.
	if [[ -n "${ALIASES[$input]:-}" ]]; then
		echo "${ALIASES[$input]}"
		return 0
	fi

	# Validate URL format.
	if [[ "$input" =~ ^https?:// ]] || [[ "$input" =~ youtube\.com ]] || [[ "$input" =~ youtu\.be ]]; then
		echo "$input"
		return 0
	fi

	return 1
}

# Auto-detect playlist URL from current directory name.
detect_from_directory() {
	local current_dir
	current_dir=$(basename "$PWD")

	if [[ -n "${DIR_ALIASES[$current_dir]:-}" ]]; then
		echo "${DIR_ALIASES[$current_dir]}"
		return 0
	fi

	return 1
}

# ============================================================
# File Naming Functions
# ============================================================

# Extract 11-character YouTube video ID from filename.
extract_video_id() {
	local filename="$1"

	if [[ "$filename" =~ \[([a-zA-Z0-9_-]{11})\]\.[^.]+$ ]]; then
		echo "${BASH_REMATCH[1]}"
	elif [[ "$filename" =~ ^([a-zA-Z0-9_-]{11})\.[^.]+$ ]]; then
		# Handle bare ID filenames like "FSilOEFMxXk.m4a".
		echo "${BASH_REMATCH[1]}"
	fi
}

# Extract the base filename without index prefix.
# Input: "001 - Something [ID].m4a" or "Something [ID].m4a" or "[ID].m4a"
# Output: "Something [ID].m4a" (without index prefix)
extract_base_filename() {
	local filename="$1"

	# Remove NNN - prefix if present.
	if [[ "$filename" =~ ^[0-9]{3}\ -\ (.+)$ ]]; then
		echo "${BASH_REMATCH[1]}"
	else
		echo "$filename"
	fi
}

# Check if filename matches the indexed format "NNN - [Name].m4a".
is_indexed_format() {
	local filename="$1"
	[[ "$filename" =~ ^[0-9]{3}\ -\ .+\.m4a$ ]]
}

# Generate indexed filename: "NNN - [OriginalName].m4a".
generate_indexed_filename() {
	local index="$1"
	local base_filename="$2"

	printf "%03d - %s" "$index" "$base_filename"
}

# ============================================================
# JSON File Operations (Atomic Writes)
# ============================================================

# Safely write JSON to file using atomic rename.
# This prevents corruption if jq fails or process is interrupted.
atomic_json_write() {
	local target_file="$1"
	local json_content="$2"

	local tmp_file
	tmp_file=$(mktemp "${target_file}.tmp.XXXXXX")

	# Write to temp file first.
	if ! echo "$json_content" | jq '.' >"$tmp_file" 2>/dev/null; then
		log_error "JSON validation failed, aborting write"
		rm -f "$tmp_file"
		return 1
	fi

	# Atomic rename.
	if ! mv "$tmp_file" "$target_file"; then
		log_error "Failed to rename temp file to target"
		rm -f "$tmp_file"
		return 1
	fi

	return 0
}

# Read value from index JSON safely.
read_index_value() {
	local key="$1"
	local index_file="$PWD/$INDEX_FILE"

	if [[ ! -f "$index_file" ]]; then
		echo ""
		return 0
	fi

	jq -r "$key // empty" "$index_file" 2>/dev/null || echo ""
}

# Get stored SponsorBlock hash for a video ID.
get_stored_sb_hash() {
	local video_id="$1"
	local index_file="$PWD/$INDEX_FILE"

	if [[ ! -f "$index_file" ]]; then
		echo ""
		return 0
	fi

	jq -r --arg id "$video_id" \
		'.songs[] | select(.id == $id) | .sb_hash // empty' \
		"$index_file" 2>/dev/null || echo ""
}

# Get stored track number for a video ID.
get_stored_track() {
	local video_id="$1"
	local index_file="$PWD/$INDEX_FILE"

	if [[ ! -f "$index_file" ]]; then
		echo ""
		return 0
	fi

	jq -r --arg id "$video_id" \
		'.songs[] | select(.id == $id) | .track // empty' \
		"$index_file" 2>/dev/null || echo ""
}

# ============================================================
# SponsorBlock API Functions
# ============================================================

# Fetch SponsorBlock segments and compute hash.
# Returns "no_segments" if no segments exist, otherwise SHA256 hash.
get_sb_hash() {
	local video_id="$1"

	local categories='%5B%22sponsor%22%2C%22selfpromo%22%2C%22interaction%22%2C%22intro%22%2C%22outro%22%2C%22preview%22%2C%22music_offtopic%22%2C%22filler%22%5D'
	local api_url="https://sponsor.ajay.app/api/skipSegments?videoID=${video_id}&categories=${categories}"

	local response
	response=$(curl -s -f --max-time 10 "$api_url" 2>/dev/null) || {
		echo "no_segments"
		return 0
	}

	# Empty or no segments.
	if [[ -z "$response" || "$response" == "[]" || "$response" == "Not Found" ]]; then
		echo "no_segments"
		return 0
	fi

	# Normalize and hash the response.
	local normalized
	normalized=$(echo "$response" | jq -c 'sort_by(.segment[0]) | [.[] | {segment, category}]' 2>/dev/null) || {
		echo "no_segments"
		return 0
	}

	echo "$normalized" | sha256sum | cut -d' ' -f1
}

# Fetch SponsorBlock hash for a single video (for parallel execution).
# Output format: "video_id|hash"
fetch_sb_hash_worker() {
	local video_id="$1"

	sleep "$SB_API_DELAY"
	local hash
	hash=$(get_sb_hash "$video_id")

	echo "${video_id}|${hash}"
}

# ============================================================
# Download Functions
# ============================================================

# Download a single video with metadata.
# Arguments: video_id, track_num, album_name
download_single() {
	local video_id="$1"
	local track_num="$2"
	local album_name="$3"
	local url="https://www.youtube.com/watch?v=${video_id}"

	# Try direct download first.
	if yt-dlp --config-location "$CONFIG_PATH" \
		--parse-metadata "%(album,playlist_title)s:%(meta_album)s" \
		--replace-in-metadata meta_album ".*" "$album_name" \
		--parse-metadata "${track_num}:%(meta_track)s" \
		-o "%(title)s [%(id)s].%(ext)s" \
		"$url" 2>/dev/null; then
		echo "OK:${video_id}"
		return 0
	fi

	# Fallback to Wayback Machine.
	local archive_url="https://web.archive.org/web/${url}"
	if yt-dlp --config-location "$CONFIG_PATH" \
		--parse-metadata "%(album,playlist_title)s:%(meta_album)s" \
		--replace-in-metadata meta_album ".*" "$album_name" \
		--parse-metadata "${track_num}:%(meta_track)s" \
		-o "%(title)s [%(id)s].%(ext)s" \
		"$archive_url" 2>/dev/null; then
		echo "ARCHIVE:${video_id}"
		return 0
	fi

	echo "FAIL:${video_id}"
	return 1
}

# ============================================================
# File Renaming Functions
# ============================================================

# Rename all audio files to indexed format.
# This runs after all metadata is updated.
rename_files_to_indexed_format() {
	log_info "Renaming files to indexed format..."

	local rename_list
	rename_list=$(mktemp)
	local rename_count=0

	shopt -s nullglob
	for file in "$PWD"/*.m4a; do
		[[ -f "$file" ]] || continue

		local filename basename_file track_num base_name new_filename
		filename=$(basename "$file")

		# Get track number from metadata.
		track_num=$(ffprobe -v quiet -show_entries format_tags=track \
			-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
		track_num=${track_num:-0}

		# Skip if track is 0 (unknown).
		if [[ "$track_num" == "0" ]]; then
			log_warn "  Skipping (no track): $filename"
			continue
		fi

		# Extract base filename without existing index prefix.
		base_name=$(extract_base_filename "$filename")

		# Handle bare ID filenames (e.g., "FSilOEFMxXk.m4a").
		local vid
		vid=$(extract_video_id "$filename")
		if [[ "$filename" =~ ^[a-zA-Z0-9_-]{11}\.m4a$ && -n "$vid" ]]; then
			# Bare ID file - need to get proper title.
			# For now, keep as "[ID].m4a" format.
			base_name="[${vid}].m4a"
		fi

		# Generate new indexed filename.
		new_filename=$(generate_indexed_filename "$track_num" "$base_name")

		# Skip if already correct.
		if [[ "$filename" == "$new_filename" ]]; then
			continue
		fi

		# Check for collision.
		if [[ -f "$PWD/$new_filename" && "$PWD/$new_filename" != "$file" ]]; then
			log_warn "  Collision, skipping: $filename -> $new_filename"
			continue
		fi

		echo "${file}|${new_filename}" >>"$rename_list"
		rename_count=$((rename_count + 1))
	done
	shopt -u nullglob

	if [[ $rename_count -eq 0 ]]; then
		log_ok "All files already in correct format"
		rm -f "$rename_list"
		return 0
	fi

	log_info "Renaming $rename_count files..."

	while IFS='|' read -r old_path new_name; do
		local old_name
		old_name=$(basename "$old_path")
		local new_path="$PWD/$new_name"

		if mv "$old_path" "$new_path" 2>/dev/null; then
			echo "  $old_name -> $new_name"
		else
			log_error "  Failed: $old_name"
		fi
	done <"$rename_list"

	rm -f "$rename_list"
	log_ok "File renaming complete"
}

# ============================================================
# Index Management Functions
# ============================================================

# Build and save the complete index file.
# This is called at the end after all processing.
save_index() {
	local album_name="$1"
	local playlist_url="$2"
	local sb_data_file="$3" # File containing "vid|hash" lines.

	log_info "Building index file..."

	# Build associative array of SB hashes if provided.
	declare -A sb_hashes
	if [[ -n "$sb_data_file" && -f "$sb_data_file" ]]; then
		while IFS='|' read -r vid hash; do
			[[ -n "$vid" ]] && sb_hashes["$vid"]="$hash"
		done <"$sb_data_file"
	fi

	# Build songs array.
	local songs_json="[]"
	local file_list
	file_list=$(mktemp)

	shopt -s nullglob
	for file in "$PWD"/*.m4a; do
		[[ -f "$file" ]] || continue

		local filename vid track sb_hash
		filename=$(basename "$file")
		vid=$(extract_video_id "$filename")

		[[ -z "$vid" ]] && continue

		track=$(ffprobe -v quiet -show_entries format_tags=track \
			-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
		track=${track:-0}

		# Get SB hash from collected data or existing index.
		sb_hash="${sb_hashes[$vid]:-}"
		if [[ -z "$sb_hash" ]]; then
			sb_hash=$(get_stored_sb_hash "$vid")
		fi

		# Build JSON object for this song.
		local song_obj
		if [[ -n "$sb_hash" ]]; then
			song_obj=$(jq -n \
				--arg id "$vid" \
				--argjson track "$track" \
				--arg file "$filename" \
				--arg sb_hash "$sb_hash" \
				'{id: $id, track: $track, file: $file, sb_hash: $sb_hash}')
		else
			song_obj=$(jq -n \
				--arg id "$vid" \
				--argjson track "$track" \
				--arg file "$filename" \
				'{id: $id, track: $track, file: $file}')
		fi

		echo "$song_obj" >>"$file_list"
	done
	shopt -u nullglob

	# Combine all song objects into array.
	if [[ -s "$file_list" ]]; then
		songs_json=$(jq -s 'sort_by(.track)' "$file_list")
	fi
	rm -f "$file_list"

	# Build final JSON.
	local final_json
	final_json=$(jq -n \
		--arg album "$album_name" \
		--arg url "$playlist_url" \
		--arg updated "$(date -Iseconds)" \
		--argjson songs "$songs_json" \
		'{album: $album, url: $url, updated: $updated, songs: $songs}')

	# Atomic write.
	if atomic_json_write "$PWD/$INDEX_FILE" "$final_json"; then
		log_ok "Index saved: $INDEX_FILE"
	else
		log_error "Failed to save index"
		return 1
	fi
}

# ============================================================
# Metadata Update Functions
# ============================================================

# Update track metadata for a single file.
# Arguments: file_path, track_num, album_name
update_track_metadata() {
	local file="$1"
	local track="$2"
	local album="$3"

	if tageditor set album="$album" track="$track" --force-rewrite --files "$file" 2>/dev/null; then
		echo "OK:$(basename "$file")"
	else
		echo "FAIL:$(basename "$file")"
	fi
}

# ============================================================
# Main Sync Logic
# ============================================================

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

	# Extract album name.
	local album_name
	album_name=$(head -1 "$tmp_json" | jq -r '.playlist_title // empty')

	if [[ -z "$album_name" || "$album_name" == "null" ]]; then
		album_name=$(basename "$PWD")
		log_warn "Could not get playlist title, using directory name: $album_name"
	fi

	log_info "Album: $album_name"
	log_info "Directory: $PWD"
	echo ""

	# ========================================
	# Phase 1: Parse remote playlist
	# ========================================
	log_info "Parsing remote playlist..."

	local remote_file
	remote_file=$(mktemp)
	local remote_count=0

	while IFS= read -r line; do
		[[ -z "$line" ]] && continue

		local vid idx
		vid=$(echo "$line" | jq -r '.id // empty')
		[[ -z "$vid" ]] && vid=$(echo "$line" | jq -r '.url // empty' | grep -oE '[a-zA-Z0-9_-]{11}' | head -1)
		idx=$(echo "$line" | jq -r '.playlist_index // empty')

		if [[ -n "$vid" && -n "$idx" && "$idx" != "null" ]]; then
			echo "${vid}|${idx}" >>"$remote_file"
			remote_count=$((remote_count + 1))
		fi
	done <"$tmp_json"

	rm -f "$tmp_json"
	log_ok "Found $remote_count songs in remote playlist"

	# ========================================
	# Phase 2: Scan local files
	# ========================================
	log_info "Scanning local files..."

	local local_file
	local_file=$(mktemp)
	local local_count=0

	shopt -s nullglob
	for file in "$PWD"/*.m4a; do
		[[ -f "$file" ]] || continue

		local vid track filename
		filename=$(basename "$file")
		vid=$(extract_video_id "$filename")

		if [[ -n "$vid" ]]; then
			track=$(ffprobe -v quiet -show_entries format_tags=track \
				-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
			track=${track:-0}
			echo "${vid}|${track}|${file}" >>"$local_file"
			local_count=$((local_count + 1))
		fi
	done
	shopt -u nullglob

	log_ok "Found $local_count songs locally"
	echo ""

	# ========================================
	# Phase 3: Analyze differences
	# ========================================
	log_info "Analyzing differences..."

	local to_download_file
	to_download_file=$(mktemp)
	local download_count=0
	local orphan_count=0
	local need_shift=0

	# Find songs to download (in remote, not in local).
	while IFS='|' read -r vid idx; do
		if ! grep -q "^${vid}|" "$local_file"; then
			echo "${vid}|${idx}" >>"$to_download_file"
			download_count=$((download_count + 1))
		fi
	done <"$remote_file"

	# Find orphans (in local, not in remote).
	while IFS='|' read -r vid track file; do
		if ! grep -q "^${vid}|" "$remote_file"; then
			orphan_count=$((orphan_count + 1))
		fi
	done <"$local_file"

	# Calculate maximum shift needed.
	while IFS='|' read -r vid track file; do
		local remote_idx
		remote_idx=$(grep "^${vid}|" "$remote_file" 2>/dev/null | cut -d'|' -f2)

		if [[ -n "$remote_idx" && "$remote_idx" != "0" ]]; then
			if ((remote_idx > track && track > 0)); then
				local diff=$((remote_idx - track))
				((diff > need_shift)) && need_shift=$diff
			fi
		fi
	done <"$local_file"

	log_info "To download: $download_count"
	log_info "Local orphans: $orphan_count"
	log_info "Track shift needed: $need_shift"
	echo ""

	# ========================================
	# Phase 4: Shift existing tracks (parallel)
	# ========================================
	if ((need_shift > 0)); then
		log_info "Shifting existing tracks by +$need_shift..."

		local shift_list
		shift_list=$(mktemp)

		# Build shift list sorted by track descending (to avoid collisions).
		shopt -s nullglob
		for file in "$PWD"/*.m4a; do
			[[ -f "$file" ]] || continue

			local track
			track=$(ffprobe -v quiet -show_entries format_tags=track \
				-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
			track=${track:-0}

			local new_track=$((track + need_shift))
			echo "${file}|${new_track}|${album_name}" >>"$shift_list"
		done
		shopt -u nullglob

		# Export function for parallel.
		export -f update_track_metadata

		# Run parallel shift with progress bar.
		parallel --bar --colsep '\|' -j "$PARALLEL_JOBS" \
			"update_track_metadata {1} {2} {3}" <"$shift_list" 2>/dev/null || true

		rm -f "$shift_list"
		rm -f "$PWD"/*.bak 2>/dev/null || true
		log_ok "Shift complete"
		echo ""
	fi

	# ========================================
	# Phase 5: Download new songs (parallel)
	# ========================================
	if [[ -s "$to_download_file" ]]; then
		log_info "Starting parallel download (jobs: $PARALLEL_JOBS)..."

		local download_list
		download_list=$(mktemp)

		while IFS='|' read -r vid idx; do
			echo "${vid}|${idx}|${album_name}" >>"$download_list"
		done <"$to_download_file"

		# Export function and config for parallel.
		export -f download_single
		export CONFIG_PATH

		# Run downloads with progress bar.
		parallel --bar --colsep '\|' -j "$PARALLEL_JOBS" \
			"download_single {1} {2} {3}" <"$download_list" 2>/dev/null || true

		rm -f "$download_list"
		log_ok "Downloads complete"
		echo ""
	else
		log_ok "Nothing to download"
		echo ""
	fi

	rm -f "$to_download_file"

	# ========================================
	# Phase 6: Final reindex (parallel metadata update)
	# ========================================
	log_info "Reindexing all tracks..."

	local reindex_list
	reindex_list=$(mktemp)
	local sorted_reindex
	sorted_reindex=$(mktemp)

	# Build list of all files with current tracks.
	shopt -s nullglob
	for file in "$PWD"/*.m4a; do
		[[ -f "$file" ]] || continue

		local vid track
		vid=$(extract_video_id "$(basename "$file")")

		# Get target track from remote playlist.
		local target_track
		target_track=$(grep "^${vid}|" "$remote_file" 2>/dev/null | cut -d'|' -f2)

		if [[ -z "$target_track" ]]; then
			# Orphan - use current track number.
			track=$(ffprobe -v quiet -show_entries format_tags=track \
				-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | cut -d'/' -f1)
			target_track=${track:-999}
		fi

		echo "${target_track}|${file}" >>"$reindex_list"
	done
	shopt -u nullglob

	# Sort by target track number.
	sort -t'|' -k1 -n "$reindex_list" >"$sorted_reindex"

	# Build final update list with sequential numbering.
	local update_list
	update_list=$(mktemp)
	local index=1

	while IFS='|' read -r _ file; do
		echo "${file}|${index}|${album_name}" >>"$update_list"
		index=$((index + 1))
	done <"$sorted_reindex"

	rm -f "$reindex_list" "$sorted_reindex"

	# Parallel metadata update.
	export -f update_track_metadata

	parallel --bar --colsep '\|' -j "$PARALLEL_JOBS" \
		"update_track_metadata {1} {2} {3}" <"$update_list" 2>/dev/null || true

	rm -f "$update_list"
	rm -f "$PWD"/*.bak 2>/dev/null || true
	log_ok "Reindex complete"
	echo ""

	# ========================================
	# Phase 7: Check SponsorBlock (parallel)
	# ========================================
	log_info "Checking SponsorBlock segments (parallel)..."

	local sb_check_list
	sb_check_list=$(mktemp)
	local sb_results
	sb_results=$(mktemp)
	local sb_redownload
	sb_redownload=$(mktemp)

	# Build list of video IDs to check.
	shopt -s nullglob
	for file in "$PWD"/*.m4a; do
		[[ -f "$file" ]] || continue

		local vid
		vid=$(extract_video_id "$(basename "$file")")
		[[ -n "$vid" ]] && echo "$vid" >>"$sb_check_list"
	done
	shopt -u nullglob

	# Export function for parallel.
	export -f fetch_sb_hash_worker get_sb_hash
	export SB_API_DELAY

	# Fetch all SB hashes in parallel with progress bar.
	parallel --bar -j "$SB_PARALLEL_JOBS" \
		"fetch_sb_hash_worker {}" <"$sb_check_list" >"$sb_results" 2>/dev/null || true

	rm -f "$sb_check_list"

	# Compare with stored hashes and find changes.
	local sb_changed=0
	while IFS='|' read -r vid new_hash; do
		[[ -z "$vid" ]] && continue

		local stored_hash
		stored_hash=$(get_stored_sb_hash "$vid")

		# Skip if hash unchanged.
		if [[ "$stored_hash" == "$new_hash" ]]; then
			continue
		fi

		# Skip if new hash is no_segments and stored is empty.
		if [[ "$new_hash" == "no_segments" && -z "$stored_hash" ]]; then
			continue
		fi

		# Hash changed - mark for redownload.
		local track
		track=$(grep "^${vid}|" "$remote_file" 2>/dev/null | cut -d'|' -f2)
		track=${track:-1}

		# Find the file to delete.
		local old_file
		old_file=$(grep "|${vid}|" "$local_file" 2>/dev/null | cut -d'|' -f3)

		if [[ -n "$old_file" && -f "$old_file" ]]; then
			echo "${vid}|${track}|${old_file}|${new_hash}" >>"$sb_redownload"
			sb_changed=$((sb_changed + 1))
		fi
	done <"$sb_results"

	if [[ $sb_changed -gt 0 ]]; then
		log_warn "Found $sb_changed songs with SponsorBlock changes"
		log_info "Redownloading affected songs..."

		# Delete old files and redownload.
		while IFS='|' read -r vid track old_file new_hash; do
			rm -f "$old_file"
			log_info "  Redownloading: $vid"
		done <"$sb_redownload"

		# Build download list.
		local sb_download_list
		sb_download_list=$(mktemp)

		while IFS='|' read -r vid track old_file new_hash; do
			echo "${vid}|${track}|${album_name}" >>"$sb_download_list"
		done <"$sb_redownload"

		# Parallel redownload.
		parallel --bar --colsep '\|' -j "$PARALLEL_JOBS" \
			"download_single {1} {2} {3}" <"$sb_download_list" 2>/dev/null || true

		rm -f "$sb_download_list"
		rm -f "$PWD"/*.bak 2>/dev/null || true
		log_ok "SponsorBlock redownload complete"
	else
		log_ok "No SponsorBlock changes detected"
	fi

	# Update sb_results to include unchanged hashes for index.
	# Merge new hashes into results file.
	local final_sb_data
	final_sb_data=$(mktemp)
	cp "$sb_results" "$final_sb_data"

	# Add redownloaded hashes.
	while IFS='|' read -r vid track old_file new_hash; do
		echo "${vid}|${new_hash}" >>"$final_sb_data"
	done <"$sb_redownload"

	rm -f "$sb_redownload"
	echo ""

	# ========================================
	# Phase 8: Rename files to indexed format
	# ========================================
	rename_files_to_indexed_format
	echo ""

	# ========================================
	# Phase 9: Save final index (atomic write)
	# ========================================
	save_index "$album_name" "$url" "$final_sb_data"

	# Cleanup.
	rm -f "$remote_file" "$local_file" "$sb_results" "$final_sb_data"

	echo ""
	log_ok "🎉 Sync complete!"
}

# ============================================================
# Main Entry Point
# ============================================================

main() {
	local url=""

	# Handle help flag.
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		show_help
		exit 0
	fi

	# Resolve URL from argument or directory.
	if [[ -n "${1:-}" ]]; then
		url=$(resolve_url "$1") || {
			log_error "Unknown alias or invalid URL: $1"
			show_help
			exit 1
		}
	else
		url=$(detect_from_directory) || {
			log_error "No argument and directory doesn't match any alias"
			log_info "Current directory: $(basename "$PWD")"
			show_help
			exit 1
		}
		log_ok "Auto-detected from directory: $(basename "$PWD")"
	fi

	sync_playlist "$url"
}

main "$@"
