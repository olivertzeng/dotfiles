#!/usr/bin/env python3
"""
yt.py - YouTube Playlist Downloader

Dependencies:
    sudo pacman -S python-rich python-requests python-mutagen yt-dlp ffmpeg

Options:
    -c, --check         Check existing songs for SponsorBlock changes, missing lyrics,
                        AND missing/corrupt thumbnails
    --check-sb          Check existing songs for SponsorBlock changes only
    --check-lyrics      Check existing songs for missing lyrics only
    --check-thumbnail   Check existing songs for missing/corrupt thumbnails only
    --wipe-lyrics       Delete all .lrc files and embedded lyrics, then re-fetch for all songs
    --wipe-thumbnail    Strip all embedded thumbnails and re-embed for all songs
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

# Subtitle languages to fetch, ordered by preference for selection scoring
LYRIC_SUB_LANGS = "en,en-orig,ja,zh-Hant,zh-TW,zh-Hans,zh-CN,zh"
LYRIC_LANG_PREF = ["en", "zh-hant", "zh-tw", "ja", "zh-hans", "zh-cn", "zh"]

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
    """Soft-delete: move a file (and its .lrc) to .trash/ and record ID."""
    trash_dir.mkdir(parents=True, exist_ok=True)
    shutil.move(str(file_path), str(trash_dir / file_path.name))

    lrc_path = file_path.with_suffix(".lrc")
    if lrc_path.exists():
        shutil.move(str(lrc_path), str(trash_dir / lrc_path.name))

    vid = extract_id(file_path.name)
    if vid:
        manifest = _load_trash_manifest(trash_dir)
        manifest.add(vid)
        _save_trash_manifest(trash_dir, manifest)


def detect_restored(work_dir: Path, trash_dir: Path, remote_ids: set[str]) -> None:
    """Auto-detect files restored from .trash/ back to an album folder.

    If a file in work_dir has an ID recorded in the trash manifest AND
    that ID is not in the current remote playlist, the user must have
    manually restored it -> auto-add to .keep so it won't be trashed again.
    """
    manifest = _load_trash_manifest(trash_dir)
    if not manifest:
        return

    updated = set(manifest)

    for vid in list(manifest):
        if vid in remote_ids:
            updated.discard(vid)
            continue

        matches = [f for f in work_dir.glob("*.m4a") if f"[{vid}]" in f.name]
        if matches:
            title = matches[0].stem.split(f" [{vid}]")[0]
            console.print(
                f"  [cyan]♻ Restored from trash: {matches[0].name} "
                f"→ auto-adding to .keep[/cyan]"
            )
            add_to_keep(work_dir, vid, title)
            updated.discard(vid)
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


def _unlink_with_lrc(path: Path) -> None:
    """Hard-delete an m4a file and its associated .lrc sidecar."""
    path.unlink()
    lrc = path.with_suffix(".lrc")
    if lrc.exists():
        lrc.unlink()


def scan_and_clean(
    work_dir: Path,
    remote_ids: set[str],
    keep_ids: set[str] | None = None,
    trash_dir: Path | None = None,
) -> dict[str, Path]:
    """Scan work_dir for .m4a files; trash orphans/duplicates, return valid map."""
    if keep_ids is None:
        keep_ids = set()

    id_to_files: dict[str, list[Path]] = {}
    no_id_files: list[Path] = []

    for f in work_dir.glob("*.m4a"):
        if ".temp." in f.name or ".part" in f.name:
            continue
        vid = extract_id(f.name)
        if vid:
            id_to_files.setdefault(vid, []).append(f)
        else:
            no_id_files.append(f)

    result: dict[str, Path] = {}
    removed = 0

    def _trash(f: Path) -> bool:
        nonlocal removed
        try:
            if trash_dir:
                move_to_trash(f, trash_dir)
            else:
                _unlink_with_lrc(f)
            removed += 1
            return True
        except OSError:
            return False

    for f in no_id_files:
        console.log(f"[yellow]No ID, trashing:[/yellow] {f.name}")
        _trash(f)

    for vid, files in id_to_files.items():
        if vid not in remote_ids:
            if vid in keep_ids:
                console.log(f"[green]⛔ Protected by .keep:[/green] {files[0].name}")
                continue
            for f in files:
                console.log(f"[yellow]Not in playlist, trashing:[/yellow] {f.name}")
                _trash(f)
        elif len(files) == 1:
            result[vid] = files[0]
        else:
            files.sort()
            result[vid] = files[0]
            for f in files[1:]:
                console.log(f"[yellow]Duplicate ID {vid}, trashing:[/yellow] {f.name}")
                _trash(f)

    if removed:
        console.log(f"[yellow]Cleaned {removed} file(s) → .trash/[/yellow]")

    return result


TEMP_EXTS: frozenset[str] = frozenset(
    {".temp.m4a", ".part", ".ytdl", ".f140.m4a", ".f251.webm", ".f140.webm"}
)
ART_EXTS: frozenset[str] = frozenset({".jpg", ".jpeg", ".webp", ".png"})
KILL_EXTS = TEMP_EXTS | ART_EXTS

# Filenames that must never be deleted (album covers, folder art, etc.)
# Case-insensitive matching is applied in cleanup()
PROTECTED_IMAGES: frozenset[str] = frozenset({
    "cover.png",
    "cover.jpg",
})

KILL_EXTS = TEMP_EXTS | ART_EXTS

def cleanup(work_dir: Path, vid: str | None = None) -> int:
    """Remove temp/art files (hard delete — these are build artifacts)."""
    removed = 0
    targets = work_dir.glob(f"*{vid}*") if vid else work_dir.iterdir()
    for f in targets:
        if not f.is_file():
            continue
        # Protect files starting with "cover." (original rule)
        if f.name.startswith("cover."):
            continue
        # Protect explicitly named album covers (case-insensitive)
        if f.name.lower() in PROTECTED_IMAGES:
            continue
        if any(f.name.endswith(e) for e in KILL_EXTS):
            try:
                f.unlink()
                removed += 1
            except OSError:
                pass
    return removed


def cleanup_subtitle_temps(work_dir: Path) -> int:
    """Remove leftover .temp_subs_* files from interrupted lyrics fetches."""
    removed = 0
    for f in work_dir.glob(".temp_subs_*"):
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
# Lyrics
# ============================================================
def has_lyrics(path: Path) -> bool:
    """Check if an m4a has lyrics via external .lrc sidecar or embedded tag."""
    if path.with_suffix(".lrc").exists():
        return True
    try:
        audio = MP4(path)
        tags = audio.tags or {}
        lyr = tags.get("\xa9lyr", [])
        return bool(lyr and lyr[0].strip())
    except Exception:
        return False


def _lyric_lang_score(path: Path) -> int:
    """Score a subtitle file by language preference (lower = better)."""
    name = path.name.lower()
    for i, pref in enumerate(LYRIC_LANG_PREF):
        if f".{pref}." in name or f".{pref}-" in name:
            return i
    return 999


def clean_and_convert_lyrics(content: str) -> str | None:
    """Convert WEBVTT to standard LRC format if needed.

    Since we only fetch manually uploaded subtitles, heavy garbage
    detection is unnecessary. We still do basic validation (reject
    empty or text-free content) and convert WEBVTT → LRC so that
    music players like Feishin/Substreamer can display synced lyrics.
    """
    content = content.strip()
    if not content:
        return None

    # --- WEBVTT → LRC conversion ---
    if "WEBVTT" in content:
        lines = content.splitlines()
        lrc_lines: list[str] = []
        time_pat = re.compile(r"(?:(\d{2,}):)?(\d{2}):(\d{2})\.(\d{3})\s*-->")

        i = 0
        while i < len(lines):
            line = lines[i].strip()
            match = time_pat.search(line)
            if match:
                hrs = int(match.group(1) or "0")
                mins = int(match.group(2))
                secs = match.group(3)
                ms = match.group(4)

                # Fold hours into minutes (LRC uses [mm:ss.xx])
                total_mins = mins + hrs * 60
                lrc_time = f"[{total_mins:02d}:{secs}.{ms[:2]}]"

                # Collect subtitle text until next timestamp or blank line
                text_parts: list[str] = []
                i += 1
                while (
                    i < len(lines)
                    and lines[i].strip()
                    and not time_pat.search(lines[i])
                ):
                    clean_line = re.sub(r"<[^>]+>", "", lines[i]).strip()
                    if clean_line:
                        text_parts.append(clean_line)
                    i += 1

                lyric_text = " ".join(text_parts)
                if lyric_text:
                    lrc_lines.append(f"{lrc_time} {lyric_text}")
                continue
            i += 1

        if not lrc_lines:
            return None
        return "\n".join(lrc_lines)

    # Already LRC — strip stray HTML/VTT tags
    cleaned = re.sub(r"<[^>]+>", "", content)

    # Basic validation: ensure there is at least some actual text
    text_only = re.sub(r"\[\d{2}:\d{2}\.\d{2,3}\]", "", cleaned)
    text_only = re.sub(r"\[.*?\]", "", text_only).strip()
    if not text_only:
        return None

    return cleaned


def fetch_lrclib(song: RemoteSong) -> str | None:
    """Fetch synced lyrics from LRCLIB as a fallback when YouTube has no manual subtitles.

    LRCLIB is a free, open, community-sourced lyrics database with no API key required.
    We only use synced lyrics (syncedLyrics field) — plain lyrics without timestamps
    are not useful for music players like Feishin/Substreamer.

    Returns a valid LRC string, or None if not found / only plain lyrics available.
    """
    if not song.artist or not song.title:
        return None

    # Strip common YouTube title suffixes that would confuse LRCLIB matching
    # e.g. "(Official MV)", "[1080p]", "feat. XXX" are usually not in the DB
    clean_title = re.sub(
        r"\s*[\(\[].*?[\)\]]"  # remove anything in () or []
        r"|\s*feat\..*$"       # remove feat. and everything after
        r"|\s*ft\..*$",        # remove ft. and everything after
        "",
        song.title,
        flags=re.IGNORECASE,
    ).strip()

    params = {
        "track_name": clean_title,
        "artist_name": song.artist,
    }

    try:
        r = requests.get(
            "https://lrclib.net/api/get",
            params=params,
            headers={"User-Agent": "yt-playlist-downloader/1.0 (github.com/olivertzeng)"},
            timeout=10,
        )
        if r.status_code == 404:
            return None
        r.raise_for_status()

        data = r.json()

        # Prefer synced lyrics (has timestamps) — plain lyrics are not useful here
        synced = data.get("syncedLyrics", "")
        if synced and synced.strip():
            return synced.strip()

        return None

    except Exception:
        return None


def do_lyrics(song: RemoteSong, m4a_path: Path, work_dir: Path) -> tuple[bool, str]:
    """Fetch lyrics with a two-tier strategy.

    Tier 1 — YouTube manual subtitles:
        Highest accuracy, guaranteed to be in sync with this exact video.
        Auto-generated subtitles are intentionally skipped (ASR garbage for music).

    Tier 2 — LRCLIB fallback:
        Used only when YouTube has no manual subtitles.
        Matched against the official release, so the LRC timestamps may be
        slightly out of sync with MV versions (intro/outro length differences).
        A '[by:lrclib]' tag is prepended so you can identify these and adjust
        the offset in Feishin if needed.

    Returns (success, source) where source is 'youtube', 'lrclib', or ''.
    """
    temp_prefix = work_dir / f".temp_subs_{song.id}"
    url = f"https://www.youtube.com/watch?v={song.id}"

    # --- Tier 1: YouTube manual subtitles ---
    run(
        [
            "yt-dlp",
            "--skip-download",
            "--write-subs",
            # NOTE: --write-auto-subs intentionally omitted (ASR garbage for music)
            "--sub-langs",
            LYRIC_SUB_LANGS,
            "--convert-subs",
            "lrc",
            "-o",
            str(temp_prefix),
            url,
        ],
        timeout=45,
    )

    subs = sorted(work_dir.glob(f".temp_subs_{song.id}*.lrc"), key=_lyric_lang_score)
    content: str | None = None
    source = ""

    if subs:
        for sub_file in subs:
            try:
                raw = sub_file.read_text(encoding="utf-8").strip()
                converted = clean_and_convert_lyrics(raw)
                if converted:
                    content = converted
                    source = "youtube"
                    break
            except Exception:
                continue

    # --- Tier 2: LRCLIB fallback ---
    if not source:
        lrclib_result = fetch_lrclib(song)
        if lrclib_result:
            # Prepend a tag so the source is identifiable later
            content = f"[by:lrclib]\n{lrclib_result}"
            source = "lrclib"

    # --- Write to disk if we got anything ---
    success = False
    if content and source:
        try:
            audio = MP4(m4a_path)
            if audio.tags is None:
                audio.add_tags()
            audio.tags["\xa9lyr"] = content
            audio.save()

            # Write external .lrc sidecar for Navidrome synced lyrics
            m4a_path.with_suffix(".lrc").write_text(content, encoding="utf-8")
            success = True
        except Exception:
            success = False

    # Cleanup all temp subtitle files for this song
    for f in work_dir.glob(f".temp_subs_{song.id}*"):
        f.unlink(missing_ok=True)

    return success, source


def wipe_all_lyrics(work_dir: Path) -> None:
    """Delete all .lrc sidecar files and remove embedded lyrics from all .m4a files."""
    lrc_count = 0
    for lrc_file in work_dir.glob("*.lrc"):
        lrc_file.unlink()
        lrc_count += 1
    console.print(f"  Deleted {lrc_count} .lrc file(s)")

    m4a_count = 0
    for m4a_file in work_dir.glob("*.m4a"):
        try:
            audio = MP4(m4a_file)
            if audio.tags and "\xa9lyr" in audio.tags:
                del audio.tags["\xa9lyr"]
                audio.save()
                m4a_count += 1
        except Exception:
            pass
    console.print(f"  Cleared embedded lyrics from {m4a_count} .m4a file(s)")
    console.print("[green]Lyrics wiped. They will be re-fetched during sync.[/green]")

def wipe_all_thumbnails(work_dir: Path) -> None:
    """Strip all embedded thumbnails from all .m4a files so they are re-embedded on next sync."""
    wiped = 0
    for m4a_file in work_dir.glob("*.m4a"):
        try:
            audio = MP4(m4a_file)
            if audio.tags and "covr" in audio.tags:
                del audio.tags["covr"]
                audio.save()
                wiped += 1
        except Exception:
            pass
    console.print(f"  Stripped thumbnails from {wiped} .m4a file(s)")
    console.print("[green]Thumbnails wiped. They will be re-embedded during sync.[/green]")

# ============================================================
# Metadata Extraction
# ============================================================
def _apply_info_dict(song: RemoteSong, d: dict) -> RemoteSong:
    """Apply metadata fields from a yt-dlp info dict to a RemoteSong."""
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

    return song


def _read_info_json(song: RemoteSong, work_dir: Path) -> RemoteSong:
    """Read .info.json written by yt-dlp, update song fields, delete the file."""
    for f in work_dir.glob("*.info.json"):
        if f"[{song.id}]" not in f.name:
            continue
        try:
            with open(f) as fh:
                song = _apply_info_dict(song, json.loads(fh.read()))
        except Exception:
            pass
        finally:
            f.unlink(missing_ok=True)
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
            song = _apply_info_dict(song, json.loads(line))
        except json.JSONDecodeError:
            continue
        break
    return song


# ============================================================
# Tasks
# ============================================================
def do_download(
    song: RemoteSong, album: str, work_dir: Path
) -> tuple[RemoteSong, bool, str]:
    base_url = f"https://www.youtube.com/watch?v={song.id}"
    urls = [base_url, f"https://web.archive.org/web/{base_url}"]

    cmd_base = [
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
    ]

    for url in urls:
        ok, out = run(cmd_base + [url])
        if ok:
            song = _read_info_json(song, work_dir)
        cleanup(work_dir, song.id)
        if ok:
            existing = [f for f in work_dir.glob("*.m4a") if f"[{song.id}]" in f.name]
            if existing:
                return song, True, ""
            return song, False, "File not found after download"

    return song, False, out


def do_metadata(
    path: Path,
    song: RemoteSong,
    album: str,
    album_year: str,
) -> bool:
    """Write metadata tags to an m4a file.

    The comment field is set to the YouTube video URL for easy reference.
    """
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
        audio.tags["\xa9cmt"] = f"https://www.youtube.com/watch?v={song.id}"

        audio.save()
        return True
    except Exception:
        return False


def do_sb(vid: str) -> tuple[str, str, int, str]:
    cats = (
        '["sponsor","selfpromo","interaction","intro","outro",'
        '"preview","music_offtopic","filler"]'
    )
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
        safe = re.sub(r'[\\/*?:"<>|]', "", song.title or "Unknown")
        new_name = f"{song.track:03d} - {safe} [{song.id}].m4a"
        new_path = work_dir / new_name
        if old_path == new_path:
            continue
        try:
            old_path.rename(new_path)
            old_lrc = old_path.with_suffix(".lrc")
            if old_lrc.exists():
                old_lrc.rename(new_path.with_suffix(".lrc"))
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
def sync(url: str, check_sb: bool = False, check_lyrics: bool = False, check_thumbnail: bool = False) -> None:
    work_dir = Path.cwd()
    trash_dir = work_dir.parent / ".trash"

    removed = cleanup(work_dir)
    if removed:
        console.log(f"[dim]Cleaned {removed} temp files[/dim]")
    removed = cleanup_subtitle_temps(work_dir)
    if removed:
        console.log(f"[dim]Cleaned {removed} leftover subtitle temps[/dim]")

    album_year = PLAYLIST_YEAR.get(url, str(datetime.now().year))

    # -- Fetch playlist (structure only) --
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

    # -- Deduplicate --
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

    # -- Squash track numbers --
    for i, song in enumerate(remote_songs):
        song.track = i + 1

    vid_to_title: dict[str, str] = {s.id: s.title for s in remote_songs}
    console.log(f"[green]Playlist:[/green] {album_name} ({len(remote_songs)} songs)")

    # -- Load old index (cache + SB hashes) --
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

    # -- Backfill metadata from cached index --
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

    # -- Detect files restored from .trash/ --
    remote_ids = {s.id for s in remote_songs}
    detect_restored(work_dir, trash_dir, remote_ids)

    # -- Load .keep whitelist --
    keep_ids = load_keep(work_dir)
    if keep_ids:
        console.log(f"[dim].keep whitelist: {len(keep_ids)} IDs[/dim]")

    # -- Clean duplicates and orphans --
    local_map = scan_and_clean(work_dir, remote_ids, keep_ids, trash_dir)

    # -- Identify missing --
    missing = [s for s in remote_songs if s.id not in local_map]
    console.log(f"[dim]Local: {len(local_map)} | Missing: {len(missing)}[/dim]")

    # Initialize before Phase 3
    sb_changed: list[str] = []
    sb_changed_set: set[str] = set()
    # -- Phase 1: Download --
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
                            f"[red]Failed:[/red] {song.title}\n [dim]{last}[/dim]"
                        )
                    p.advance(task)

        local_map = scan_and_clean(work_dir, remote_ids, keep_ids, trash_dir)

    # -- Phase 2: Fetch metadata for songs missing artist --
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
                            f"[green]Got artist:[/green] {song.title} → {song.artist}"
                        )
                    else:
                        console.log(f"[dim]No artist: {song.title}[/dim]")
                    p.advance(task)

    # -- Phase 3: Thumbnails (newly downloaded songs) --
    thumb_tasks: list[tuple[Path, str]] = []
    for song in remote_songs:
        if song.id not in local_map:
            continue
        is_new = song.id in newly_downloaded
        if not is_new and not check_thumbnail:
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

    # -- Phase 4: Metadata (ALL files) --
    meta_songs = [s for s in remote_songs if s.id in local_map]

    if meta_songs:
        with make_progress() as p:
            task = p.add_task("Metadata", total=len(meta_songs))
            with ThreadPoolExecutor(max_workers=PARALLEL_DOWNLOADS) as pool:
                futs = {
                    pool.submit(
                        do_metadata, local_map[s.id], s, album_name, album_year
                    ): None
                    for s in meta_songs
                }
                for _ in as_completed(futs):
                    p.advance(task)

    # -- Phase 5: Rename --
    local_map = enforce_names(remote_songs, local_map, work_dir)

    # -- Phase 6: SponsorBlock --
    # New songs: always check. Existing songs: only with --check-sb or -c.
    if check_sb:
        vids_check_sb = list(local_map.keys())
    else:
        vids_check_sb = [vid for vid in local_map if vid in newly_downloaded]

    new_hashes: dict[str, str] = {}
    new_counts: dict[str, int] = {}
    sb_changed: list[str] = []
    sb_changed_set = set(sb_changed)
    always_check = newly_downloaded | sb_changed_set
    # Carry forward old data for songs not being checked
    for vid in local_map:
        if vid not in vids_check_sb:
            new_hashes[vid] = old_hashes.get(vid, "")
            new_counts[vid] = old_counts.get(vid, 0)

    if vids_check_sb:
        console.log(f"[dim]SponsorBlock: checking {len(vids_check_sb)} songs[/dim]")
        with make_progress() as p:
            task = p.add_task("SponsorBlock", total=len(vids_check_sb))
            with ThreadPoolExecutor(max_workers=SB_CONCURRENCY) as pool:
                futures = {pool.submit(do_sb, vid): vid for vid in vids_check_sb}
                for fut in as_completed(futures):
                    vid, h, count, err_msg = fut.result()
                    title = vid_to_title.get(vid, vid)

                    if h == "error":
                        console.log(
                            f"[red]SB error[/red] {title} [dim]({err_msg})[/dim]"
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
    else:
        console.log("[dim]SponsorBlock: nothing to check[/dim]")

    # -- Phase 7: Re-download SB-changed --
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

        local_map = scan_and_clean(work_dir, remote_ids, keep_ids, trash_dir)
        local_map = enforce_names(remote_songs, local_map, work_dir)
    # -- Phase 7b: Re-embed thumbnails for SB-redownloaded songs --
    # These songs went through do_download() again (--no-embed-thumbnail),
    # so their thumbnails were stripped and need to be re-fetched.
    sb_thumb_tasks = [
        (local_map[vid], vid)
        for vid in sb_changed_set
        if vid in local_map and not has_thumbnail(local_map[vid])
    ]

    if sb_thumb_tasks:
        console.log(
            f"[cyan]Re-embedding thumbnails for {len(sb_thumb_tasks)} "
            f"SB-redownloaded songs...[/cyan]"
        )
        with make_progress() as p:
            task = p.add_task("Thumbnails (SB)", total=len(sb_thumb_tasks))
            for path, vid in sb_thumb_tasks:
                thumb = fetch_thumbnail(vid, work_dir)
                if thumb:
                    if embed_thumbnail(path, thumb):
                        console.log(f"[green]Thumbnail (SB):[/green] {path.name}")
                    else:
                        console.log(f"[red]Embed failed:[/red] {path.name}")
                    thumb.unlink(missing_ok=True)
                else:
                    console.log(f"[dim]No thumbnail: {vid}[/dim]")
                p.advance(task)
    # -- Phase 8: Lyrics --
    # Placed after SB re-download so re-downloaded files also get lyrics.
    # New songs: always. Existing songs: only with --check-lyrics or -c.

    if check_lyrics:
        lyric_candidates = [s for s in remote_songs if s.id in local_map]
    else:
        lyric_candidates = [
            s for s in remote_songs if s.id in local_map and s.id in always_check
        ]

    vids_need_lyrics = [
        (s, local_map[s.id])
        for s in lyric_candidates
        if not has_lyrics(local_map[s.id])
    ]

    if vids_need_lyrics:
        console.log(
            f"[cyan]Fetching lyrics for {len(vids_need_lyrics)} songs...[/cyan]"
        )
        with make_progress() as p:
            task = p.add_task("Lyrics", total=len(vids_need_lyrics))
            with ThreadPoolExecutor(max_workers=PARALLEL_DOWNLOADS) as pool:
                futs = {
                    pool.submit(do_lyrics, s, path, work_dir): s
                    for s, path in vids_need_lyrics
                }
                for fut in as_completed(futs):
                    song = futs[fut]
                    ok, source = fut.result()
                    if ok:
                        if source == "lrclib":
                            console.log(f"[green]Lyrics (lrclib):[/green] {song.title}")
                        else:
                            console.log(f"[green]Lyrics (youtube):[/green] {song.title}")
                    else:
                        console.log(f"[dim]No lyrics: {song.title}[/dim]")
                    p.advance(task)
    else:
        console.log("[dim]Lyrics: nothing to fetch[/dim]")

    # -- Phase 9: Save index --
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
        f"[bold green]Sync complete![/bold green] {len(final_songs)} songs indexed."
    )


# ============================================================
# Entry
# ============================================================
if __name__ == "__main__":
    args = sys.argv[1:]
    check_sb = False
    check_lyrics = False
    check_thumbnail = False
    wipe_lyrics = False
    wipe_thumbnail = False

    # -c / --check is a shorthand for --check-sb, --check-lyrics, AND --check-thumbnail
    for flag in ("-c", "--check"):
        if flag in args:
            check_sb = True
            check_lyrics = True
            check_thumbnail = True
            args.remove(flag)

    if "--check-sb" in args:
        check_sb = True
        args.remove("--check-sb")

    if "--check-lyrics" in args:
        check_lyrics = True
        args.remove("--check-lyrics")

    if "--check-thumbnail" in args:
        check_thumbnail = True
        args.remove("--check-thumbnail")

    if "--wipe-lyrics" in args:
        wipe_lyrics = True
        args.remove("--wipe-lyrics")

    if "--wipe-thumbnail" in args:
        wipe_thumbnail = True
        args.remove("--wipe-thumbnail")

    if len(args) == 0:
        cwd = Path.cwd().name
        url = DIR_ALIASES.get(cwd)
        if not url:
            console.print(
                "[red]Usage:[/red] ./yt.py [-c|--check] [--check-sb] "
                "[--check-lyrics] [--wipe-lyrics] [url|alias]"
            )
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

    if wipe_lyrics:
        console.log("[yellow]Wiping all lyrics...[/yellow]")
        wipe_all_lyrics(Path.cwd())
        check_lyrics = True

    if wipe_thumbnail:                                      # NEW
        console.log("[yellow]Wiping all thumbnails...[/yellow]")
        wipe_all_thumbnails(Path.cwd())
        check_thumbnail = True                              # force re-embed on sync

    try:
        sync(url, check_sb=check_sb, check_lyrics=check_lyrics, check_thumbnail=check_thumbnail)
    except KeyboardInterrupt:
        console.print("\n[yellow]Interrupted.[/yellow]")
        cleanup(Path.cwd())
        cleanup_subtitle_temps(Path.cwd())
        sys.exit(130)
