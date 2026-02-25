#!/usr/bin/env python3
"""
yt.py - YouTube Playlist Downloader

Dependencies:
    sudo pacman -S python-rich python-requests python-mutagen yt-dlp
"""

import hashlib
import json
import re
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

# Per-playlist creation year. Falls back to current year if not specified.
PLAYLIST_YEAR: dict[str, str] = {
    "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K1kjniRx00Tbtqh7Ob30m5v": "2024",
    "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K2foVHjRnuc3t44TGfeo0Ft": "2023",
    "https://www.youtube.com/playlist?list=PLNv1Xy2Vg8K33VK5QZdyZy6OUsLljItgp": "2025",
}

ID_RE = re.compile(r"\[([a-zA-Z0-9_-]{11})\]")
sb_sem = BoundedSemaphore(SB_CONCURRENCY)

console = Console(highlight=False)

# ============================================================
# Description Cleaner
# ============================================================

# Patterns to strip from YouTube descriptions
_DESC_JUNK_RE = re.compile(
    r"("
    r"https?://\S+"  # URLs
    r"|#\S+"  # hashtags
    r"|subscribe\b.*"  # subscribe begging (case-insensitive)
    r"|チャンネル登録.*"  # JP subscribe begging
    r"|↓.*?↓"  # arrow-enclosed promo blocks
    r"|━+.*?━+"  # decorated separators
    r"|─+.*?─+"  # another separator style
    r"|＝+.*?＝+"  # JP equals separators
    r"|▼.*?▼"  # triangle-enclosed blocks
    r"|♪\s*iTunes.*"  # iTunes promo
    r"|♪\s*Spotify.*"  # Spotify promo
    r"|♪\s*Apple Music.*"  # Apple Music promo
    r"|follow\s+me\b.*"  # follow me lines
    r"|フォローしてね.*"  # JP follow me
    r"|please\s+like\b.*"  # like begging
    r"|高評価.*"  # JP like begging
    r"|🔔.*"  # notification bell spam
    r")",
    re.IGNORECASE | re.DOTALL,
)

_MULTI_NEWLINE_RE = re.compile(r"\n{3,}")


def clean_description(raw: str) -> str:
    """Strip URLs, hashtags, subscribe/follow spam, and promo blocks."""
    if not raw:
        return ""
    cleaned = _DESC_JUNK_RE.sub("", raw)
    # Collapse excessive blank lines
    cleaned = _MULTI_NEWLINE_RE.sub("\n\n", cleaned)
    return cleaned.strip()


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
# Utilities
# ============================================================


def extract_id(filename: str) -> str | None:
    m = ID_RE.search(filename)
    return m.group(1) if m else None


def scan_dir(work_dir: Path) -> dict[str, Path]:
    result = {}
    for f in work_dir.glob("*.m4a"):
        if ".temp." in f.name or ".part" in f.name:
            continue
        vid = extract_id(f.name)
        if vid:
            result[vid] = f
    return result


def scan_and_clean(work_dir: Path, remote_ids: set[str]) -> dict[str, Path]:
    """Scan .m4a files, remove duplicates (same ID), remove orphans (no ID or not in playlist)."""
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

    for f in no_id_files:
        console.log(f"[yellow]No ID, removing:[/yellow] {f.name}")
        try:
            f.unlink()
            removed += 1
        except OSError:
            pass

    for vid, files in id_to_files.items():
        if vid not in remote_ids:
            for f in files:
                console.log(f"[yellow]Not in playlist, removing:[/yellow] {f.name}")
                try:
                    f.unlink()
                    removed += 1
                except OSError:
                    pass
        elif len(files) == 1:
            result[vid] = files[0]
        else:
            files.sort()
            result[vid] = files[0]
            for f in files[1:]:
                console.log(f"[yellow]Duplicate ID {vid}, removing:[/yellow] {f.name}")
                try:
                    f.unlink()
                    removed += 1
                except OSError:
                    pass

    if removed:
        console.log(f"[yellow]Removed {removed} duplicate/orphan files[/yellow]")

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
    removed = 0
    targets = work_dir.glob(f"*{vid}*") if vid else work_dir.iterdir()
    for f in targets:
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
        "--no-write-info-json",
        url,
    ]
    ok, out = run(cmd)
    cleanup(work_dir, song.id)

    if ok:
        existing = [f for f in work_dir.glob("*.m4a") if f"[{song.id}]" in f.name]
        if not existing:
            return song, False, "File not found after download"
        return song, True, ""

    cmd[-1] = f"https://web.archive.org/web/{url}"
    ok, out = run(cmd)
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
    """Write M4A tags. Uses album_year (playlist creation year) for the date field."""
    try:
        audio = MP4(path)
        if audio.tags is None:
            audio.add_tags()
        audio.tags["\xa9nam"] = song.title
        audio.tags["\xa9ART"] = song.artist
        audio.tags["\xa9alb"] = album
        audio.tags["aART"] = "olivertzeng"
        audio.tags["trkn"] = [(song.track, 0)]
        audio.tags["\xa9day"] = album_year
        audio.tags["\xa9cmt"] = clean_description(song.description)
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
    cats = '["sponsor","selfpromo","interaction","intro","outro","preview","music_offtopic","filler"]'
    url = f"https://sponsor.ajay.app/api/skipSegments?videoID={vid}&categories={cats}"
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
        safe = re.sub(r'[\\/*?:"<>|]', "", song.title)
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


