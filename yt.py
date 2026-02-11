#!/usr/bin/env python3
"""
yt.py - YouTube Playlist Smart Downloader

Features:
    - Parallel processing with progress bars for all operations
    - Atomic JSON writes with temp file protection
    - SponsorBlock data stored in index, batch processed at end
    - Auto file renaming to "NNN - [OriginalFilename].m4a" format
    - Track number and album metadata management
    - Wayback Machine fallback for unavailable videos
    - Automatic cleanup of temp/thumbnail/meta files

Dependencies:
    sudo pacman -S python-tqdm python-requests

Usage:
    ./yt.py [url|alias]
    ./yt.py h
    cd ~/Music/homebrew && ./yt.py
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import Future, ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Final

import requests
from tqdm import tqdm

# ============================================================
# Configuration
# ============================================================

PARALLEL_JOBS: Final[int] = 10
SB_PARALLEL_JOBS: Final[int] = 20
CONFIG_PATH: Final[Path] = Path.home() / ".config" / "yt-dlp" / "config"
INDEX_FILE: Final[str] = ".yt_index.json"
TIMEOUT: Final[int] = 120
SB_API_DELAY: Final[float] = 0.05

CLEANUP_EXTENSIONS: Final[tuple[str, ...]] = (
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".meta",
    ".bak",
)

ALIASES: Final[dict[str, str]] = {
    "homebrew": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v",
    "h": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v",
    "topgrade": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft",
    "t": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft",
    "kyuKurarin": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp",
    "k": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp",
}

DIR_ALIASES: Final[dict[str, str]] = {
    "homebrew": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v",
    "topgrade": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft",
    "kyuKurarin": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp",
}

TQDM_FORMAT: Final[str] = "{desc} {bar:35} {n_fmt}/{total_fmt}"
TQDM_CHARS: Final[str] = " ━"


# ============================================================
# ANSI Colors
# ============================================================


class Color:
    """ANSI color codes for terminal output."""

    INFO: Final[str] = "\033[1;34m"
    OK: Final[str] = "\033[1;32m"
    WARN: Final[str] = "\033[1;33m"
    ERROR: Final[str] = "\033[1;31m"
    DIM: Final[str] = "\033[2m"
    RESET: Final[str] = "\033[0m"


def log_info(msg: str) -> None:
    print(f"{Color.INFO}ℹ  {msg}{Color.RESET}")


def log_ok(msg: str) -> None:
    print(f"{Color.OK}✅ {msg}{Color.RESET}")


def log_warn(msg: str) -> None:
    print(f"{Color.WARN}⚠  {msg}{Color.RESET}")


def log_error(msg: str) -> None:
    print(f"{Color.ERROR}❌ {msg}{Color.RESET}")


def log_dim(msg: str) -> None:
    print(f"{Color.DIM}   {msg}{Color.RESET}")


# ============================================================
# Data Classes
# ============================================================


@dataclass
class Song:
    """Represents a song in the playlist index."""

    id: str
    track: int
    file: str
    sb_hash: str | None = None

    def to_dict(self) -> dict[str, str | int]:
        d: dict[str, str | int] = {
            "id": self.id,
            "track": self.track,
            "file": self.file,
        }
        if self.sb_hash:
            d["sb_hash"] = self.sb_hash
        return d


@dataclass
class PlaylistIndex:
    """Represents the playlist index file structure."""

    album: str
    url: str
    updated: str
    songs: list[Song] = field(default_factory=list)

    def to_dict(self) -> dict[str, str | list[dict[str, str | int]]]:
        return {
            "album": self.album,
            "url": self.url,
            "updated": self.updated,
            "songs": [s.to_dict() for s in self.songs],
        }


@dataclass
class RemoteSong:
    """Represents a song from the remote playlist."""

    id: str
    index: int


@dataclass
class LocalSong:
    """Represents a local audio file."""

    id: str
    track: int
    path: Path


# ============================================================
# Utility Functions
# ============================================================


def extract_video_id(filename: str) -> str | None:
    match = re.search(r"\[([a-zA-Z0-9_-]{11})\]\.[^.]+$", filename)
    if match:
        return match.group(1)

    match = re.match(r"^([a-zA-Z0-9_-]{11})\.[^.]+$", filename)
    if match:
        return match.group(1)

    return None


def extract_base_filename(filename: str) -> str:
    match = re.match(r"^(\d{3}) - (.+)$", filename)
    if match:
        return match.group(2)
    return filename


def generate_indexed_filename(index: int, base_filename: str) -> str:
    return f"{index:03d} - {base_filename}"


def get_track_from_file(filepath: Path) -> int:
    try:
        result = subprocess.run(
            [
                "ffprobe",
                "-v",
                "quiet",
                "-show_entries",
                "format_tags=track",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(filepath),
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0 and result.stdout.strip():
            track_str = result.stdout.strip().split("/")[0]
            return int(track_str) if track_str.isdigit() else 0
    except (subprocess.TimeoutExpired, ValueError, FileNotFoundError):
        pass
    return 0


def run_command(cmd: list[str], timeout: int = 60) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.returncode == 0, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return False, "Command timed out"
    except FileNotFoundError as e:
        return False, f"Command not found: {e}"


def truncate_error(error: str, max_len: int = 80) -> str:
    lines = [ln.strip() for ln in error.strip().split("\n") if ln.strip()]
    if not lines:
        return "Unknown error"

    last_line = lines[-1]
    if len(last_line) > max_len:
        return last_line[: max_len - 3] + "..."
    return last_line


def make_progress_bar(total: int, desc: str):
    """Create a pip-style progress bar."""
    return tqdm(
        total=total,
        desc=f"{desc:12}",
        bar_format=TQDM_FORMAT,
        ascii=TQDM_CHARS,
        leave=True,
    )


# ============================================================
# Cleanup Functions
# ============================================================


def cleanup_byproduct_files(directory: Path) -> int:
    removed = 0

    for ext in CLEANUP_EXTENSIONS:
        for filepath in directory.glob(f"*{ext}"):
            try:
                filepath.unlink()
                removed += 1
            except OSError:
                pass

    for filepath in directory.glob("*.temp.m4a"):
        try:
            filepath.unlink()
            removed += 1
        except OSError:
            pass

    for filepath in directory.glob("*.m4a.part"):
        try:
            filepath.unlink()
            removed += 1
        except OSError:
            pass

    return removed


def cleanup_files_for_video(directory: Path, video_id: str) -> int:
    removed = 0
    patterns = [
        f"*[{video_id}].jpg",
        f"*[{video_id}].jpeg",
        f"*[{video_id}].png",
        f"*[{video_id}].webp",
        f"*[{video_id}].meta",
        f"*[{video_id}].temp.m4a",
        f"*[{video_id}].m4a.part",
    ]

    for pattern in patterns:
        for filepath in directory.glob(pattern):
            try:
                filepath.unlink()
                removed += 1
            except OSError:
                pass

    return removed


# ============================================================
# JSON Operations
# ============================================================


def atomic_json_write(
    filepath: Path, data: dict[str, str | list[dict[str, str | int]]]
) -> bool:
    filepath.parent.mkdir(parents=True, exist_ok=True)

    tmp_fd, tmp_path = tempfile.mkstemp(
        suffix=".tmp",
        prefix=filepath.name + ".",
        dir=filepath.parent,
    )

    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        shutil.move(tmp_path, filepath)
        return True

    except OSError as e:
        log_error(f"JSON write failed: {e}")
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        return False


def load_index(directory: Path) -> PlaylistIndex | None:
    index_path = directory / INDEX_FILE

    if not index_path.exists():
        return None

    try:
        with open(index_path, encoding="utf-8") as f:
            data: dict[str, str | list[dict[str, str | int]]] = json.load(f)

        songs_data = data.get("songs", [])
        if not isinstance(songs_data, list):
            songs_data = []

        songs: list[Song] = []
        for s in songs_data:
            if isinstance(s, dict):
                song_id = s.get("id")
                song_track = s.get("track", 0)
                song_file = s.get("file", "")
                song_sb_hash = s.get("sb_hash")

                if isinstance(song_id, str):
                    songs.append(
                        Song(
                            id=song_id,
                            track=(
                                int(song_track)
                                if isinstance(song_track, (int, str))
                                else 0
                            ),
                            file=str(song_file),
                            sb_hash=str(song_sb_hash) if song_sb_hash else None,
                        )
                    )

        album = data.get("album", "")
        url = data.get("url", "")
        updated = data.get("updated", "")

        return PlaylistIndex(
            album=str(album) if album else "",
            url=str(url) if url else "",
            updated=str(updated) if updated else "",
            songs=songs,
        )
    except (json.JSONDecodeError, KeyError, OSError):
        return None


def get_stored_sb_hash(directory: Path, video_id: str) -> str | None:
    index = load_index(directory)
    if not index:
        return None

    for song in index.songs:
        if song.id == video_id:
            return song.sb_hash

    return None


# ============================================================
# SponsorBlock API
# ============================================================


def get_sb_hash(video_id: str) -> str:
    categories = json.dumps(
        [
            "sponsor",
            "selfpromo",
            "interaction",
            "intro",
            "outro",
            "preview",
            "music_offtopic",
            "filler",
        ]
    )

    url = f"https://sponsor.ajay.app/api/skipSegments?videoID={video_id}&categories={categories}"

    try:
        response = requests.get(url, timeout=10)

        if response.status_code == 404:
            return "no_segments"

        response.raise_for_status()
        data: list[dict[str, list[float] | str]] = response.json()

        if not data:
            return "no_segments"

        normalized = sorted(
            data,
            key=lambda x: (
                float(x["segment"][0]) if isinstance(x.get("segment"), list) else 0
            ),
        )
        normalized_list = [
            {"segment": x["segment"], "category": x["category"]} for x in normalized
        ]
        normalized_str = json.dumps(normalized_list, sort_keys=True)

        return hashlib.sha256(normalized_str.encode()).hexdigest()

    except (requests.RequestException, json.JSONDecodeError, KeyError, TypeError):
        return "no_segments"


def fetch_sb_hash_worker(video_id: str) -> tuple[str, str]:
    time.sleep(SB_API_DELAY)
    return video_id, get_sb_hash(video_id)


# ============================================================
# Download Functions
# ============================================================


def download_single(
    video_id: str, track_num: int, album_name: str, directory: Path
) -> tuple[str, bool, str]:
    url = f"https://www.youtube.com/watch?v={video_id}"

    cmd = [
        "yt-dlp",
        "--config-location",
        str(CONFIG_PATH),
        "--parse-metadata",
        f"{album_name}:%(meta_album)s",
        "--parse-metadata",
        f"{track_num}:%(meta_track)s",
        "-o",
        "%(title)s [%(id)s].%(ext)s",
        url,
    ]

    success, output = run_command(cmd, timeout=TIMEOUT)

    if success:
        cleanup_files_for_video(directory, video_id)
        return video_id, True, ""

    archive_url = f"https://web.archive.org/web/{url}"
    cmd[-1] = archive_url

    success, _ = run_command(cmd, timeout=TIMEOUT)
    cleanup_files_for_video(directory, video_id)

    if success:
        return video_id, True, ""

    return video_id, False, truncate_error(output)


# ============================================================
# Metadata Functions
# ============================================================


def update_track_metadata(filepath: Path, track: int, album: str) -> tuple[Path, bool]:
    cmd = [
        "tageditor",
        "set",
        f"album={album}",
        f"track={track}",
        "--force-rewrite",
        "--files",
        str(filepath),
    ]

    success, _ = run_command(cmd, timeout=30)
    return filepath, success


# ============================================================
# File Renaming
# ============================================================


def rename_files_to_indexed_format(directory: Path, remote_map: dict[str, int]) -> int:
    log_info("Renaming files...")

    renames: list[tuple[Path, Path, int]] = []

    for filepath in sorted(directory.glob("*.m4a")):
        if ".temp." in filepath.name:
            continue

        filename = filepath.name
        track_num = get_track_from_file(filepath)

        if track_num == 0:
            vid = extract_video_id(filename)
            if vid and vid in remote_map:
                track_num = remote_map[vid]

        if track_num == 0:
            log_warn(f"No track: {filename}")
            continue

        base_name = extract_base_filename(filename)

        vid = extract_video_id(filename)
        if re.match(r"^[a-zA-Z0-9_-]{11}\.m4a$", filename) and vid:
            base_name = f"[{vid}].m4a"

        new_filename = generate_indexed_filename(track_num, base_name)

        if filename == new_filename:
            continue

        new_path = directory / new_filename

        if new_path.exists() and new_path != filepath:
            log_warn(f"Collision: {filename}")
            continue

        renames.append((filepath, new_path, track_num))

    if not renames:
        log_ok("Files already named correctly")
        return 0

    renames.sort(key=lambda x: x[2])

    renamed = 0
    for old_path, new_path, _ in renames:
        try:
            old_path.rename(new_path)
            renamed += 1
        except OSError as e:
            log_error(f"Rename failed: {old_path.name} ({e})")

    log_ok(f"Renamed {renamed} files")
    return renamed


# ============================================================
# Index Building
# ============================================================


def save_index(
    directory: Path,
    album_name: str,
    playlist_url: str,
    sb_hashes: dict[str, str] | None = None,
    remote_map: dict[str, int] | None = None,
) -> bool:
    if sb_hashes is None:
        sb_hashes = {}
    if remote_map is None:
        remote_map = {}

    songs: list[Song] = []

    for filepath in sorted(directory.glob("*.m4a")):
        if ".temp." in filepath.name:
            continue

        filename = filepath.name
        vid = extract_video_id(filename)

        if not vid:
            continue

        track = get_track_from_file(filepath)

        if track == 0 and vid in remote_map:
            track = remote_map[vid]

        sb_hash = sb_hashes.get(vid)
        if sb_hash is None:
            sb_hash = get_stored_sb_hash(directory, vid)

        songs.append(
            Song(
                id=vid,
                track=track,
                file=filename,
                sb_hash=sb_hash,
            )
        )

    songs.sort(key=lambda s: s.track)

    index = PlaylistIndex(
        album=album_name,
        url=playlist_url,
        updated=datetime.now().isoformat(),
        songs=songs,
    )

    index_path = directory / INDEX_FILE
    return atomic_json_write(index_path, index.to_dict())


# ============================================================
# URL Resolution
# ============================================================


def resolve_url(input_str: str) -> str | None:
    if input_str in ALIASES:
        return ALIASES[input_str]

    if (
        re.match(r"^https?://", input_str)
        or "youtube.com" in input_str
        or "youtu.be" in input_str
    ):
        return input_str

    return None


def detect_from_directory() -> str | None:
    current_dir = Path.cwd().name
    return DIR_ALIASES.get(current_dir)


# ============================================================
# Playlist Fetching
# ============================================================


def fetch_remote_playlist(url: str) -> tuple[str, list[RemoteSong]]:
    log_info("Fetching playlist...")

    cmd = ["yt-dlp", "--flat-playlist", "-j", url]
    success, output = run_command(cmd, timeout=TIMEOUT)

    if not success or not output.strip():
        raise RuntimeError("Failed to fetch playlist")

    songs: list[RemoteSong] = []
    album_name: str = ""

    for line in output.strip().split("\n"):
        if not line:
            continue

        try:
            data: dict[str, str | int | None] = json.loads(line)
        except json.JSONDecodeError:
            continue

        if not album_name:
            playlist_title = data.get("playlist_title")
            if isinstance(playlist_title, str):
                album_name = playlist_title

        vid: str | None = None
        vid_raw = data.get("id")
        if isinstance(vid_raw, str):
            vid = vid_raw

        if not vid:
            vid_url = data.get("url")
            if isinstance(vid_url, str):
                match = re.search(r"[a-zA-Z0-9_-]{11}", vid_url)
                vid = match.group(0) if match else None

        idx_raw = data.get("playlist_index")
        idx: int | None = None
        if isinstance(idx_raw, int):
            idx = idx_raw
        elif isinstance(idx_raw, str) and idx_raw.isdigit():
            idx = int(idx_raw)

        if vid and idx is not None:
            songs.append(RemoteSong(id=vid, index=idx))

    if not album_name:
        album_name = Path.cwd().name
        log_warn(f"No playlist title, using: {album_name}")

    return album_name, songs


# ============================================================
# Local File Scanning
# ============================================================


def scan_local_files(directory: Path) -> list[LocalSong]:
    songs: list[LocalSong] = []

    for filepath in directory.glob("*.m4a"):
        if ".temp." in filepath.name:
            continue

        vid = extract_video_id(filepath.name)
        if vid:
            track = get_track_from_file(filepath)
            songs.append(LocalSong(id=vid, track=track, path=filepath))

    return songs


# ============================================================
# Main Sync Logic
# ============================================================


def sync_playlist(url: str) -> None:
    directory = Path.cwd()

    # Phase 0: Initial cleanup.
    cleaned = cleanup_byproduct_files(directory)
    if cleaned > 0:
        log_info(f"Cleaned {cleaned} leftover files")

    # Phase 1: Fetch remote playlist.
    album_name, remote_songs = fetch_remote_playlist(url)
    remote_map: dict[str, int] = {s.id: s.index for s in remote_songs}

    log_ok(f"{album_name} ({len(remote_songs)} songs)")

    # Phase 2: Scan local files.
    local_songs = scan_local_files(directory)
    local_ids = {s.id for s in local_songs}

    # Phase 3: Calculate differences.
    to_download = [s for s in remote_songs if s.id not in local_ids]
    orphans = [s for s in local_songs if s.id not in {r.id for r in remote_songs}]

    log_info(f"Local: {len(local_songs)} | New: {len(to_download)} | Orphan: {len(orphans)}")

    # Track newly downloaded songs.
    newly_downloaded: set[str] = set()

    # Phase 4: Download new songs.
    if to_download:
        results: list[tuple[str, bool, str]] = []

        with ThreadPoolExecutor(max_workers=PARALLEL_JOBS) as executor:
            futures: dict[Future[tuple[str, bool, str]], str] = {
                executor.submit(
                    download_single, song.id, song.index, album_name, directory
                ): song.id
                for song in to_download
            }

            with make_progress_bar(len(futures), "Download") as pbar:
                for future in as_completed(futures):
                    result = future.result()
                    results.append(result)
                    pbar.update(1)

        failures = [(vid, err) for vid, success, err in results if not success]
        succeeded = len(results) - len(failures)

        for vid, success, _ in results:
            if success:
                newly_downloaded.add(vid)

        if failures:
            log_warn(f"Downloads: {succeeded} ok, {len(failures)} failed")
            for vid, err in failures:
                log_dim(f"{vid}: {err}")
        else:
            log_ok(f"Downloaded {succeeded} songs")

        cleanup_byproduct_files(directory)

    # Phase 5: Reindex all tracks.
    local_songs = scan_local_files(directory)

    reindex_list: list[tuple[int, Path]] = []
    for song in local_songs:
        target_track = remote_map.get(song.id, 999)
        reindex_list.append((target_track, song.path))

    reindex_list.sort(key=lambda x: x[0])

    update_tasks: list[tuple[Path, int, str]] = [
        (path, idx + 1, album_name) for idx, (_, path) in enumerate(reindex_list)
    ]

    with ThreadPoolExecutor(max_workers=PARALLEL_JOBS) as executor:
        futures_meta: dict[Future[tuple[Path, bool]], Path] = {
            executor.submit(update_track_metadata, path, track, album): path
            for path, track, album in update_tasks
        }

        with make_progress_bar(len(futures_meta), "Metadata") as pbar:
            for future in as_completed(futures_meta):
                _ = future.result()
                pbar.update(1)

    cleanup_byproduct_files(directory)
    log_ok("Metadata updated")

    # Phase 6: Check SponsorBlock.
    local_songs = scan_local_files(directory)
    video_ids = [s.id for s in local_songs]

    existing_index = load_index(directory)
    is_first_run = existing_index is None or len(existing_index.songs) == 0

    sb_hashes: dict[str, str] = {}
    sb_changes: list[str] = []

    with ThreadPoolExecutor(max_workers=SB_PARALLEL_JOBS) as executor:
        futures_sb: dict[Future[tuple[str, str]], str] = {
            executor.submit(fetch_sb_hash_worker, vid): vid for vid in video_ids
        }

        with make_progress_bar(len(futures_sb), "SponsorBlock") as pbar:
            for future in as_completed(futures_sb):
                vid, new_hash = future.result()
                sb_hashes[vid] = new_hash

                if is_first_run or vid in newly_downloaded:
                    pbar.update(1)
                    continue

                stored_hash = get_stored_sb_hash(directory, vid)
                if stored_hash is not None and stored_hash != new_hash:
                    sb_changes.append(vid)

                pbar.update(1)

    if is_first_run:
        log_ok(f"Stored {len(sb_hashes)} SB hashes")
    elif sb_changes:
        log_warn(f"SB changed: {len(sb_changes)} songs")

        redownload_results: list[tuple[str, bool, str]] = []

        with ThreadPoolExecutor(max_workers=PARALLEL_JOBS) as executor:
            futures_redown: dict[Future[tuple[str, bool, str]], tuple[str, Path | None]] = {}

            for vid in sb_changes:
                track = remote_map.get(vid, 1)
                old_file: Path | None = None
                for song in local_songs:
                    if song.id == vid:
                        old_file = song.path
                        break

                future = executor.submit(
                    download_single, vid, track, album_name, directory
                )
                futures_redown[future] = (vid, old_file)

            with make_progress_bar(len(futures_redown), "Redownload") as pbar:
                for future in as_completed(futures_redown):
                    vid, old_file = futures_redown[future]
                    result_vid, success, err = future.result()
                    redownload_results.append((result_vid, success, err))

                    if success and old_file and old_file.exists():
                        new_files = [
                            f
                            for f in directory.glob(f"*[{vid}].m4a")
                            if f != old_file and ".temp." not in f.name
                        ]
                        if new_files:
                            old_file.unlink()
                    elif not success:
                        cleanup_files_for_video(directory, vid)

                    pbar.update(1)

        failures = [(vid, err) for vid, success, err in redownload_results if not success]
        succeeded = len(redownload_results) - len(failures)

        if failures:
            log_warn(f"Redownload: {succeeded} ok, {len(failures)} failed")
            for vid, err in failures:
                log_dim(f"{vid}: {err}")
        else:
            log_ok(f"Redownloaded {succeeded} songs")

        cleanup_byproduct_files(directory)
    else:
        log_ok("No SB changes")

    # Phase 7: Rename files.
    rename_files_to_indexed_format(directory, remote_map)

    # Phase 8: Final cleanup and save.
    cleanup_byproduct_files(directory)

    if save_index(directory, album_name, url, sb_hashes, remote_map):
        log_ok(f"Saved {INDEX_FILE}")
    else:
        log_error("Failed to save index")

    print()
    log_ok("Sync complete!")


# ============================================================
# Help
# ============================================================

HELP_TEXT: Final[str] = """
Usage: yt.py [url|alias]

Aliases:
  homebrew, h   - Homebrew playlist
  topgrade, t   - Topgrade playlist
  kyuKurarin, k - kyuKurarin playlist

Examples:
  ./yt.py h
  ./yt.py https://youtube.com/playlist?list=...
  cd ~/Music/homebrew && ./yt.py
"""


# ============================================================
# Main Entry Point
# ============================================================


def main() -> None:
    args = sys.argv[1:]

    if "-h" in args or "--help" in args:
        print(HELP_TEXT)
        sys.exit(0)

    url: str | None = None

    if args:
        url = resolve_url(args[0])
        if not url:
            log_error(f"Unknown: {args[0]}")
            print(HELP_TEXT)
            sys.exit(1)
    else:
        url = detect_from_directory()
        if not url:
            log_error("No argument and directory doesn't match alias")
            print(HELP_TEXT)
            sys.exit(1)
        log_ok(f"Auto: {Path.cwd().name}")

    try:
        sync_playlist(url)
    except KeyboardInterrupt:
        print()
        log_warn("Interrupted")
        sys.exit(130)
    except RuntimeError as e:
        log_error(str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()
