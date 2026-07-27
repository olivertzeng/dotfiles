#!/usr/bin/env python3
"""
yt.py - YouTube Playlist Downloader

Dependencies:
    sudo pacman -S python-rich python-requests python-mutagen yt-dlp

Download Options:
    -s  Enable SponsorBlock detection
"""

import hashlib
import json
import re
import shutil
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from threading import BoundedSemaphore

import requests
from mutagen.mp4 import MP4, MP4Cover
from rich.console import Console
from rich.progress import (BarColumn, MofNCompleteColumn, Progress,
                           SpinnerColumn, TaskProgressColumn, TextColumn,
                           TimeRemainingColumn)

# ============================================================
# Config
# ============================================================
PARALLEL_DOWNLOADS = 4
SB_CONCURRENCY = 16
SB_API_DELAY = 0.05
TIMEOUT = 120

CONFIG_PATH = Path.home() / ".config" / "yt-dlp" / "config"
INDEX_FILE = ".yt_index.json"

ALIASES: dict[str, str] = {
    "homebrew": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v",
    "h": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v",
    "topgrade": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft",
    "t": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft",
    "kyuKurarin": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp",
    "k": "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp",
}

DIR_ALIASES: dict[str, str] = {
    "homebrew": ALIASES["homebrew"],
    "topgrade": ALIASES["topgrade"],
    "kyuKurarin": ALIASES["kyuKurarin"],
}

PLAYLIST_YEAR: dict[str, str] = {
    "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v": "2024",
    "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft": "2023",
    "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp": "2025",
}

ID_RE = re.compile(r"\[([a-zA-Z0-9_-]{11})]")
sb_sem = BoundedSemaphore(SB_CONCURRENCY)

console = Console(highlight=False)


# ============================================================
# Data
# ============================================================
@dataclass
class RemoteSong:
    id: str
    track: int
    title: str
    artist: str = ""
    upload_year: str = ""
    description: str = ""


# ============================================================
# Trash & Keep System
# ============================================================
def load_keep(album_dir: Path) -> set[str]:
    """Load the .keep whitelist for an album directory.

    The .keep file contains one YouTube video ID per line.
    Lines starting with '#' are treated as comments.
    Full YouTube URLs are also accepted and parsed automatically.
    """
    keep_file = album_dir / ".keep"
    if not keep_file.exists():
        return set()
    ids: set[str] = set()
    for line in keep_file.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if "youtube.com" in line or "youtu.be" in line:
            match = re.search(r"(?:v=|/)([a-zA-Z0-9_-]{11})", line)
            if match:
                ids.add(match.group(1))
        elif re.fullmatch(r"[a-zA-Z0-9_-]{11}", line):
            ids.add(line)
    return ids


def add_to_keep(album_dir: Path, video_id: str, title: str = "") -> None:
    """Append a video ID to the album's .keep whitelist (idempotent)."""
    existing = load_keep(album_dir)
    if video_id in existing:
        return
    keep_file = album_dir / ".keep"
    with keep_file.open("a", encoding="utf-8") as f:
        comment = f"  # {title}" if title else ""
        f.write(f"{video_id}{comment}\n")
    console.print(f"  [green]+ Added {video_id} to .keep[/green]")


