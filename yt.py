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
from mutagen.mp4 import MP4
from rich.console import Console
from rich.progress import (BarColumn, MofNCompleteColumn, Progress,
                           SpinnerColumn, TaskProgressColumn, TextColumn,
                           TimeRemainingColumn)

# ============================================================
# Config
# ============================================================

PARALLEL_DOWNLOADS = 4
SB_CONCURRENCY = 4
SB_API_DELAY = 0.2
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

ID_RE = re.compile(r"\[([a-zA-Z0-9_-]{11})\]\.[a-z0-9]+$")
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


def clean_orphans(work_dir: Path, remote_ids: set[str]) -> int:
    """Remove .m4a files without video ID or not in remote playlist."""
    removed = 0
    for f in work_dir.glob("*.m4a"):
        if ".temp." in f.name or ".part" in f.name:
            continue
        vid = extract_id(f.name)
        if not vid or vid not in remote_ids:
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


def do_metadata(path: Path, track: int, album: str) -> bool:
    try:
        audio = MP4(path)
        if audio.tags is None:
            audio.add_tags()
        audio.tags["trkn"] = [(track, 0)]
        audio.tags["\xa9alb"] = album
        audio.tags["aART"] = "olivertzeng"
        audio.save()
        return True
    except Exception:
        return False


def do_sb(vid: str) -> tuple[str, str, int]:
    """Returns (vid, hash_or_status, segment_count)."""
    cats = '["sponsor","selfpromo","interaction","intro","outro","preview","music_offtopic","filler"]'
    url = f"https://sponsor.ajay.app/api/skipSegments?videoID={vid}&categories={cats}"
    with sb_sem:
        time.sleep(SB_API_DELAY)
        try:
            r = requests.get(url, timeout=10)
            if r.status_code == 404:
                return vid, "no_segments", 0
            r.raise_for_status()
            data = r.json()
            if not data:
                return vid, "no_segments", 0
            norm = sorted(data, key=lambda x: x.get("segment", [0])[0])
            items = [{"segment": x["segment"], "category": x["category"]} for x in norm]
            h = hashlib.sha256(json.dumps(items, sort_keys=True).encode()).hexdigest()
            return vid, h, len(items)
        except Exception:
            return vid, "error", 0


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
                remote_songs.append(RemoteSong(id=vid, track=int(idx), title=title))
        except Exception:
            continue

    # ── Squash track numbers ───────────────────────────────────
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

    # ── Clean orphan files ─────────────────────────────────────
    remote_ids = {s.id for s in remote_songs}
    orphans = clean_orphans(work_dir, remote_ids)
    if orphans:
        console.log(f"[yellow]Removed {orphans} orphan files[/yellow]")

    # ── Identify missing ───────────────────────────────────────
    local_map = scan_dir(work_dir)
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

        local_map = scan_dir(work_dir)

    # ── Phase 2: Metadata ──────────────────────────────────────
    meta_tasks = [(local_map[s.id], s.track) for s in remote_songs if s.id in local_map]

    if meta_tasks:
        with make_progress() as p:
            task = p.add_task("Metadata", total=len(meta_tasks))
            with ThreadPoolExecutor(max_workers=PARALLEL_DOWNLOADS) as pool:
                futs = {
                    pool.submit(do_metadata, path, track, album_name): None
                    for path, track in meta_tasks
                }
                for _ in as_completed(futs):
                    p.advance(task)

    # ── Phase 3: Rename ────────────────────────────────────────
    local_map = enforce_names(remote_songs, local_map, work_dir)

    # ── Phase 4: SponsorBlock ──────────────────────────────────
    vids_need_sb = [
        vid for vid in local_map if vid in newly_downloaded or not old_hashes.get(vid)
    ]
    vids_use_cache = [
        vid for vid in local_map if vid not in newly_downloaded and old_hashes.get(vid)
    ]

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
                    vid, h, count = fut.result()
                    title = vid_to_title.get(vid, vid)

                    if h == "error":
                        console.log(f"[red]SB error[/red]  {title}")
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

    # ── Phase 5: Re-download SB-changed ───────────────────────
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

        local_map = scan_dir(work_dir)
        local_map = enforce_names(remote_songs, local_map, work_dir)

    # ── Phase 6: Save index ────────────────────────────────────
    final_songs = []
    for s in remote_songs:
        if s.id in local_map:
            final_songs.append(
                {
                    "id": s.id,
                    "track": s.track,
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