def sync(url: str) -> None:
    work_dir = Path.cwd()
    removed = cleanup(work_dir)
    if removed:
        console.log(f"[dim]Cleaned {removed} temp files[/dim]")

    # Resolve album year from config, fall back to current year
    album_year = PLAYLIST_YEAR.get(url, str(datetime.now().year))

    # ── Fetch playlist ─────────────────────────────────────────
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
            title = d.get("title", "Unknown")
            if vid and idx:
                # Extract artist from uploader/channel field
                artist = d.get("uploader", d.get("channel", "Unknown"))
                # Strip trailing " - Topic" from YouTube auto-generated channels
                if artist.endswith(" - Topic"):
                    artist = artist[:-8]
                # Extract upload year from YYYYMMDD format
                upload_date = d.get("upload_date", "")
                upload_year = upload_date[:4] if len(upload_date) >= 4 else ""
                desc = d.get("description", "")

                remote_songs.append(
                    RemoteSong(
                        id=vid,
                        track=int(idx),
                        title=title,
                        artist=artist,
                        upload_year=upload_year,
                        description=desc,
                    )
                )
        except Exception:
            continue

    # ── Deduplicate by video ID (keep first occurrence) ────────
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
            console.log(f"[dim]  - Track {d.track}: {d.title} [{d.id}][/dim]")
        remote_songs = unique_songs

    # ── Squash track numbers (always consecutive from 1) ────────
    for i, song in enumerate(remote_songs):
        song.track = i + 1

    vid_to_title: dict[str, str] = {s.id: s.title for s in remote_songs}
    console.log(f"[green]Playlist:[/green] {album_name} ({len(remote_songs)} songs)")

    # ── Load old index ─────────────────────────────────────────
    old_hashes: dict[str, str] = {}
    old_counts: dict[str, int] = {}
    index_path = work_dir / INDEX_FILE

    if index_path.exists():
        try:
            with open(index_path) as f:
                for s in json.load(f).get("songs", []):
                    if "id" in s:
                        old_hashes[s["id"]] = s.get("sb_hash", "")
                        old_counts[s["id"]] = s.get("sb_count", 0)
        except Exception:
            pass

    # ── Clean duplicates and orphans ───────────────────────────
    remote_ids = {s.id for s in remote_songs}
    local_map = scan_and_clean(work_dir, remote_ids)

    # ── Identify missing ───────────────────────────────────────
    missing = [s for s in remote_songs if s.id not in local_map]
    console.log(f"[dim]Local: {len(local_map)} | Missing: {len(missing)}[/dim]")

    # ── Phase 1: Download ──────────────────────────────────────
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
                            f"[red]Failed:[/red] {song.title}\n  [dim]{last}[/dim]"
                        )
                    p.advance(task)

        local_map = scan_and_clean(work_dir, remote_ids)

    # ── Phase 2: Thumbnails ────────────────────────────────────
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

    # ── Phase 3: Metadata (ALL files, not just new) ────────────
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

    # ── Phase 4: Rename ────────────────────────────────────────
    local_map = enforce_names(remote_songs, local_map, work_dir)

    # ── Phase 5: SponsorBlock ──────────────────────────────────
    vids_need_sb = list(local_map.keys())
    vids_use_cache = []

    console.log(
        f"[dim]SponsorBlock: fetching {len(vids_need_sb)}, "
        f"using cache for {len(vids_use_cache)}[/dim]"
    )

    new_hashes: dict[str, str] = {}
    new_counts: dict[str, int] = {}
    sb_changed: list[str] = []

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
                        console.log(f"[red]SB error[/red]  {title} [dim]({err_msg})[/dim]")
                        new_hashes[vid] = old_hashes.get(vid, "error")
                        new_counts[vid] = old_counts.get(vid, 0)

                    elif h == "no_segments":
                        console.log(f"[dim]SB none   {title}[/dim]")
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

                        console.log(f"[cyan]SB ok[/cyan] {diff_str}  {title}")
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

    # ── Phase 6: Re-download SB-changed ───────────────────────
    if sb_changed:
        console.log(
            f"[yellow]Re-downloading {len(sb_changed)} SB-changed songs...[/yellow]"
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

        local_map = scan_and_clean(work_dir, remote_ids)
        local_map = enforce_names(remote_songs, local_map, work_dir)

    # ── Phase 7: Save index ────────────────────────────────────
    final_songs = []
    for s in remote_songs:
        if s.id in local_map:
            final_songs.append(
                {
                    "id": s.id,
                    "track": s.track,
                    "artist": s.artist,
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
        f"[bold green]Sync complete![/bold green] {len(final_songs)} songs indexed."
    )


# ============================================================
# Entry
# ============================================================

if __name__ == "__main__":
    if len(sys.argv) < 2:
        cwd = Path.cwd().name
        url = DIR_ALIASES.get(cwd)
        if not url:
            console.print("[red]Usage:[/red] ./yt.py [url|alias]")
            sys.exit(1)
        console.log(f"[dim]Auto-detected: {cwd}[/dim]")
    else:
        arg = sys.argv[1]
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
        sync(url)
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted.[/yellow]")
        cleanup(Path.cwd())
        sys.exit(130)