def _load_trash_manifest(trash_dir: Path) -> set[str]:
    """Load the set of video IDs that have been soft-deleted."""
    manifest = trash_dir / ".manifest"
    if not manifest.exists():
        return set()
    return {
        line.strip()
        for line in manifest.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


def _save_trash_manifest(trash_dir: Path, ids: set[str]) -> None:
    """Persist the trash manifest to disk."""
    manifest = trash_dir / ".manifest"
    trash_dir.mkdir(parents=True, exist_ok=True)
    manifest.write_text("\n".join(sorted(ids)) + "\n" if ids else "", encoding="utf-8")


def move_to_trash(file_path: Path, trash_dir: Path) -> None:
    """Soft-delete: move a file to .trash/ and record its ID in manifest."""
    trash_dir.mkdir(parents=True, exist_ok=True)
    dest = trash_dir / file_path.name
    shutil.move(str(file_path), str(dest))

    vid = extract_id(file_path.name)
    if vid:
        manifest = _load_trash_manifest(trash_dir)
        manifest.add(vid)
        _save_trash_manifest(trash_dir, manifest)


def detect_restored(work_dir: Path, trash_dir: Path, remote_ids: set[str]) -> None:
    """Auto-detect files restored from .trash/ back to an album folder.

    If a file in work_dir has an ID recorded in the trash manifest AND
    that ID is not in the current remote playlist, the user must have
    manually restored it → auto-add to .keep so it won't be trashed again.
    """
    manifest = _load_trash_manifest(trash_dir)
    if not manifest:
        return

    updated = set(manifest)

    for vid in list(manifest):
        # If the video is back in the playlist, just clean up the manifest
        if vid in remote_ids:
            updated.discard(vid)
            continue

        # Check if a file with this ID exists in the current album dir
        matches = [f for f in work_dir.glob("*.m4a") if f"[{vid}]" in f.name]
        if matches:
            title = matches[0].stem.split(f" [{vid}]")[0]
            console.print(
                f"  [cyan]♻ Restored from trash: {matches[0].name} "
                f"→ auto-adding to .keep[/cyan]"
            )
            add_to_keep(work_dir, vid, title)
            updated.discard(vid)
            # Remove leftover copy in .trash/ if it still exists
            for tf in trash_dir.glob(f"*[{vid}]*"):
                if tf.is_file():
                    tf.unlink(missing_ok=True)

    _save_trash_manifest(trash_dir, updated)


# ============================================================
# Utilities
# ============================================================
def extract_id(filename: str) -> str | None:
    m = ID_RE.search(filename)
    return m.group(1) if m else None


def scan_and_clean(
    work_dir: Path,
    remote_ids: set[str],
    keep_ids: set[str] | None = None,
    trash_dir: Path | None = None,
) -> dict[str, Path]:
    """Scan work_dir for .m4a files; trash orphans/duplicates, return valid map.

    Files not in the remote playlist are moved to .trash/ unless their ID
    appears in keep_ids.  Duplicates (same ID, multiple files) keep only
    the first sorted file; extras are trashed.
    """
    if keep_ids is None:
        keep_ids = set()

    id_to_files: dict[str, list[Path]] = {}
    no_id_files: list[Path] = []

    for f in work_dir.glob("*.m4a"):
        if ".temp." in f.name or ".part" in f.name:
            continue
        vid = extract_id(f.name)
        if vid:
            if vid not in id_to_files:
                id_to_files[vid] = []
            id_to_files[vid].append(f)
        else:
            no_id_files.append(f)

    result: dict[str, Path] = {}
    removed = 0

    # Files with no parseable video ID → trash
    for f in no_id_files:
        console.log(f"[yellow]No ID, trashing:[/yellow] {f.name}")
        try:
            if trash_dir:
                move_to_trash(f, trash_dir)
            else:
                f.unlink()
            removed += 1
        except OSError:
            pass

    for vid, files in id_to_files.items():
        if vid not in remote_ids:
            # ── Protected by .keep → skip entirely ──
            if vid in keep_ids:
                console.log(f"[green]⛔ Protected by .keep:[/green] {files[0].name}")
                continue
            # ── Not protected → soft-delete ──
            for f in files:
                console.log(f"[yellow]Not in playlist, trashing:[/yellow] {f.name}")
                try:
                    if trash_dir:
                        move_to_trash(f, trash_dir)
                    else:
                        f.unlink()
                    removed += 1
                except OSError:
                    pass
        elif len(files) == 1:
            result[vid] = files[0]
        else:
            # Duplicates: keep first (sorted), trash the rest
            files.sort()
            result[vid] = files[0]
            for f in files[1:]:
                console.log(f"[yellow]Duplicate ID {vid}, trashing:[/yellow] {f.name}")
                try:
                    if trash_dir:
                        move_to_trash(f, trash_dir)
                    else:
                        f.unlink()
                    removed += 1
                except OSError:
                    pass

    if removed:
        console.log(f"[yellow]Cleaned {removed} file(s) → .trash/[/yellow]")

    return result


TEMP_EXTS: frozenset[str] = frozenset(
    {
        ".temp.m4a",
        ".part",
        ".ytdl",
        ".f140.m4a",
        ".f251.webm",
        ".f140.webm",
    }
)
ART_EXTS: frozenset[str] = frozenset({".jpg", ".jpeg", ".webp", ".png"})
KILL_EXTS = TEMP_EXTS | ART_EXTS


def cleanup(work_dir: Path, vid: str | None = None) -> int:
    """Remove temp/art files (hard delete — these are build artifacts)."""
    removed = 0
    targets = work_dir.glob(f"*{vid}*") if vid else work_dir.iterdir()
    for f in targets:
        if f.is_file() and f.name.startswith("cover."):
            continue
        if f.is_file() and any(f.name.endswith(e) for e in KILL_EXTS):
            try:
                f.unlink()
                removed += 1
            except OSError:
                pass
    return removed


def run(cmd: list[str], timeout: int = TIMEOUT) -> tuple[bool, str]:
    import subprocess

    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode == 0, r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return False, "timed out"
    except Exception as e:
        return False, str(e)


def make_progress() -> Progress:
    return Progress(
        SpinnerColumn(),
        TextColumn("[bold]{task.description}"),
        BarColumn(),
        MofNCompleteColumn(),
        TaskProgressColumn(),
        TimeRemainingColumn(),
        console=console,
    )


# ============================================================
# Thumbnail
# ============================================================
def has_thumbnail(path: Path) -> bool:
    try:
        audio = MP4(path)
        return "covr" in audio.tags and len(audio.tags["covr"]) > 0
    except Exception:
        return False


def fetch_thumbnail(vid: str, work_dir: Path) -> Path | None:
    urls = [
        f"https://img.youtube.com/vi/{vid}/maxresdefault.jpg",
        f"https://img.youtube.com/vi/{vid}/hqdefault.jpg",
        f"https://img.youtube.com/vi/{vid}/mqdefault.jpg",
    ]
    for url in urls:
        try:
            r = requests.get(url, timeout=10)
            if r.status_code == 200 and len(r.content) > 1000:
                thumb_path = work_dir / f".thumb_{vid}.jpg"
                with open(thumb_path, "wb") as f:
                    f.write(r.content)
                return thumb_path
        except Exception:
            continue
    return None


def embed_thumbnail(path: Path, thumb_path: Path) -> bool:
    try:
        audio = MP4(path)
        if audio.tags is None:
            audio.add_tags()
        with open(thumb_path, "rb") as f:
            audio.tags["covr"] = [MP4Cover(f.read(), imageformat=MP4Cover.FORMAT_JPEG)]
        audio.save()
        return True
    except Exception:
        return False


# ============================================================
# Metadata Extraction
# ============================================================
def _read_info_json(song: RemoteSong, work_dir: Path) -> RemoteSong:
    """Read .info.json written by yt-dlp, update song fields, delete the file."""
    for f in work_dir.glob("*.info.json"):
        if f"[{song.id}]" not in f.name:
            continue
        try:
            with open(f) as fh:
                d = json.loads(fh.read())
            artist = d.get("uploader", d.get("channel", ""))
            if artist.endswith(" - Topic"):
                artist = artist[:-8]
            if artist:
                song.artist = artist
            upload_date = d.get("upload_date", "")
            if len(upload_date) >= 4:
                song.upload_year = upload_date[:4]
            desc = d.get("description", "")
            if desc:
                song.description = desc
            title = d.get("title", "")
            if title:
                song.title = title
        except Exception:
            pass
        finally:
            try:
                f.unlink()
            except OSError:
                pass
        break
    return song


def _fetch_metadata(song: RemoteSong) -> RemoteSong:
    """Fetch full metadata for one video (no download)."""
    url = f"https://www.youtube.com/watch?v={song.id}"
    ok, out = run(["yt-dlp", "-j", "--skip-download", url], timeout=30)
    if not ok or not out.strip():
        return song
    for line in reversed(out.strip().split("\n")):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        artist = d.get("uploader", d.get("channel", ""))
        if artist.endswith(" - Topic"):
            artist = artist[:-8]
        if artist:
            song.artist = artist
        upload_date = d.get("upload_date", "")
        if len(upload_date) >= 4:
            song.upload_year = upload_date[:4]
        desc = d.get("description", "")
        if desc:
            song.description = desc
        title = d.get("title", "")
        if title:
            song.title = title
        break
    return song


# ============================================================
# Tasks
# ============================================================
def do_download(
    song: RemoteSong, album: str, work_dir: Path
) -> tuple[RemoteSong, bool, str]:
    url = f"https://www.youtube.com/watch?v={song.id}"
    cmd = [
        "yt-dlp",
        "--config-location",
        str(CONFIG_PATH),
        "--parse-metadata",
        f"{album}:%(meta_album)s",
        "--parse-metadata",
        f"{song.track}:%(meta_track)s",
        "-o",
        "%(title)s [%(id)s].%(ext)s",
        "--no-mtime",
        "--no-embed-thumbnail",
        "--write-info-json",
        url,
    ]
    ok, out = run(cmd)

    if ok:
        song = _read_info_json(song, work_dir)
    cleanup(work_dir, song.id)

    if ok:
        existing = [f for f in work_dir.glob("*.m4a") if f"[{song.id}]" in f.name]
        if not existing:
            return song, False, "File not found after download"
        return song, True, ""

    # Fallback: archive.org
    cmd[-1] = f"https://web.archive.org/web/{url}"
    ok, out = run(cmd)

    if ok:
        song = _read_info_json(song, work_dir)
    cleanup(work_dir, song.id)

    if ok:
        existing = [f for f in work_dir.glob("*.m4a") if f"[{song.id}]" in f.name]
        if not existing:
            return song, False, "File not found after archive download"
    return song, ok, out


def do_metadata(
    path: Path,
    song: RemoteSong,
    album: str,
    album_year: str,
    thumb_path: Path | None = None,
) -> bool:
    """Write metadata tags to an m4a file.

    The comment field (\xa9cmt) is set to the YouTube video URL
    for easy reference instead of the raw video description.
    """
    try:
        audio = MP4(path)
        if audio.tags is None:
            audio.add_tags()

        video_url = f"https://www.youtube.com/watch?v={song.id}"

        audio.tags["\xa9nam"] = song.title
        audio.tags["\xa9ART"] = song.artist
        audio.tags["\xa9alb"] = album
        audio.tags["aART"] = "olivertzeng"
        audio.tags["trkn"] = [(song.track, 0)]
        audio.tags["\xa9day"] = album_year
        audio.tags["\xa9cmt"] = video_url

        if thumb_path and thumb_path.exists():
            with open(thumb_path, "rb") as f:
                audio.tags["covr"] = [
                    MP4Cover(f.read(), imageformat=MP4Cover.FORMAT_JPEG)
                ]
        audio.save()
        return True
    except Exception:
        return False


def do_sb(vid: str) -> tuple[str, str, int, str]:
    cats = (
        '["sponsor","selfpromo","interaction","intro","outro",'
        '"preview","music_offtopic","filler"]'
    )
    url = (
        f"https://sponsor.ajay.app/api/skipSegments" f"?videoID={vid}&categories={cats}"
    )
    with sb_sem:
        time.sleep(SB_API_DELAY)
        try:
            r = requests.get(url, timeout=10)
            if r.status_code == 404:
                return vid, "no_segments", 0, ""
            r.raise_for_status()
            data = r.json()
            if not data:
                return vid, "no_segments", 0, ""
            norm = sorted(data, key=lambda x: x.get("segment", [0])[0])
            items = [{"segment": x["segment"], "category": x["category"]} for x in norm]
            h = hashlib.sha256(json.dumps(items, sort_keys=True).encode()).hexdigest()
            return vid, h, len(items), ""
        except requests.exceptions.HTTPError as e:
            return vid, "error", 0, f"HTTP {e.response.status_code}"
        except Exception as e:
            return vid, "error", 0, str(e)


# ============================================================
# Rename
# ============================================================
def enforce_names(
    remote_songs: list[RemoteSong],
    local_map: dict[str, Path],
    work_dir: Path,
) -> dict[str, Path]:
    renamed = 0
    for song in remote_songs:
        if song.id not in local_map:
            continue
        old_path = local_map[song.id]
        safe_title = song.title or "Unknown"
        safe = re.sub(r'[\\/*?:"<>|]', "", safe_title)
        new_name = f"{song.track:03d} - {safe} [{song.id}].m4a"
        new_path = work_dir / new_name
        if old_path == new_path:
            continue
        try:
            old_path.rename(new_path)
            local_map[song.id] = new_path
            renamed += 1
        except OSError as e:
            console.log(f"[yellow]Rename failed {song.id}: {e}[/yellow]")
    if renamed:
        console.log(f"[green]Renamed {renamed} files[/green]")
    return local_map


# ============================================================
# Sync
# ============================================================
def sync(url: str, enable_sb: bool = False) -> None:
    work_dir = Path.cwd()
    trash_dir = work_dir.parent / ".trash"

    removed = cleanup(work_dir)
    if removed:
        console.log(f"[dim]Cleaned {removed} temp files[/dim]")

    album_year = PLAYLIST_YEAR.get(url, str(datetime.now().year))

    # ── Fetch playlist (structure only) ────────────────────
    console.log("[cyan]Fetching playlist...[/cyan]")
    ok, out = run(["yt-dlp", "--flat-playlist", "-j", url])
    if not ok:
        console.log(f"[red]Failed to fetch playlist:\n{out}[/red]")
        sys.exit(1)

    remote_songs: list[RemoteSong] = []
    album_name = "Unknown Album"
    for line in out.strip().split("\n"):
        if not line:
            continue
        try:
            d = json.loads(line)
            if album_name == "Unknown Album" and d.get("playlist_title"):
                album_name = d["playlist_title"]
            vid = d.get("id")
            idx = d.get("playlist_index")
            title = d.get("title") or "Unknown"
            if vid and idx:
                remote_songs.append(RemoteSong(id=vid, track=int(idx), title=title))
        except Exception:
            continue

    # ── Deduplicate ────────────────────────────────────────
    seen_ids: set[str] = set()
    unique_songs: list[RemoteSong] = []
    duplicates: list[RemoteSong] = []
    for song in remote_songs:
        if song.id in seen_ids:
            duplicates.append(song)
        else:
            seen_ids.add(song.id)
            unique_songs.append(song)

    if duplicates:
        console.log(f"[yellow]Skipping {len(duplicates)} duplicate(s):[/yellow]")
        for d in duplicates:
            console.log(f"[dim] - Track {d.track}: {d.title} [{d.id}][/dim]")
        remote_songs = unique_songs

    # ── Squash track numbers ───────────────────────────────
    for i, song in enumerate(remote_songs):
        song.track = i + 1

    vid_to_title: dict[str, str] = {s.id: s.title for s in remote_songs}
    console.log(f"[green]Playlist:[/green] {album_name} ({len(remote_songs)} songs)")

    # ── Load old index (cache + SB hashes) ─────────────────
    old_hashes: dict[str, str] = {}
    old_counts: dict[str, int] = {}
    old_meta: dict[str, dict] = {}
    index_path = work_dir / INDEX_FILE

    if index_path.exists():
        try:
            with open(index_path) as f:
                for s in json.load(f).get("songs", []):
                    if "id" not in s:
                        continue
                    old_hashes[s["id"]] = s.get("sb_hash", "")
                    old_counts[s["id"]] = s.get("sb_count", 0)
                    old_meta[s["id"]] = s
        except Exception:
            pass

    # ── Backfill metadata from cached index ────────────────
    for song in remote_songs:
        cached = old_meta.get(song.id, {})
        cached_artist = cached.get("artist", "")
        if cached_artist and cached_artist != "Unknown":
            song.artist = cached_artist
        cached_desc = cached.get("description", "")
        if cached_desc:
            song.description = cached_desc
        cached_year = cached.get("upload_year", "")
        if cached_year:
            song.upload_year = cached_year

    # ── Detect files restored from .trash/ ─────────────────
    remote_ids = {s.id for s in remote_songs}
    detect_restored(work_dir, trash_dir, remote_ids)

    # ── Load .keep whitelist (after detect_restored may have updated it)
    keep_ids = load_keep(work_dir)
    if keep_ids:
        console.log(f"[dim].keep whitelist: {len(keep_ids)} IDs[/dim]")

    # ── Clean duplicates and orphans ───────────────────────
    local_map = scan_and_clean(work_dir, remote_ids, keep_ids, trash_dir)

    # ── Identify missing ───────────────────────────────────
    missing = [s for s in remote_songs if s.id not in local_map]
    console.log(f"[dim]Local: {len(local_map)} | Missing: {len(missing)}[/dim]")

    # ── Phase 1: Download ─────────────────────────────────
    newly_downloaded: set[str] = set()

    if missing:
        with make_progress() as p:
            task = p.add_task("Downloading", total=len(missing))
            with ThreadPoolExecutor(max_workers=PARALLEL_DOWNLOADS) as pool:
                futures = {
                    pool.submit(do_download, s, album_name, work_dir): s
                    for s in missing
                }
                for fut in as_completed(futures):
                    song, ok, err = fut.result()
                    if ok:
                        newly_downloaded.add(song.id)
                        console.log(f"[green]Downloaded:[/green] {song.title}")
                    else:
                        last = err.splitlines()[-1] if err else "unknown"
                        console.log(
                            f"[red]Failed:[/red] {song.title}" f"\n [dim]{last}[/dim]"
                        )
                    p.advance(task)

        local_map = scan_and_clean(work_dir, remote_ids, keep_ids, trash_dir)

    # ── Phase 1.5: Fetch metadata for songs missing artist ─
    needs_meta = [
        s
        for s in remote_songs
        if s.id in local_map and (not s.artist or s.artist == "Unknown")
    ]

    if needs_meta:
        console.log(
            f"[cyan]Fetching metadata for {len(needs_meta)} "
            f"songs with missing artist...[/cyan]"
        )
        with make_progress() as p:
            task = p.add_task("Metadata fetch", total=len(needs_meta))
            with ThreadPoolExecutor(max_workers=PARALLEL_DOWNLOADS) as pool:
                futures = {pool.submit(_fetch_metadata, s): s for s in needs_meta}
                for fut in as_completed(futures):
                    song = fut.result()
                    if song.artist and song.artist != "Unknown":
                        console.log(
                            f"[green]Got artist:[/green] "
                            f"{song.title} → {song.artist}"
                        )
                    else:
                        console.log(f"[dim]No artist: {song.title}[/dim]")
                    p.advance(task)

    # ── Phase 2: Thumbnails ────────────────────────────────
    thumb_tasks: list[tuple[Path, str]] = []
    for song in remote_songs:
        if song.id not in local_map:
            continue
        path = local_map[song.id]
        if not has_thumbnail(path):
            thumb_tasks.append((path, song.id))

    if thumb_tasks:
        console.log(f"[cyan]Fetching thumbnails for {len(thumb_tasks)} files...[/cyan]")
        with make_progress() as p:
            task = p.add_task("Thumbnails", total=len(thumb_tasks))
            for path, vid in thumb_tasks:
                thumb = fetch_thumbnail(vid, work_dir)
                if thumb:
                    if embed_thumbnail(path, thumb):
                        console.log(f"[green]Thumbnail:[/green] {path.name}")
                    else:
                        console.log(f"[red]Embed failed:[/red] {path.name}")
                    thumb.unlink(missing_ok=True)
                else:
                    console.log(f"[dim]No thumbnail: {vid}[/dim]")
                p.advance(task)

    # ── Phase 3: Metadata (ALL files) ──────────────────────
    meta_songs = [s for s in remote_songs if s.id in local_map]

    if meta_songs:
        with make_progress() as p:
            task = p.add_task("Metadata", total=len(meta_songs))
            with ThreadPoolExecutor(max_workers=PARALLEL_DOWNLOADS) as pool:
                futs = {
                    pool.submit(
                        do_metadata,
                        local_map[s.id],
                        s,
                        album_name,
                        album_year,
                    ): None
                    for s in meta_songs
                }
                for _ in as_completed(futs):
                    p.advance(task)

    # ── Phase 4: Rename ────────────────────────────────────
    local_map = enforce_names(remote_songs, local_map, work_dir)

    # ── Phase 5: SponsorBlock ──────────────────────────────
    vids_need_sb = list(local_map.keys())
    new_hashes: dict[str, str] = {}
    new_counts: dict[str, int] = {}
    sb_changed: list[str] = []

    if not enable_sb:
        console.log("[dim]SponsorBlock check disabled.[/dim]")
        for vid in vids_need_sb:
            new_hashes[vid] = old_hashes.get(vid, "")
            new_counts[vid] = old_counts.get(vid, 0)
    else:
        # NOTE: cache logic placeholder — currently re-fetches all
        vids_use_cache: list[str] = []

        console.log(
            f"[dim]SponsorBlock: fetching {len(vids_need_sb)}, "
            f"using cache for {len(vids_use_cache)}[/dim]"
        )

        for vid in vids_use_cache:
            new_hashes[vid] = old_hashes[vid]
            new_counts[vid] = old_counts.get(vid, 0)

        if vids_need_sb:
            with make_progress() as p:
                task = p.add_task("SponsorBlock", total=len(vids_need_sb))
                with ThreadPoolExecutor(max_workers=SB_CONCURRENCY) as pool:
                    futures = {pool.submit(do_sb, vid): vid for vid in vids_need_sb}
                    for fut in as_completed(futures):
                        vid, h, count, err_msg = fut.result()
                        title = vid_to_title.get(vid, vid)

                        if h == "error":
                            console.log(
                                f"[red]SB error[/red] {title} "
                                f"[dim]({err_msg})[/dim]"
                            )
                            new_hashes[vid] = old_hashes.get(vid, "error")
                            new_counts[vid] = old_counts.get(vid, 0)

                        elif h == "no_segments":
                            console.log(f"[dim]SB none {title}[/dim]")
                            new_hashes[vid] = "no_segments"
                            new_counts[vid] = 0

                        else:
                            old_count = old_counts.get(vid, 0)
                            diff = count - old_count

                            if vid in newly_downloaded or not old_hashes.get(vid):
                                diff_str = f"[green]+{count}[/green]"
                            elif diff > 0:
                                diff_str = f"[yellow]+{diff}[/yellow]"
                            elif diff < 0:
                                diff_str = f"[red]{diff}[/red]"
                            else:
                                diff_str = "[dim] =[/dim]"

                            console.log(f"[cyan]SB ok[/cyan] {diff_str} {title}")
                            new_hashes[vid] = h
                            new_counts[vid] = count

                            if (
                                vid not in newly_downloaded
                                and old_hashes.get(vid)
                                and old_hashes[vid] != h
                            ):
                                sb_changed.append(vid)
                                console.log(f"[yellow]SB changed:[/yellow] {title}")

                        p.advance(task)

    # ── Phase 6: Re-download SB-changed ───────────────────
    if sb_changed:
        console.log(
            f"[yellow]Re-downloading {len(sb_changed)} " f"SB-changed songs...[/yellow]"
        )
        to_redownload = [s for s in remote_songs if s.id in sb_changed]

        with make_progress() as p:
            task = p.add_task("Redownload", total=len(to_redownload))
            with ThreadPoolExecutor(max_workers=PARALLEL_DOWNLOADS) as pool:
                futures = {
                    pool.submit(do_download, s, album_name, work_dir): s
                    for s in to_redownload
                }
                for fut in as_completed(futures):
                    song, ok, err = fut.result()
                    if ok:
                        console.log(f"[green]Redownloaded:[/green] {song.title}")
                    else:
                        console.log(f"[red]Redownload failed:[/red] {song.title}")
                    p.advance(task)

        local_map = scan_and_clean(work_dir, remote_ids, keep_ids, trash_dir)
        local_map = enforce_names(remote_songs, local_map, work_dir)

    # ── Phase 7: Save index ────────────────────────────────
    final_songs = []
    for s in remote_songs:
        if s.id in local_map:
            final_songs.append(
                {
                    "id": s.id,
                    "track": s.track,
                    "artist": s.artist,
                    "upload_year": s.upload_year,
                    "description": s.description,
                    "file": local_map[s.id].name,
                    "sb_hash": new_hashes.get(s.id),
                    "sb_count": new_counts.get(s.id, 0),
                }
            )

    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(
            {
                "album": album_name,
                "url": url,
                "year": album_year,
                "updated": datetime.now().isoformat(),
                "songs": final_songs,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    console.log(
        f"[bold green]Sync complete![/bold green] " f"{len(final_songs)} songs indexed."
    )


# ============================================================
# Entry
# ============================================================
if __name__ == "__main__":
    args = sys.argv[1:]
    enable_sb = False
    if "-s" in args:
        enable_sb = True
        args.remove("-s")

    if len(args) == 0:
        cwd = Path.cwd().name
        url = DIR_ALIASES.get(cwd)
        if not url:
            console.print("[red]Usage:[/red] ./yt.py [-s] [url|alias]")
            sys.exit(1)
        console.log(f"[dim]Auto-detected: {cwd}[/dim]")
    else:
        arg = args[0]
        if arg in ("-h", "--help"):
            print(__doc__)
            sys.exit(0)
        url = ALIASES.get(
            arg, arg if "youtube.com" in arg or "youtu.be" in arg else None
        )
        if not url:
            console.print(f"[red]Unknown alias or URL:[/red] {arg}")
            sys.exit(1)

    try:
        sync(url, enable_sb=enable_sb)
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted.[/yellow]")
        cleanup(Path.cwd())
        sys.exit(130)
