import os
import sys
import re
import time
import socket
import hashlib
import tempfile
import stat as stat_mod
import json
import heapq
import configparser
import mimetypes
import subprocess
import shutil
from urllib.parse import unquote
from datetime import datetime
from pathlib import Path
from PySide6.QtCore import QObject, Slot, Property, Signal, QRunnable, QThreadPool, QFileSystemWatcher, QTimer, QUrl, Qt
from PySide6.QtGui import QGuiApplication, QDrag, QPixmap, QPainter, QColor, QFont
from PySide6.QtCore import QMimeData
from core.models import FileListModel, MediaHubSectionModel
from core.config import ConfigManager
from core.thumbnails import ThumbnailManager, IMAGE_EXTS, VIDEO_EXTS

SUBTITLE_EXTS = {".srt", ".ass", ".ssa", ".sub", ".vtt", ".idx", ".sup", ".smi"}
FONT_EXTS = {".ttf", ".otf", ".woff", ".woff2", ".ttc"}
ARCHIVE_EXTS = {".zip", ".tar", ".gz", ".tgz", ".bz2", ".tbz2", ".xz", ".txz", ".7z", ".rar"}
from core.search import SearchManager
from core.picker_context import PickerContext
from core.portal_service import SystemIntegrationBridge, install_desktop_and_set_default, is_default_file_manager
from core.jellyfin_bridge import JellyfinBridge, JellyfinSignals, JellyfinFolderSyncTask, post_jellyfin_playback_event
from core.airing_tracker import AiringTracker

import pwd
import grp

EXECUTABLE_EXTS = {".appimage", ".sh", ".bin", ".run", ".out", ".py"}

PROTECTED_SYSTEM_PATHS = {
    "/", "/bin", "/boot", "/dev", "/etc", "/home", "/lib", "/lib64",
    "/mnt", "/opt", "/proc", "/root", "/run", "/sbin", "/srv", "/sys",
    "/tmp", "/usr", "/var", str(Path.home())
}


def find_matching_external_subs_for_video(video_file_path: str) -> list:
    """
    Scans the video file's directory (and Subs/Subtitles subfolders) for external subtitle files
    matching the original video filename stem so MPV always loads them regardless of Jellyfin titles.
    """
    if not video_file_path or not os.path.isfile(video_file_path):
        return []
    vp = Path(video_file_path)
    parent = vp.parent
    stem = vp.stem
    stem_low = stem.lower()
    matched = []
    seen = set()

    search_dirs = [parent]
    for sd_name in ("Subs", "subs", "Subtitles", "subtitles", stem):
        sd = parent / sd_name
        if sd.is_dir():
            search_dirs.append(sd)

    for sdir in search_dirs:
        try:
            with os.scandir(str(sdir)) as it:
                for entry in it:
                    if not entry.is_file():
                        continue
                    sp = Path(entry.name)
                    if sp.suffix.lower() not in SUBTITLE_EXTS:
                        continue
                    sub_stem_low = sp.stem.lower()
                    if (
                        sub_stem_low == stem_low
                        or sub_stem_low.startswith(stem_low + ".")
                        or sub_stem_low.startswith(stem_low + "_")
                        or sub_stem_low.startswith(stem_low + "-")
                        or sub_stem_low.startswith(stem_low + " ")
                    ):
                        abs_sub = os.path.abspath(entry.path)
                        if abs_sub not in seen:
                            seen.add(abs_sub)
                            matched.append(abs_sub)
        except OSError:
            pass

    def _sub_prio(p_str: str):
        nl = Path(p_str).stem.lower()
        is_ar = any(x in nl for x in (".ar", "_ar", "-ar", "arabic", "ara"))
        is_ass = p_str.lower().endswith((".ass", ".ssa"))
        return (0 if is_ar else 1, 0 if is_ass else 1, p_str)

    matched.sort(key=_sub_prio)
    return matched


def _get_secure_runtime_dir() -> Path:
    xdg_run = os.environ.get("XDG_RUNTIME_DIR", "")
    if xdg_run and os.path.isdir(xdg_run):
        rt = Path(xdg_run) / "find"
    else:
        rt = Path("/tmp") / f"find_runtime_{os.getuid()}"
    rt.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(rt, 0o700)
    except OSError:
        pass
    return rt


def _is_safe_extract_path(dest_dir: Path, member_name: str) -> bool:
    if not member_name:
        return False
    base_real = os.path.realpath(str(dest_dir))
    target_real = os.path.realpath(os.path.join(base_real, member_name))
    return target_real == base_real or target_real.startswith(base_real.rstrip(os.sep) + os.sep)


def _run_toggle_hdr_script(arg: str):
    """Executes toggle-hdr.sh with the given argument (--on, --off, --status)."""
    candidates = [
        shutil.which("toggle-hdr.sh"),
        str(Path.home() / ".local" / "bin" / "toggle-hdr.sh"),
    ]
    script_path = next((c for c in candidates if c and os.path.exists(c)), None)
    if not script_path:
        return
    try:
        subprocess.run(
            [script_path, arg],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=4
        )
    except Exception:
        pass


def detect_video_hdr_sync(file_path_str: str) -> bool:
    """
    Detects whether a video file contains HDR metadata (HDR10, HDR10+, Dolby Vision, PQ, HLG)
    primarily using `mediainfo --Output=JSON`, with fallback to `ffprobe`.
    """
    if shutil.which("mediainfo"):
        try:
            res = subprocess.run(
                ["mediainfo", "--Output=JSON", file_path_str],
                capture_output=True,
                text=True,
                timeout=2.5
            )
            if res.returncode == 0 and res.stdout:
                data = json.loads(res.stdout)
                tracks = data.get("media", {}).get("track", [])
                for t in tracks:
                    if t.get("@type") == "Video":
                        hdr_fmt = str(t.get("HDR_Format", "") or t.get("HDR_Format_Commercial", "") or "").upper()
                        transfer = str(t.get("transfer_characteristics", "") or t.get("transfer_characteristics_Original", "") or "").upper()
                        primaries = str(t.get("colour_primaries", "") or t.get("colour_primaries_Original", "") or "").upper()
                        if any(k in hdr_fmt for k in ("HDR", "DOLBY VISION", "SMPTE ST 2086", "SMPTE ST 2094", "SL-HDR")):
                            return True
                        if any(k in transfer for k in ("PQ", "SMPTE ST 2084", "HLG", "ARIB STD-B67")):
                            return True
                        if "BT.2020" in primaries and ("10" in str(t.get("BitDepth", "")) or "12" in str(t.get("BitDepth", ""))):
                            return True
                return False
        except Exception:
            pass

    if shutil.which("ffprobe"):
        try:
            res = subprocess.run(
                ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_streams", "-select_streams", "v:0", file_path_str],
                capture_output=True,
                text=True,
                timeout=2.0
            )
            if res.returncode == 0 and res.stdout:
                data = json.loads(res.stdout)
                for s in data.get("streams", []):
                    tr = str(s.get("color_transfer", "")).lower()
                    prim = str(s.get("color_primaries", "")).lower()
                    if tr in ("smpte2084", "arib-std-b67"):
                        return True
                    for sd in s.get("side_data_list", []):
                        sd_type = str(sd.get("side_data_type", "")).lower()
                        if "mastering display" in sd_type or "content light" in sd_type or "dovi" in sd_type or "dolby" in sd_type:
                            return True
                    if "bt2020" in prim and tr not in ("", "bt709", "unknown"):
                        return True
        except Exception:
            pass
    return False


class HdrBatchDetectorTask(QRunnable):
    def __init__(self, items_to_probe: list, config_mgr, signals):
        super().__init__()
        self.items_to_probe = items_to_probe
        self.config_mgr = config_mgr
        self.signals = signals

    def run(self):
        dirty = False
        for fpath, mtime in self.items_to_probe:
            try:
                is_hdr = detect_video_hdr_sync(fpath)
                self.config_mgr.set_cached_hdr(fpath, mtime, is_hdr, flush=False)
                dirty = True
                self.signals.hdrStatusDetected.emit(fpath, is_hdr)
            except Exception:
                pass
        if dirty:
            self.config_mgr.save_hdr_cache()


class IconGalleryScannerTask(QRunnable):
    """Recursively scans icon directories for SVG/PNG/ICO/WEBP files and streams them to the Icon Browser."""
    def __init__(self, root_dirs: list, search_filter: str, signals):
        super().__init__()
        self.root_dirs = root_dirs
        self.search_filter = search_filter.strip().lower()
        self.signals = signals

    def run(self):
        icons = []
        seen = set()
        valid_exts = {".svg", ".png", ".ico", ".webp"}
        max_icons = 600

        for base_dir in self.root_dirs:
            if not base_dir or not os.path.isdir(base_dir):
                continue
            for root, dirs, files in os.walk(base_dir):
                dirs[:] = [d for d in dirs if not d.startswith(".")]
                for f in files:
                    ext = os.path.splitext(f)[1].lower()
                    if ext not in valid_exts:
                        continue
                    if self.search_filter and self.search_filter not in f.lower():
                        continue
                    full_p = os.path.join(root, f)
                    if full_p in seen:
                        continue
                    seen.add(full_p)
                    icons.append({
                        "name": os.path.splitext(f)[0],
                        "filename": f,
                        "path": full_p
                    })
                    if len(icons) >= max_icons:
                        self.signals.iconGalleryReady.emit(icons)
                        return
        self.signals.iconGalleryReady.emit(icons)


class CallableTask(QRunnable):
    """Wraps any Python callable in a proper QRunnable with autoDelete so QThreadPool never drops or GCs it."""
    def __init__(self, fn, on_done=None):
        super().__init__()
        self.setAutoDelete(True)
        self.fn = fn
        self.on_done = on_done

    def run(self):
        try:
            self.fn()
        finally:
            if callable(self.on_done):
                self.on_done(self)


class AsyncWorkerSignals(QObject):
    directoryLoaded = Signal(str, list)
    directoryLoadError = Signal(str, str)
    # Use object instead of 32-bit C++ int so folders > 2GB never overflow into negative bytes!
    folderSizeReady = Signal(str, object)
    multiSelectionSizeReady = Signal(str, object, int, int)
    trashSizeReady = Signal(object, int)
    recentEntriesReady = Signal(list)
    mediaInfoReady = Signal(str, dict)
    mpvProgressUpdated = Signal(str, float, float, bool)
    mpvExternalSubDetected = Signal(str, str)
    mpvHdrSessionEnded = Signal(int)
    hdrStatusDetected = Signal(str, bool)
    externalPickerFinished = Signal(list)
    iconGalleryReady = Signal(list)
    archiveProgress = Signal(float, str)
    archiveFinished = Signal(bool, str)
    mediaHubSectionsReady = Signal(list)
    storageAnalyzerReady = Signal(str, list, object)
    requestRefresh = Signal()


class ArchiveTask(QRunnable):
    """Background multi-file/folder compressor with real-time progress reporting."""
    def __init__(self, target_paths: list, dest_archive_path: Path, archive_format: str, signals):
        super().__init__()
        self.target_paths = [Path(p) for p in target_paths if os.path.exists(p)]
        self.dest_archive_path = dest_archive_path
        self.archive_format = archive_format
        self.signals = signals

    def run(self):
        import zipfile
        import tarfile

        if not self.target_paths:
            self.signals.archiveFinished.emit(False, "No valid files selected to compress.")
            return

        try:
            file_items = []
            empty_dirs = []
            for root_item in self.target_paths:
                base_parent = root_item.parent
                if root_item.is_file() or root_item.is_symlink():
                    file_items.append((root_item, root_item.name))
                elif root_item.is_dir():
                    has_children = False
                    for r, dirs, files in os.walk(str(root_item)):
                        rel_dir = os.path.relpath(r, str(base_parent))
                        if not dirs and not files:
                            empty_dirs.append((Path(r), rel_dir))
                        for f in files:
                            has_children = True
                            fp = Path(r) / f
                            rel_arc = os.path.relpath(str(fp), str(base_parent))
                            file_items.append((fp, rel_arc))
                    if not has_children and not empty_dirs:
                        empty_dirs.append((root_item, root_item.name))

            total_items = max(1, len(file_items) + len(empty_dirs))
            processed = 0

            self.signals.archiveProgress.emit(0.02, f"Creating {self.dest_archive_path.name}...")

            if self.archive_format == "7z" and shutil.which("7z"):
                cmd = ["7z", "a", str(self.dest_archive_path)] + [str(p) for p in self.target_paths]
                self.signals.archiveProgress.emit(0.4, f"Compressing {self.dest_archive_path.name} (7z)...")
                res = subprocess.run(cmd, capture_output=True, text=True)
                if res.returncode != 0:
                    raise RuntimeError(res.stderr.strip() or "7z failed")
            elif self.archive_format == "zip":
                with zipfile.ZipFile(str(self.dest_archive_path), "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
                    for d_path, rel_arc in empty_dirs:
                        zf.writestr(rel_arc.rstrip("/") + "/", "")
                        processed += 1
                        self.signals.archiveProgress.emit(processed / total_items, f"Packing {rel_arc}")
                    for f_path, rel_arc in file_items:
                        if f_path.exists():
                            zf.write(str(f_path), arcname=rel_arc)
                        processed += 1
                        self.signals.archiveProgress.emit(processed / total_items, f"Compressing {f_path.name}")
            else:
                mode_str = "w:xz" if self.archive_format == "tar.xz" else "w:gz"
                with tarfile.open(str(self.dest_archive_path), mode_str) as tf:
                    for d_path, rel_arc in empty_dirs:
                        if d_path.exists():
                            tf.add(str(d_path), arcname=rel_arc, recursive=False)
                        processed += 1
                        self.signals.archiveProgress.emit(processed / total_items, f"Packing {rel_arc}")
                    for f_path, rel_arc in file_items:
                        if f_path.exists():
                            tf.add(str(f_path), arcname=rel_arc, recursive=False)
                        processed += 1
                        self.signals.archiveProgress.emit(processed / total_items, f"Compressing {f_path.name}")

            self.signals.archiveFinished.emit(True, f"✔ Created archive: {self.dest_archive_path.name}")
        except Exception as e:
            try:
                if self.dest_archive_path.exists():
                    self.dest_archive_path.unlink()
            except OSError:
                pass
            self.signals.archiveFinished.emit(False, f"⚠️ Compression failed: {e}")


class ExtractTask(QRunnable):
    """Background archive extractor supporting ZIP, TAR/GZ/BZ2/XZ, 7Z, and RAR with progress."""
    def __init__(self, archive_path: Path, dest_dir: Path, signals):
        super().__init__()
        self.archive_path = archive_path
        self.dest_dir = dest_dir
        self.signals = signals

    def run(self):
        import zipfile
        import tarfile

        if not self.archive_path.exists():
            self.signals.archiveFinished.emit(False, "⚠️ Archive file not found.")
            return

        try:
            self.dest_dir.mkdir(parents=True, exist_ok=True)
            name_lower = self.archive_path.name.lower()
            self.signals.archiveProgress.emit(0.05, f"Extracting {self.archive_path.name}...")

            if zipfile.is_zipfile(str(self.archive_path)):
                try:
                    zf_ctx = zipfile.ZipFile(str(self.archive_path), "r", metadata_encoding="cp1256")
                except TypeError:
                    zf_ctx = zipfile.ZipFile(str(self.archive_path), "r")
                with zf_ctx as zf:
                    members = zf.infolist()
                    total = max(1, len(members))
                    for idx, m in enumerate(members, 1):
                        if not _is_safe_extract_path(self.dest_dir, m.filename):
                            raise RuntimeError(f"Blocked unsafe path in archive: {m.filename}")
                        extracted_p = zf.extract(m, str(self.dest_dir))
                        unix_attr = m.external_attr >> 16
                        if unix_attr and os.path.exists(extracted_p) and not os.path.islink(extracted_p):
                            try:
                                os.chmod(extracted_p, unix_attr & 0o777)
                            except OSError:
                                pass
                        if idx % 5 == 0 or idx == total:
                            self.signals.archiveProgress.emit(idx / total, f"Extracting {m.filename}")
            elif tarfile.is_tarfile(str(self.archive_path)) or any(name_lower.endswith(x) for x in (".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tar.xz", ".txz")):
                with tarfile.open(str(self.archive_path), "r:*") as tf:
                    members = tf.getmembers()
                    total = max(1, len(members))
                    for idx, m in enumerate(members, 1):
                        if not _is_safe_extract_path(self.dest_dir, m.name) or m.issym() or m.islnk():
                            raise RuntimeError(f"Blocked unsafe tar member: {m.name}")
                        try:
                            tf.extract(m, str(self.dest_dir), filter="data")
                        except TypeError:
                            tf.extract(m, str(self.dest_dir))
                        if idx % 5 == 0 or idx == total:
                            self.signals.archiveProgress.emit(idx / total, f"Extracting {m.name}")
            elif name_lower.endswith(".7z") or name_lower.endswith(".rar"):
                if shutil.which("7z"):
                    self.signals.archiveProgress.emit(0.4, f"Extracting {self.archive_path.name} via 7z...")
                    res = subprocess.run(["7z", "x", "-y", f"-o{self.dest_dir}", str(self.archive_path)], capture_output=True, text=True)
                    if res.returncode != 0:
                        raise RuntimeError(res.stderr.strip() or "7z extraction failed")
                elif shutil.which("unrar") and name_lower.endswith(".rar"):
                    self.signals.archiveProgress.emit(0.4, f"Extracting {self.archive_path.name} via unrar...")
                    res = subprocess.run(["unrar", "x", "-y", str(self.archive_path), str(self.dest_dir) + "/"], capture_output=True, text=True)
                    if res.returncode != 0:
                        raise RuntimeError(res.stderr.strip() or "unrar extraction failed")
                elif shutil.which("bsdtar"):
                    res = subprocess.run(["bsdtar", "-xf", str(self.archive_path), "-C", str(self.dest_dir)], capture_output=True, text=True)
                    if res.returncode != 0:
                        raise RuntimeError(res.stderr.strip() or "bsdtar extraction failed")
                else:
                    raise RuntimeError("Install 'p7zip' (7z) or 'unrar' to extract .7z/.rar archives")
            else:
                shutil.unpack_archive(str(self.archive_path), str(self.dest_dir))

            self.signals.archiveFinished.emit(True, f"✔ Extracted to {self.dest_dir.name}")
        except Exception as e:
            self.signals.archiveFinished.emit(False, f"⚠️ Extraction failed: {e}")


class MpvSessionMonitorTask(QRunnable):
    """
    Connects to mpv's JSON IPC socket while playing a video from a Media Library
    and streams live playback progress, episode changes, and drag-and-dropped subtitles back to Find.
    Also automatically turns off HDR via toggle-hdr.sh --off when an HDR mpv session exits.
    """
    def __init__(self, file_path_str: str, ipc_sock_path: str, proc, hdr_mode: bool, initial_start_pos: float, get_progress_func, signals, jf_meta: dict = None, stream_to_local: dict = None):
        super().__init__()
        self.file_path_str = file_path_str
        self.ipc_sock_path = ipc_sock_path
        self.proc = proc
        self.hdr_mode = hdr_mode
        self.initial_start_pos = float(initial_start_pos or 0.0)
        self.get_progress_func = get_progress_func
        self.signals = signals
        self.jf_meta = dict(jf_meta) if isinstance(jf_meta, dict) else {}
        self.stream_to_local = dict(stream_to_local) if isinstance(stream_to_local, dict) else {}

    def _send_ipc_command(self, sock, cmd_list: list, req_id: int = 99):
        try:
            payload = json.dumps({"command": cmd_list, "request_id": req_id}) + "\n"
            sock.sendall(payload.encode("utf-8"))
            sock.settimeout(0.15)
            try:
                sock.recv(4096)
            except Exception:
                pass
            sock.settimeout(0.8)
        except Exception:
            pass

    def _query_ipc_property(self, sock, prop_name: str, req_id: int):
        cmd = json.dumps({"command": ["get_property", prop_name], "request_id": req_id}) + "\n"
        try:
            sock.sendall(cmd.encode("utf-8"))
        except Exception:
            return None
        buf = b""
        deadline = time.time() + 0.55
        while time.time() < deadline:
            try:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                buf += chunk
                for line in buf.decode("utf-8", errors="ignore").splitlines():
                    try:
                        msg = json.loads(line)
                        if msg.get("request_id") == req_id:
                            if msg.get("error") == "success":
                                return msg.get("data")
                            return None
                    except Exception:
                        pass
            except Exception:
                break
        return None

    def _read_mpv_watch_later_pos(self, target_path: str) -> float:
        try:
            md5_hex = hashlib.md5(target_path.encode("utf-8")).hexdigest().upper()
            candidates = [
                Path.home() / ".local" / "state" / "mpv" / "watch_later" / md5_hex,
                Path.home() / ".config" / "mpv" / "watch_later" / md5_hex,
            ]
            for wl_file in candidates:
                if wl_file.exists():
                    with open(wl_file, "r", encoding="utf-8", errors="ignore") as f:
                        for ln in f:
                            if ln.startswith("start="):
                                return float(ln.split("=", 1)[1].strip())
        except Exception:
            pass
        return -1.0

    def _resolve_active_path(self, raw_path_prop: str, fallback_dir: str) -> str:
        if not raw_path_prop:
            return ""
        p = str(raw_path_prop).strip()
        if p.startswith("file://"):
            p = QUrl(p).toLocalFile() or p[7:]
        if not os.path.isabs(p):
            p = os.path.abspath(os.path.join(fallback_dir, p))
        else:
            p = os.path.abspath(p)
        return p

    def _detect_active_external_sub(self, sock, fallback_dir: str) -> str:
        tracks = self._query_ipc_property(sock, "track-list", 5)
        if not isinstance(tracks, list):
            return ""
        for tr in tracks:
            if isinstance(tr, dict) and tr.get("type") == "sub" and tr.get("selected") is True and tr.get("external") is True:
                ext_fn = tr.get("external-filename", "")
                if ext_fn:
                    resolved = self._resolve_active_path(ext_fn, fallback_dir)
                    if resolved and os.path.exists(resolved):
                        return resolved
        return ""

    def run(self):
        active_file = os.path.abspath(self.file_path_str)
        base_dir = os.path.dirname(active_file)
        last_pos = 0.0
        duration = 0.0
        eof_reached = False
        initial_seek_done = False
        chapters_injected = False
        jf_started = False
        last_jf_sync_ts = 0.0
        last_recorded_sub = ""
        file_switch_ts = 0.0
        prev_file_final_pos = -1.0

        # Wait up to 3s for mpv to create the UNIX socket
        for _ in range(15):
            if os.path.exists(self.ipc_sock_path) or self.proc.poll() is not None:
                break
            time.sleep(0.2)

        while self.proc.poll() is None:
            if os.path.exists(self.ipc_sock_path):
                try:
                    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                        s.settimeout(0.8)
                        s.connect(self.ipc_sock_path)
                        cur_mpv_path = str(self._query_ipc_property(s, "path", 4) or "").strip()
                        is_http_stream = cur_mpv_path.startswith(("http://", "https://"))
                        if is_http_stream:
                            resolved_mpv_path = self.stream_to_local.get(cur_mpv_path, active_file)
                        else:
                            resolved_mpv_path = self._resolve_active_path(cur_mpv_path, base_dir)

                        # Detect when the user switches to the next/previous episode inside MPV!
                        if resolved_mpv_path and os.path.exists(resolved_mpv_path) and resolved_mpv_path != active_file:
                            if duration > 0 and last_pos > 0:
                                prev_done = eof_reached or (last_pos / duration >= 0.88)
                                self.signals.mpvProgressUpdated.emit(active_file, last_pos, duration, prev_done)
                            prev_file_final_pos = last_pos
                            active_file = resolved_mpv_path
                            base_dir = os.path.dirname(active_file)
                            last_pos = 0.0
                            duration = 0.0
                            eof_reached = False
                            last_recorded_sub = ""
                            file_switch_ts = time.time()

                            # Load saved subtitle and any matching external subtitles for the newly switched episode
                            saved_next = self.get_progress_func(active_file) if callable(self.get_progress_func) else {}
                            loaded_subs = set()
                            next_sub = saved_next.get("ext_sub", "")
                            if next_sub and os.path.exists(next_sub):
                                self._send_ipc_command(s, ["sub-add", next_sub, "select"], 10)
                                loaded_subs.add(os.path.abspath(next_sub))
                                last_recorded_sub = next_sub
                            for auto_sub in find_matching_external_subs_for_video(active_file):
                                if auto_sub not in loaded_subs:
                                    self._send_ipc_command(s, ["sub-add", auto_sub, "select" if not loaded_subs else "auto"], 10)
                                    loaded_subs.add(auto_sub)

                            if not saved_next.get("watched", False) and float(saved_next.get("position", 0.0) or 0.0) > 5.0:
                                self._send_ipc_command(s, ["set_property", "time-pos", float(saved_next["position"])], 11)
                            else:
                                self._send_ipc_command(s, ["set_property", "time-pos", 0.0], 11)
                            time.sleep(0.45)
                            continue

                        dur_val = self._query_ipc_property(s, "duration", 2)
                        pos_val = self._query_ipc_property(s, "time-pos", 1)
                        eof_val = self._query_ipc_property(s, "eof-reached", 3)

                        if isinstance(dur_val, (int, float)) and dur_val > 0:
                            duration = float(dur_val)
                            if not chapters_injected:
                                chapters_injected = True
                                jf_chapters = self.jf_meta.get("chapters") or []
                                if jf_chapters:
                                    existing_ch = self._query_ipc_property(s, "chapter-list", 14)
                                    if not existing_ch:
                                        self._send_ipc_command(s, ["set_property", "chapter-list", jf_chapters], 15)
                            # Perform initial resume seek ONLY for the first launched file via IPC (never global --start!)
                            if not initial_seek_done:
                                initial_seek_done = True
                                if self.initial_start_pos > 5.0 and self.initial_start_pos < duration * 0.95:
                                    self._send_ipc_command(s, ["set_property", "time-pos", self.initial_start_pos], 12)
                                    pos_val = self.initial_start_pos

                        if isinstance(pos_val, (int, float)) and pos_val >= 0:
                            f_pos = float(pos_val)
                            # Guard against stale time-pos right after switching files in MPV
                            if file_switch_ts > 0 and (time.time() - file_switch_ts) < 4.5:
                                if prev_file_final_pos > 15.0 and abs(f_pos - prev_file_final_pos) < 12.0:
                                    continue
                            last_pos = f_pos

                        if eof_val is True:
                            eof_reached = True

                        # Track external subtitle drag-and-dropped into MPV
                        ext_sub = self._detect_active_external_sub(s, base_dir)
                        if ext_sub and ext_sub != last_recorded_sub:
                            last_recorded_sub = ext_sub
                            self.signals.mpvExternalSubDetected.emit(active_file, ext_sub)

                        if duration > 0 and last_pos > 0:
                            is_done = eof_reached or (last_pos / duration >= 0.90)
                            self.signals.mpvProgressUpdated.emit(active_file, last_pos, duration, is_done)
                            if self.jf_meta.get("item_id"):
                                now_t = time.time()
                                if not jf_started:
                                    jf_started = True
                                    last_jf_sync_ts = now_t
                                    QThreadPool.globalInstance().start(
                                        lambda p=last_pos, d=duration: post_jellyfin_playback_event(self.jf_meta, "start", p, d, False)
                                    )
                                elif (now_t - last_jf_sync_ts) >= 2.5:
                                    last_jf_sync_ts = now_t
                                    QThreadPool.globalInstance().start(
                                        lambda p=last_pos, d=duration: post_jellyfin_playback_event(self.jf_meta, "progress", p, d, False)
                                    )
                except Exception:
                    pass
            time.sleep(0.8)

        # Clean up socket file
        try:
            if os.path.exists(self.ipc_sock_path):
                os.unlink(self.ipc_sock_path)
        except OSError:
            pass

        # Final check on exit for whichever episode was playing last (only if not stale from previous episode)
        wl_pos = self._read_mpv_watch_later_pos(active_file)
        if wl_pos >= 0 and (file_switch_ts == 0.0 or abs(wl_pos - prev_file_final_pos) > 12.0):
            last_pos = wl_pos
        if duration > 0 and last_pos > 0:
            is_done = eof_reached or (last_pos / duration >= 0.90)
            self.signals.mpvProgressUpdated.emit(active_file, last_pos, duration, is_done)
            if self.jf_meta.get("item_id"):
                QThreadPool.globalInstance().start(
                    lambda p=last_pos, d=duration: post_jellyfin_playback_event(self.jf_meta, "stop", p, d, True)
                )

        if self.hdr_mode:
            self.signals.mpvHdrSessionEnded.emit(int(self.proc.pid))


class DirectoryLoaderTask(QRunnable):
    def __init__(
        self,
        target_path_str: str,
        show_hidden: bool,
        is_media_lib: bool,
        is_movie_mode: bool,
        show_subtitles: bool,
        picker_ctx,
        format_size_func,
        determine_icon_func,
        get_progress_func,
        get_cached_hdr_func,
        thumb_mgr,
        folder_size_cache,
        signals
    ):
        super().__init__()
        self.target_path_str = target_path_str
        self.show_hidden = show_hidden
        self.is_media_lib = is_media_lib
        self.is_movie_mode = is_movie_mode
        self.show_subtitles = show_subtitles
        self.picker_ctx = picker_ctx
        self.format_size_func = format_size_func
        self.determine_icon_func = determine_icon_func
        self.get_progress_func = get_progress_func
        self.get_cached_hdr_func = get_cached_hdr_func
        self.thumb_mgr = thumb_mgr
        self.folder_size_cache = folder_size_cache
        self.signals = signals

    def run(self):
        entries = []
        now_ts = time.time()
        seven_days_sec = 7 * 86400

        try:
            target_path = Path(self.target_path_str)
            if target_path.exists() and target_path.is_dir():
                with os.scandir(str(target_path)) as it:
                    for entry in it:
                        if not self.show_hidden and entry.name.startswith("."):
                            continue

                        try:
                            is_dir = entry.is_dir(follow_symlinks=True)
                        except OSError:
                            is_dir = False

                        ext_lower = Path(entry.name).suffix.lower() if not is_dir else ""

                        # Hide subtitle files automatically inside Media Library unless toggled with 'C'
                        if self.is_media_lib and not is_dir and not self.show_subtitles and ext_lower in SUBTITLE_EXTS:
                            continue

                        if self.picker_ctx.isActive:
                            if self.picker_ctx.mode == "folder" and not is_dir:
                                continue
                            if not self.picker_ctx.matches_filter(entry.name, is_dir):
                                continue

                        raw_size = 0
                        raw_mod = 0
                        raw_created = 0
                        size_str = ""
                        mod_str = ""
                        created_str = ""

                        try:
                            st = entry.stat(follow_symlinks=True)
                            raw_mod = st.st_mtime
                            mod_str = datetime.fromtimestamp(raw_mod).strftime("%Y-%m-%d %H:%M")
                            raw_created = getattr(st, "st_birthtime", st.st_ctime)
                            created_str = datetime.fromtimestamp(raw_created).strftime("%Y-%m-%d %H:%M")

                            if not is_dir:
                                raw_size = max(0, int(st.st_size))
                                size_str = self.format_size_func(raw_size)
                            else:
                                cached_sz = self.folder_size_cache.get(entry.path)
                                if cached_sz is not None:
                                    raw_size = cached_sz
                                    size_str = self.format_size_func(cached_sz)
                        except OSError:
                            size_str = "-"
                            mod_str = "-"
                            created_str = "-"

                        icon, file_type = self.determine_icon_func(Path(entry.path), is_dir)
                        existing_thumb = self.thumb_mgr.get_existing_thumbnail(entry.path) if not is_dir else ""
                        folder_previews = self.thumb_mgr.get_cached_folder_preview(entry.path) if is_dir else []

                        progress_val = 0.0
                        is_watched = False
                        is_new = False
                        is_movie_item = False
                        is_hdr = False

                        if self.is_media_lib and not is_dir and ext_lower in VIDEO_EXTS:
                            p_info = self.get_progress_func(entry.path)
                            progress_val = float(p_info.get("progress", 0.0))
                            is_watched = bool(p_info.get("watched", False))
                            newest_ts = max(raw_mod, raw_created)
                            if not is_watched and (now_ts - newest_ts) <= seven_days_sec:
                                is_new = True
                            if self.is_movie_mode:
                                is_movie_item = True
                            cached_hdr = self.get_cached_hdr_func(entry.path, raw_mod)
                            if cached_hdr is not None:
                                is_hdr = bool(cached_hdr)

                        entries.append({
                            "name": entry.name,
                            "path": entry.path,
                            "is_dir": is_dir,
                            "size": size_str,
                            "modified": mod_str,
                            "created": created_str,
                            "icon": icon,
                            "type": file_type,
                            "raw_size": raw_size,
                            "raw_mod": raw_mod,
                            "raw_created": raw_created,
                            "thumb": existing_thumb,
                            "folder_previews": folder_previews,
                            "episode_num": "",
                            "progress": progress_val,
                            "is_watched": is_watched,
                            "is_new": is_new,
                            "is_movie_item": is_movie_item,
                            "is_hdr": is_hdr,
                            "episode_title": "",
                            "overview": "",
                            "rating": "",
                            "poster": ""
                        })
        except PermissionError:
            self.signals.directoryLoadError.emit(self.target_path_str, f"🔒 Permission denied: {self.target_path_str}")
        except Exception as e:
            self.signals.directoryLoadError.emit(self.target_path_str, f"⚠️ Failed to read folder: {e}")

        self.signals.directoryLoaded.emit(self.target_path_str, entries)


ISO_LANG_MAP = {
    "ara": "ar", "arabic": "ar", "ar": "ar", "العربية": "ar", "عربي": "ar",
    "eng": "en", "english": "en", "en": "en",
    "jpn": "ja", "japanese": "ja", "ja": "ja", "jp": "ja",
    "spa": "es", "spanish": "es", "es": "es",
    "fre": "fr", "fra": "fr", "french": "fr", "fr": "fr",
    "ger": "de", "deu": "de", "german": "de", "de": "de",
    "ita": "it", "italian": "it", "it": "it",
    "rus": "ru", "russian": "ru", "ru": "ru",
    "por": "pt", "portuguese": "pt", "pt": "pt", "pt-br": "pt", "por-br": "pt",
    "chi": "zh", "zho": "zh", "chinese": "zh", "zh": "zh", "chs": "zh", "cht": "zh",
    "kor": "ko", "korean": "ko", "ko": "ko",
    "tur": "tr", "turkish": "tr", "tr": "tr",
    "hin": "hi", "hindi": "hi", "hi": "hi",
    "ind": "id", "indonesian": "id", "id": "id",
    "may": "ms", "msa": "ms", "malay": "ms", "ms": "ms",
    "vie": "vi", "vietnamese": "vi", "vi": "vi",
    "tha": "th", "thai": "th", "th": "th",
    "pol": "pl", "polish": "pl", "pl": "pl",
    "dut": "nl", "nld": "nl", "dutch": "nl", "nl": "nl",
    "swe": "sv", "swedish": "sv", "sv": "sv",
    "nor": "no", "norwegian": "no", "no": "no", "nob": "no",
    "dan": "da", "danish": "da", "da": "da",
    "fin": "fi", "finnish": "fi", "fi": "fi",
    "gre": "el", "ell": "el", "greek": "el", "el": "el",
    "heb": "he", "hebrew": "he", "he": "he",
    "per": "fa", "fas": "fa", "persian": "fa", "fa": "fa",
    "ukr": "uk", "ukrainian": "uk", "uk": "uk",
    "rum": "ro", "ron": "ro", "romanian": "ro", "ro": "ro",
    "hun": "hu", "hungarian": "hu", "hu": "hu",
    "cze": "cs", "ces": "cs", "czech": "cs", "cs": "cs",
}


def _normalize_short_lang(raw_lang: str, title_hint: str = "") -> str:
    s = str(raw_lang or "").strip().lower()
    if s and s not in ("und", "unk", "unknown", "none", "mul", "zxx"):
        if s in ISO_LANG_MAP:
            return ISO_LANG_MAP[s]
        if "-" in s:
            base = s.split("-", 1)[0]
            if base in ISO_LANG_MAP:
                return ISO_LANG_MAP[base]
        if len(s) == 2 and s.isalpha():
            return s
        if len(s) == 3 and s.isalpha():
            return ISO_LANG_MAP.get(s, s[:2])
    if title_hint:
        th = title_hint.lower()
        for k, v in ISO_LANG_MAP.items():
            if len(k) >= 3 and re.search(rf'\b{re.escape(k)}\b', th):
                return v
    return "und"


def _sort_langs_arabic_first(lang_codes: list) -> list:
    seen = set()
    unique = []
    for c in lang_codes:
        if not c or c in seen:
            continue
        seen.add(c)
        unique.append(c)
    # Priority: Arabic ('ar' / 'ar (ext)') always first, then English ('en'), Japanese ('ja'), then alphabetical
    def _prio(code: str):
        base = code.split(" ")[0].lower()
        if base == "ar":
            return (0, code)
        if base == "en":
            return (1, code)
        if base == "ja":
            return (2, code)
        if base == "und":
            return (9, code)
        return (3, code)
    return sorted(unique, key=_prio)


class MediaInfoTask(QRunnable):
    def __init__(self, file_path_str: str, saved_ext_sub: str, signals):
        super().__init__()
        self.file_path_str = file_path_str
        self.saved_ext_sub = saved_ext_sub or ""
        self.signals = signals

    def _scan_external_subtitles(self) -> list:
        ext_langs = []
        p = Path(self.file_path_str)
        parent = p.parent
        stem = p.stem
        stem_low = stem.lower()

        candidates = []
        if self.saved_ext_sub and os.path.isfile(self.saved_ext_sub):
            candidates.append(Path(self.saved_ext_sub))

        try:
            if parent.is_dir():
                for entry in os.scandir(str(parent)):
                    if not entry.is_file():
                        continue
                    sf = Path(entry.name)
                    if sf.suffix.lower() not in SUBTITLE_EXTS:
                        continue
                    sub_stem_low = sf.stem.lower()
                    if sub_stem_low == stem_low or sub_stem_low.startswith(stem_low + ".") or sub_stem_low.startswith(stem_low + "_") or sub_stem_low.startswith(stem_low + "-") or sub_stem_low.startswith(stem_low + " "):
                        candidates.append(sf)
                # Also check 'Subs' or 'Subtitles' subfolder if present
                for sub_dir_name in ("Subs", "subs", "Subtitles", "subtitles"):
                    sd = parent / sub_dir_name
                    if sd.is_dir():
                        for entry in os.scandir(str(sd)):
                            if entry.is_file() and Path(entry.name).suffix.lower() in SUBTITLE_EXTS:
                                sf = Path(entry.name)
                                if sf.stem.lower().startswith(stem_low):
                                    candidates.append(sf)
        except OSError:
            pass

        seen_files = set()
        for sub_p in candidates:
            if sub_p.name in seen_files:
                continue
            seen_files.add(sub_p.name)
            sub_stem = sub_p.stem
            tail = sub_stem[len(stem):].strip("._- []()") if sub_stem.lower().startswith(stem_low) else sub_stem
            lang_code = _normalize_short_lang(tail, title_hint=sub_stem)
            if lang_code == "und":
                # Default external subtitle with exact video name (frequently Arabic in user's library)
                lang_code = "ext"
            ext_langs.append(f"{lang_code} (ext)" if lang_code != "ext" else "ext")
        return ext_langs

    def run(self):
        info = {
            "resolution": "N/A",
            "codec": "N/A",
            "bit_depth": "8-bit",
            "color_profile": "Standard",
            "bitrate": "N/A",
            "fps": "N/A",
            "audio_codec": "N/A",
            "audio_langs": [],
            "sub_langs": []
        }
        if shutil.which("ffprobe"):
            try:
                cmd = [
                    "ffprobe", "-v", "quiet", "-print_format", "json",
                    "-show_streams", "-show_format", self.file_path_str
                ]
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=2.0)
                if res.returncode == 0 and res.stdout:
                    data = json.loads(res.stdout)
                    streams = data.get("streams", [])
                    v_stream = next((s for s in streams if s.get("codec_type") == "video"), None)
                    a_streams = [s for s in streams if s.get("codec_type") == "audio"]
                    s_streams = [s for s in streams if s.get("codec_type") == "subtitle"]
                    fmt = data.get("format", {})

                    if v_stream:
                        w, h = v_stream.get("width"), v_stream.get("height")
                        if w and h:
                            info["resolution"] = f"{w}x{h}"
                        info["codec"] = v_stream.get("codec_name", "N/A").upper()

                        pix_fmt = v_stream.get("pix_fmt", "")
                        bits = v_stream.get("bits_per_raw_sample")
                        if bits:
                            info["bit_depth"] = f"{bits}-bit"
                        elif "10le" in pix_fmt or "p10" in pix_fmt or "10be" in pix_fmt:
                            info["bit_depth"] = "10-bit"
                        elif "12le" in pix_fmt or "p12" in pix_fmt:
                            info["bit_depth"] = "12-bit"
                        elif pix_fmt:
                            info["bit_depth"] = "8-bit"

                        prim = v_stream.get("color_primaries") or v_stream.get("color_space")
                        tr = v_stream.get("color_transfer")
                        if prim or tr:
                            info["color_profile"] = " / ".join([p for p in [prim, tr] if p])

                        r_fps = v_stream.get("r_frame_rate", "")
                        if "/" in r_fps:
                            num, den = map(float, r_fps.split("/"))
                            if den > 0:
                                info["fps"] = f"{round(num / den, 2)} fps"

                    br_raw = fmt.get("bit_rate") or (v_stream.get("bit_rate") if v_stream else None)
                    if br_raw:
                        try:
                            br_kbps = int(br_raw) / 1000
                            info["bitrate"] = f"{round(br_kbps / 1000, 2)} Mbps" if br_kbps >= 1000 else f"{int(br_kbps)} kbps"
                        except Exception:
                            pass

                    if a_streams:
                        info["audio_codec"] = a_streams[0].get("codec_name", "N/A").upper()
                        raw_a_langs = []
                        for ast in a_streams:
                            tags = ast.get("tags") or {}
                            l_raw = tags.get("language") or tags.get("LANGUAGE") or ""
                            t_raw = tags.get("title") or tags.get("TITLE") or ""
                            raw_a_langs.append(_normalize_short_lang(l_raw, t_raw))
                        info["audio_langs"] = _sort_langs_arabic_first(raw_a_langs)

                    raw_s_langs = []
                    for sst in s_streams:
                        tags = sst.get("tags") or {}
                        l_raw = tags.get("language") or tags.get("LANGUAGE") or ""
                        t_raw = tags.get("title") or tags.get("TITLE") or ""
                        raw_s_langs.append(_normalize_short_lang(l_raw, t_raw))

                    ext_subs = self._scan_external_subtitles()
                    info["sub_langs"] = _sort_langs_arabic_first(raw_s_langs + ext_subs)
            except Exception:
                pass
        self.signals.mediaInfoReady.emit(self.file_path_str, info)


class FolderSizeTask(QRunnable):
    def __init__(self, dir_path: str, signals):
        super().__init__()
        self.dir_path = dir_path
        self.signals = signals

    def run(self):
        total = 0
        try:
            for root, _, files in os.walk(self.dir_path, followlinks=False):
                for f in files:
                    try:
                        fp = os.path.join(root, f)
                        if not os.path.islink(fp):
                            sz = os.path.getsize(fp)
                            if sz > 0:
                                total += int(sz)
                    except OSError:
                        pass
        except Exception:
            pass
        self.signals.folderSizeReady.emit(self.dir_path, int(max(0, total)))


class MultiSelectionSizeTask(QRunnable):
    """Calculates total combined size (including all subfolders) and file/folder counts for multiple selected items."""
    def __init__(self, paths_list: list, token: str, signals):
        super().__init__()
        self.paths_list = list(paths_list)
        self.token = token
        self.signals = signals

    def run(self):
        total_bytes = 0
        file_count = 0
        dir_count = 0
        for p in self.paths_list:
            try:
                if os.path.islink(p):
                    file_count += 1
                elif os.path.isfile(p):
                    file_count += 1
                    sz = os.path.getsize(p)
                    if sz > 0:
                        total_bytes += int(sz)
                elif os.path.isdir(p):
                    dir_count += 1
                    for root, _, files in os.walk(p, followlinks=False):
                        for f in files:
                            try:
                                fp = os.path.join(root, f)
                                if not os.path.islink(fp):
                                    sz = os.path.getsize(fp)
                                    if sz > 0:
                                        total_bytes += int(sz)
                            except OSError:
                                pass
            except OSError:
                pass
        self.signals.multiSelectionSizeReady.emit(self.token, int(max(0, total_bytes)), file_count, dir_count)


class StorageAnalyzerTask(QRunnable):
    """Calculates immediate child folder & file sizes sorted descending for Storage Analyzer tabs."""
    SKIP_VIRTUAL = {"/proc", "/sys", "/dev", "/run"}

    def __init__(self, target_dir: str, show_hidden: bool, format_size_func, determine_icon_func, thumb_mgr, folder_cache: dict, signals):
        super().__init__()
        self.target_dir = os.path.abspath(target_dir)
        self.show_hidden = show_hidden
        self.format_size_func = format_size_func
        self.determine_icon_func = determine_icon_func
        self.thumb_mgr = thumb_mgr
        self.folder_cache = folder_cache
        self.signals = signals

    def _calc_dir_size(self, dir_path: str) -> int:
        if dir_path in self.folder_cache:
            return self.folder_cache[dir_path]
        total = 0
        try:
            root_dev = os.stat(dir_path, follow_symlinks=False).st_dev
        except OSError:
            return 0
        stack = [dir_path]
        while stack:
            curr = stack.pop()
            if curr in self.SKIP_VIRTUAL:
                continue
            try:
                with os.scandir(curr) as it:
                    for entry in it:
                        try:
                            if entry.is_symlink():
                                continue
                            if entry.is_file(follow_symlinks=False):
                                st = entry.stat(follow_symlinks=False)
                                total += max(0, int(st.st_size))
                            elif entry.is_dir(follow_symlinks=False):
                                st = entry.stat(follow_symlinks=False)
                                if st.st_dev == root_dev:
                                    stack.append(entry.path)
                        except OSError:
                            pass
            except OSError:
                pass
        self.folder_cache[dir_path] = total
        return total

    def run(self):
        raw_items = []
        total_dir_bytes = 0
        try:
            with os.scandir(self.target_dir) as it:
                for entry in it:
                    if not self.show_hidden and entry.name.startswith("."):
                        continue
                    if entry.path in self.SKIP_VIRTUAL:
                        continue
                    try:
                        is_dir = entry.is_dir(follow_symlinks=False)
                        st = entry.stat(follow_symlinks=False)
                        mtime = st.st_mtime
                        ctime = getattr(st, "st_birthtime", st.st_ctime)
                        if is_dir:
                            sz = self._calc_dir_size(entry.path)
                        else:
                            sz = max(0, int(st.st_size))
                        total_dir_bytes += sz
                        raw_items.append((sz, entry.name, entry.path, is_dir, mtime, ctime))
                    except OSError:
                        pass
        except OSError:
            pass

        raw_items.sort(key=lambda x: x[0], reverse=True)
        entries = []
        safe_total = max(1, total_dir_bytes)
        for sz, name, full_p, is_dir, mtime, ctime in raw_items:
            icon, ftype = self.determine_icon_func(Path(full_p), is_dir)
            ratio = min(1.0, max(0.0, float(sz) / float(safe_total))) if total_dir_bytes > 0 else 0.0
            pct_str = f"{ratio * 100.0:.1f}%"
            entries.append({
                "name": name,
                "path": full_p,
                "is_dir": is_dir,
                "size": self.format_size_func(sz),
                "modified": datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M"),
                "created": datetime.fromtimestamp(ctime).strftime("%Y-%m-%d %H:%M"),
                "icon": icon,
                "type": ftype,
                "raw_size": sz,
                "raw_mod": mtime,
                "raw_created": ctime,
                "thumb": self.thumb_mgr.get_existing_thumbnail(full_p) if not is_dir else "",
                "folder_previews": self.thumb_mgr.get_cached_folder_preview(full_p) if is_dir else [],
                "episode_num": "",
                "progress": 0.0,
                "is_watched": False,
                "is_new": False,
                "is_movie_item": False,
                "is_hdr": False,
                "episode_title": "",
                "overview": "",
                "rating": "",
                "poster": "",
                "size_ratio": round(ratio, 4),
                "percent_str": pct_str
            })

        self.signals.storageAnalyzerReady.emit(self.target_dir, entries, int(total_dir_bytes))


class TrashSizeTask(QRunnable):
    """Calculates the total size of all items across all Trash directories."""
    def __init__(self, trash_dirs: list, signals):
        super().__init__()
        self.trash_dirs = list(trash_dirs)
        self.signals = signals

    def run(self):
        total_bytes = 0
        item_count = 0
        seen = set()
        for t_dir in self.trash_dirs:
            try:
                with os.scandir(t_dir) as it:
                    for entry in it:
                        if entry.path in seen:
                            continue
                        seen.add(entry.path)
                        item_count += 1
                        try:
                            if entry.is_file(follow_symlinks=False):
                                total_bytes += max(0, int(entry.stat(follow_symlinks=False).st_size))
                            elif entry.is_dir(follow_symlinks=False):
                                for r, _, files in os.walk(entry.path, followlinks=False):
                                    for f in files:
                                        try:
                                            fp = os.path.join(r, f)
                                            if not os.path.islink(fp):
                                                total_bytes += max(0, int(os.path.getsize(fp)))
                                        except OSError:
                                            pass
                        except OSError:
                            pass
            except OSError:
                pass
        self.signals.trashSizeReady.emit(int(max(0, total_bytes)), item_count)


class RecentScannerTask(QRunnable):
    """Fast multi-drive scanner that collects the most recently modified/created files across all drives."""
    SKIP_DIRS = {
        ".cache", ".local", ".config", ".git", "node_modules", "__pycache__",
        "target", "build", "dist", "venv", ".venv", ".cargo", ".rustup",
        ".mozilla", ".thunderbird", ".steam", "Steam", ".wine", "proc", "sys",
        "dev", "run", "tmp", "var", "usr", "lib", "lib64", "etc", "boot", "srv", "opt",
        "timeshift", "lost+found", "$RECYCLE.BIN", "System Volume Information"
    }

    def __init__(self, scan_roots: list, show_hidden: bool, format_size_func, determine_icon_func, thumb_mgr, signals):
        super().__init__()
        self.scan_roots = list(scan_roots)
        self.show_hidden = show_hidden
        self.format_size_func = format_size_func
        self.determine_icon_func = determine_icon_func
        self.thumb_mgr = thumb_mgr
        self.signals = signals

    def run(self):
        heap = []  # min-heap of (timestamp, full_path, name, raw_size, mtime, ctime)
        seen_paths = set()
        max_keep = 200

        for root_Info in self.scan_roots:
            base_path, max_depth = root_Info
            if not base_path or not os.path.isdir(base_path):
                continue
            stack = [(base_path, 0)]
            visited_dirs = 0
            while stack and visited_dirs < 3500:
                curr_dir, depth = stack.pop()
                visited_dirs += 1
                try:
                    with os.scandir(curr_dir) as it:
                        for entry in it:
                            name = entry.name
                            if not self.show_hidden and name.startswith("."):
                                continue
                            if name in self.SKIP_DIRS or name.startswith(".Trash"):
                                continue
                            try:
                                if entry.is_dir(follow_symlinks=False):
                                    if depth < max_depth:
                                        stack.append((entry.path, depth + 1))
                                elif entry.is_file(follow_symlinks=False):
                                    fp = entry.path
                                    if fp in seen_paths:
                                        continue
                                    st = entry.stat(follow_symlinks=False)
                                    mtime = st.st_mtime
                                    ctime = getattr(st, "st_birthtime", st.st_ctime)
                                    newest_ts = max(mtime, ctime)
                                    if len(heap) < max_keep:
                                        seen_paths.add(fp)
                                        heapq.heappush(heap, (newest_ts, fp, name, max(0, int(st.st_size)), mtime, ctime))
                                    elif newest_ts > heap[0][0]:
                                        seen_paths.add(fp)
                                        heapq.heapreplace(heap, (newest_ts, fp, name, max(0, int(st.st_size)), mtime, ctime))
                            except OSError:
                                pass
                except OSError:
                    pass

        sorted_top = sorted(heap, key=lambda x: x[0], reverse=True)
        entries = []
        for newest_ts, full_p, fname, raw_sz, mtime, ctime in sorted_top:
            icon, file_type = self.determine_icon_func(Path(full_p), False)
            entries.append({
                "name": fname,
                "path": full_p,
                "is_dir": False,
                "size": self.format_size_func(raw_sz),
                "modified": datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M"),
                "created": datetime.fromtimestamp(ctime).strftime("%Y-%m-%d %H:%M"),
                "icon": icon,
                "type": file_type,
                "raw_size": raw_sz,
                "raw_mod": mtime,
                "raw_created": ctime,
                "thumb": self.thumb_mgr.get_existing_thumbnail(full_p),
                "folder_previews": [],
                "episode_num": "",
                "progress": 0.0,
                "is_watched": False,
                "is_new": False,
                "is_movie_item": False,
                "is_hdr": False,
                "episode_title": "",
                "overview": "",
                "rating": "",
                "poster": ""
            })

        self.signals.recentEntriesReady.emit(entries)


class MediaHubBuilderTask(QRunnable):
    """Builds the smart rows for mediahub:// (Continue Watching, Recently Added Episodes, Next Up)."""
    def __init__(self, backend_ref, signals):
        super().__init__()
        self.backend = backend_ref
        self.signals = signals

    def _format_ep_num(self, val: float) -> str:
        if float(val).is_integer():
            return str(int(val))
        return str(val)

    def _compress_ep_ranges(self, ep_numbers: list) -> str:
        if not ep_numbers:
            return "New EP added"
        unique_eps = sorted(set(ep_numbers))
        if len(unique_eps) == 1:
            return f"EP {self._format_ep_num(unique_eps[0])} added"

        is_all_int = all(float(x).is_integer() for x in unique_eps)
        if is_all_int:
            ints = [int(x) for x in unique_eps]
            ranges = []
            start = ints[0]
            prev = ints[0]
            for n in ints[1:]:
                if n == prev + 1:
                    prev = n
                else:
                    ranges.append((start, prev))
                    start = n
                    prev = n
            ranges.append((start, prev))
            if len(ranges) == 1:
                s, e = ranges[0]
                return f"EP {s}-{e} added" if s != e else f"EP {s} added"
            parts = [f"{s}-{e}" if s != e else f"{s}" for s, e in ranges[:2]]
            suffix = "..." if len(ranges) > 2 else ""
            return f"EP {', '.join(parts)}{suffix} added"
        return f"EP {self._format_ep_num(unique_eps[0])}-{self._format_ep_num(unique_eps[-1])} added"

    def _build_entry_dict(self, target_path: str, badge_text: str = "", subtitle_text: str = "", override_poster: str = "", override_prog: float = None, override_watched: bool = None) -> dict:
        p_obj = Path(target_path)
        is_dir = p_obj.is_dir()
        raw_size = 0
        raw_mod = 0.0
        raw_created = 0.0
        size_str = "-"
        mod_str = "-"
        created_str = "-"
        try:
            st = p_obj.stat()
            raw_mod = st.st_mtime
            mod_str = datetime.fromtimestamp(raw_mod).strftime("%Y-%m-%d %H:%M")
            raw_created = getattr(st, "st_birthtime", st.st_ctime)
            created_str = datetime.fromtimestamp(raw_created).strftime("%Y-%m-%d %H:%M")
            if not is_dir:
                raw_size = max(0, int(st.st_size))
                size_str = self.backend._format_size(raw_size)
        except OSError:
            pass

        icon, file_type = self.backend._determine_icon_and_type(p_obj, is_dir)
        existing_thumb = self.backend.thumb_mgr.get_existing_thumbnail(target_path) if not is_dir else ""
        if not existing_thumb and not is_dir and p_obj.suffix.lower() in VIDEO_EXTS:
            self.backend.thumb_mgr.request_thumbnail(target_path)

        folder_previews = self.backend.thumb_mgr.get_cached_folder_preview(target_path) if is_dir else []
        if is_dir and not folder_previews:
            self.backend.thumb_mgr.request_folder_preview(target_path, False)

        p_info = self.backend.config_mgr.get_media_progress(target_path) if not is_dir else {}
        prog_val = float(override_prog if override_prog is not None else p_info.get("progress", 0.0))
        watched_val = bool(override_watched if override_watched is not None else p_info.get("watched", False))

        _, is_in_movie_dir = self.backend._check_path_in_media_library(target_path)
        jf_meta = self.backend.jf_bridge.get_cached_item(target_path)

        # Ensure movies & uncached items fetch their official Jellyfin vertical poster
        if not is_dir and self.backend.jf_bridge.is_enabled:
            is_mov_candidate = is_in_movie_dir or (jf_meta and jf_meta.get("item_type") == "Movie")
            if not jf_meta or (is_mov_candidate and not jf_meta.get("poster")):
                try:
                    self.backend.jf_bridge.sync_directory_items_sync(
                        str(p_obj.parent),
                        [{"path": target_path, "name": p_obj.name, "is_dir": False, "is_movie_item": is_mov_candidate}]
                    )
                    jf_meta = self.backend.jf_bridge.get_cached_item(target_path)
                except Exception:
                    pass
            if jf_meta and jf_meta.get("item_id") and not jf_meta.get("poster") and (is_mov_candidate or jf_meta.get("item_type") == "Movie"):
                poster_dl = self.backend.jf_bridge._ensure_poster_cached(
                    jf_meta["item_id"],
                    fallback_series_id=str(jf_meta.get("SeriesId") or ""),
                    is_poster_target=True
                )
                if poster_dl:
                    jf_meta["poster"] = poster_dl
                    self.backend.jf_bridge._path_map[os.path.abspath(target_path)] = jf_meta
                    self.backend.jf_bridge.save_cache()

        parent_jf = self.backend.jf_bridge.get_cached_item(str(p_obj.parent)) if not is_dir else {}
        if not parent_jf and not is_dir and self.backend.jf_bridge.is_season_folder_name(p_obj.parent.name):
            parent_jf = self.backend.jf_bridge.get_cached_item(str(p_obj.parent.parent))

        if not is_dir and not is_in_movie_dir and not (jf_meta and jf_meta.get("poster")) and not (parent_jf and parent_jf.get("poster")) and self.backend.jf_bridge.is_enabled:
            show_dir = p_obj.parent.parent if self.backend.jf_bridge.is_season_folder_name(p_obj.parent.name) else p_obj.parent
            try:
                self.backend.jf_bridge.sync_directory_items_sync(
                    str(show_dir.parent),
                    [{"path": str(show_dir), "name": show_dir.name, "is_dir": True}]
                )
                parent_jf = self.backend.jf_bridge.get_cached_item(str(show_dir))
            except Exception:
                pass

        poster = override_poster or (jf_meta.get("poster") if jf_meta else "") or (parent_jf.get("poster") if parent_jf else "")
        series_title = (jf_meta.get("series_name") if jf_meta else "") or (parent_jf.get("title") if parent_jf else "")
        is_movie_flag = bool(is_in_movie_dir or (jf_meta and jf_meta.get("item_type") == "Movie"))

        if is_dir:
            show_folder_path = target_path
        elif not is_movie_flag:
            show_folder_path = str(p_obj.parent.parent if self.backend.jf_bridge.is_season_folder_name(p_obj.parent.name) else p_obj.parent)
        else:
            show_folder_path = str(p_obj.parent)

        if not series_title and not is_dir and not is_movie_flag:
            series_title = Path(show_folder_path).name

        ep_badge, _ = self.backend._parse_episode_info(p_obj.name) if not is_dir else ("", None)
        if not badge_text and ep_badge:
            badge_text = f"EP {ep_badge.lstrip('0') or '0'}"

        raw_jf_title = (jf_meta.get("title") if jf_meta else "")
        if not is_dir and not is_movie_flag:
            if raw_jf_title and raw_jf_title.lower() != series_title.lower():
                ep_title = f"EP {ep_badge.lstrip('0') or '0'} - {raw_jf_title}" if ep_badge and not raw_jf_title.lower().startswith(("ep", "episode")) else raw_jf_title
            elif ep_badge:
                ep_title = f"Episode {ep_badge.lstrip('0') or '0'}"
            else:
                ep_title = p_obj.stem
            # Headline is the episode name; subtitle is the clickable show name
            display_title = ep_title
            sub_line = subtitle_text or series_title or p_obj.parent.name
        else:
            ep_title = raw_jf_title or p_obj.stem
            display_title = ep_title if not is_dir else (raw_jf_title or p_obj.name)
            sub_line = subtitle_text or (series_title if series_title else p_obj.name)

        is_hdr = False
        is_new_flag = False
        now_sec = time.time()
        seven_days = 7 * 86400
        if not is_dir and p_obj.suffix.lower() in VIDEO_EXTS:
            newest_ts = max(raw_mod, raw_created)
            if not watched_val and newest_ts > 0 and (now_sec - newest_ts) <= seven_days:
                is_new_flag = True
            cached_hdr = self.backend.config_mgr.get_cached_hdr(target_path, raw_mod)
            if cached_hdr is not None:
                is_hdr = bool(cached_hdr)
            elif hasattr(self, "_unprobed_hdr_items"):
                self._unprobed_hdr_items.append((target_path, raw_mod))

        return {
            "name": p_obj.name,
            "display_title": display_title,
            "subtitle": sub_line,
            "badge": badge_text,
            "path": target_path,
            "show_path": show_folder_path,
            "is_dir": is_dir,
            "size": size_str,
            "modified": mod_str,
            "created": created_str,
            "icon": icon,
            "type": file_type,
            "raw_size": raw_size,
            "raw_mod": raw_mod,
            "raw_created": raw_created,
            "thumb": existing_thumb,
            "folder_previews": folder_previews,
            "episode_num": ep_badge or "",
            "progress": round(prog_val, 4),
            "is_watched": watched_val,
            "is_new": is_new_flag,
            "is_movie_item": bool(is_in_movie_dir or (jf_meta and jf_meta.get("item_type") == "Movie")),
            "is_hdr": is_hdr,
            "episode_title": ep_title,
            "overview": (jf_meta.get("overview") if jf_meta else "") or (parent_jf.get("overview") if parent_jf else ""),
            "rating": str(jf_meta.get("rating", "")) if (jf_meta and jf_meta.get("rating")) else (str(parent_jf.get("rating", "")) if (parent_jf and parent_jf.get("rating")) else ""),
            "poster": poster
        }

    def run(self):
        self._unprobed_hdr_items = []
        rows_cfg = self.backend.getMediaHubRowConfig()
        hidden_map = dict(self.backend.config_mgr.get("media_hub_hidden", {}) or {})
        dirty_hidden = False

        def _is_hidden_item(fpath: str, cur_prog: float, cur_pos: float) -> bool:
            nonlocal dirty_hidden
            norm = os.path.abspath(fpath)
            if norm not in hidden_map:
                return False
            rec = hidden_map[norm]
            saved_prog = float(rec.get("progress", 0.0) or 0.0)
            saved_pos = float(rec.get("position", 0.0) or 0.0)
            if abs(cur_prog - saved_prog) >= 0.015 or abs(cur_pos - saved_pos) >= 15.0:
                hidden_map.pop(norm, None)
                dirty_hidden = True
                return False
            return True

        # 1. Continue Watching (Merge Jellyfin Resume + Local In-Progress)
        cw_map = {}
        if self.backend.jf_bridge.is_enabled:
            for loc_p, meta in self.backend.jf_bridge.fetch_resume_items_sync():
                if not meta.get("watched", False) and (meta.get("progress", 0.0) > 0.01 or meta.get("position", 0.0) > 10.0):
                    cw_map[loc_p] = {
                        "path": loc_p,
                        "progress": float(meta.get("progress", 0.0)),
                        "position": float(meta.get("position", 0.0)),
                        "ts": float(meta.get("server_updated_at", 0.0) or time.time())
                    }

        self.backend.config_mgr.reload_progress_from_disk()
        for fpath, pdata in list(self.backend.config_mgr._progress.items()):
            if not isinstance(pdata, dict) or not os.path.isfile(fpath):
                continue
            in_lib, _ = self.backend._check_path_in_media_library(fpath)
            if not in_lib:
                continue
            watched = bool(pdata.get("watched", False))
            prog = float(pdata.get("progress", 0.0) or 0.0)
            pos = float(pdata.get("position", 0.0) or 0.0)
            ts = float(pdata.get("updated_at", 0.0) or 0.0)
            if not watched and (prog > 0.01 or pos > 10.0) and prog < 0.92:
                norm_p = os.path.abspath(fpath)
                if norm_p not in cw_map or ts > cw_map[norm_p]["ts"]:
                    cw_map[norm_p] = {
                        "path": norm_p,
                        "progress": prog,
                        "position": pos,
                        "ts": ts if ts > 0 else os.path.getmtime(norm_p)
                    }

        cw_sorted = sorted(cw_map.values(), key=lambda x: x["ts"], reverse=True)
        continue_items = []
        for item in cw_sorted:
            if _is_hidden_item(item["path"], item["progress"], item["position"]):
                continue
            mins, secs = divmod(int(item["position"]), 60)
            pct_int = int(round(item["progress"] * 100))
            ep_b, _ = self.backend._parse_episode_info(Path(item["path"]).name)
            b_str = f"EP {ep_b.lstrip('0') or '0'} • {pct_int}%" if ep_b else f"{pct_int}% ({mins:02d}:{secs:02d})"
            continue_items.append(
                self._build_entry_dict(
                    item["path"],
                    badge_text=b_str,
                    override_prog=item["progress"],
                    override_watched=False
                )
            )
            if len(continue_items) >= 25:
                break

        # 2. Next Up (Jellyfin /Shows/NextUp + Local Fallback for active shows)
        next_up_items = []
        seen_next_paths = {x["path"] for x in continue_items}
        seen_series = set()

        if self.backend.jf_bridge.is_enabled:
            for loc_p, meta in self.backend.jf_bridge.fetch_next_up_items_sync():
                if loc_p in seen_next_paths:
                    continue
                p_info = self.backend.config_mgr.get_media_progress(loc_p)
                cur_prog = float(p_info.get("progress", meta.get("progress", 0.0)) or 0.0)
                cur_pos = float(p_info.get("position", meta.get("position", 0.0)) or 0.0)
                is_already_watched = bool(meta.get("watched", False) or p_info.get("watched", False) or cur_prog >= 0.90)
                if is_already_watched:
                    continue
                if _is_hidden_item(loc_p, cur_prog, cur_pos):
                    continue
                seen_next_paths.add(loc_p)
                s_name = meta.get("series_name") or str(Path(loc_p).parent)
                seen_series.add(s_name.lower())
                idx_num = meta.get("index_number")
                s_num = meta.get("season_number")
                if s_num is not None and idx_num is not None:
                    b_lbl = f"S{int(s_num):02d}E{int(idx_num):02d}"
                elif idx_num is not None:
                    b_lbl = f"EP {int(idx_num)}"
                else:
                    b_lbl = "NEXT UP"
                next_up_items.append(
                    self._build_entry_dict(
                        loc_p,
                        badge_text=b_lbl,
                        override_poster=meta.get("poster", ""),
                        override_prog=cur_prog,
                        override_watched=False
                    )
                )

        # Local Next-Up fallback for series where the user finished an episode
        libs = self.backend.getMediaLibraries()
        for lib in libs:
            if lib.get("mode") == "movies":
                continue
            lp = lib.get("path", "")
            if not lp or not os.path.isdir(lp):
                continue
            try:
                with os.scandir(lp) as it:
                    for entry in it:
                        if not entry.is_dir() or entry.name.startswith("."):
                            continue
                        if entry.name.lower() in seen_series:
                            continue
                        # Check if folder has any watched episode
                        res_ep = self.backend._find_resume_episode_in_folder(entry.path)
                        if not res_ep or res_ep in seen_next_paths:
                            continue
                        p_info = self.backend.config_mgr.get_media_progress(res_ep)
                        # Only include in Next Up if this target episode hasn't been started yet, but a previous episode in the show was watched
                        if p_info.get("position", 0.0) <= 5.0 and not p_info.get("watched", False):
                            ep_b, ep_v = self.backend._parse_episode_info(Path(res_ep).name)
                            if ep_v is not None and ep_v > 1:
                                if not _is_hidden_item(res_ep, 0.0, 0.0):
                                    seen_next_paths.add(res_ep)
                                    show_jf = self.backend.jf_bridge.get_cached_item(entry.path)
                                    next_up_items.append(
                                        self._build_entry_dict(
                                            res_ep,
                                            badge_text=f"NEXT • EP {ep_b.lstrip('0') or '1'}",
                                            override_poster=show_jf.get("poster", "") if show_jf else ""
                                        )
                                    )
            except OSError:
                pass

        # 3. New Episodes (Strictly last 7 days only, then automatically disappears!)
        raw_recent_events = []
        now_ts = time.time()
        window_sec = 7 * 86400  # 7 days (1 week) window

        for lib in libs:
            lp = lib.get("path", "")
            is_movie_lib = (lib.get("mode") == "movies")
            if not lp or not os.path.isdir(lp):
                continue
            try:
                with os.scandir(lp) as it:
                    for show_entry in it:
                        if show_entry.name.startswith("."):
                            continue
                        if is_movie_lib and show_entry.is_file() and Path(show_entry.name).suffix.lower() in VIDEO_EXTS:
                            st = show_entry.stat()
                            ts = max(st.st_mtime, getattr(st, "st_birthtime", st.st_ctime))
                            if (now_ts - ts) <= window_sec:
                                mov_jf = self.backend.jf_bridge.get_cached_item(show_entry.path)
                                mov_poster = mov_jf.get("poster", "") if mov_jf else ""
                                mov_title = (mov_jf.get("title") if mov_jf else "") or Path(show_entry.name).stem
                                raw_recent_events.append({
                                    "ts": ts,
                                    "is_movie": True,
                                    "show_path": show_entry.path,
                                    "show_name": mov_title,
                                    "poster": mov_poster,
                                    "file_path": show_entry.path,
                                    "file_name": show_entry.name,
                                    "ep_val": None
                                })
                            continue

                        if not show_entry.is_dir():
                            continue

                        show_jf = self.backend.jf_bridge.get_cached_item(show_entry.path)
                        poster_p = show_jf.get("poster", "") if show_jf else ""
                        show_display = (show_jf.get("title") if show_jf else "") or show_entry.name

                        try:
                            with os.scandir(show_entry.path) as sub_it:
                                for sub_e in sub_it:
                                    if sub_e.name.startswith("."):
                                        continue
                                    if sub_e.is_file() and Path(sub_e.name).suffix.lower() in VIDEO_EXTS:
                                        st = sub_e.stat()
                                        ts = max(st.st_mtime, getattr(st, "st_birthtime", st.st_ctime))
                                        if (now_ts - ts) <= window_sec:
                                            _, ep_v = self.backend._parse_episode_info(sub_e.name)
                                            raw_recent_events.append({
                                                "ts": ts,
                                                "is_movie": False,
                                                "show_path": show_entry.path,
                                                "show_name": show_display,
                                                "poster": poster_p,
                                                "file_path": sub_e.path,
                                                "file_name": sub_e.name,
                                                "ep_val": ep_v
                                            })
                                    elif sub_e.is_dir() and self.backend.jf_bridge.is_season_folder_name(sub_e.name):
                                        try:
                                            with os.scandir(sub_e.path) as s_it:
                                                for se in s_it:
                                                    if se.is_file() and not se.name.startswith(".") and Path(se.name).suffix.lower() in VIDEO_EXTS:
                                                        st = se.stat()
                                                        ts = max(st.st_mtime, getattr(st, "st_birthtime", st.st_ctime))
                                                        if (now_ts - ts) <= window_sec:
                                                            _, ep_v = self.backend._parse_episode_info(se.name)
                                                            raw_recent_events.append({
                                                                "ts": ts,
                                                                "is_movie": False,
                                                                "show_path": show_entry.path,
                                                                "show_name": show_display,
                                                                "poster": poster_p,
                                                                "file_path": se.path,
                                                                "file_name": se.name,
                                                                "ep_val": ep_v
                                                            })
                                        except OSError:
                                            pass
                        except OSError:
                            pass
            except OSError:
                pass

        # Sort all individual episode/movie additions strictly by timestamp (Newest first)
        raw_recent_events.sort(key=lambda e: e["ts"], reverse=True)

        # 3b. Per-Library Recently Added Rows (Each library in Media Libraries / Jellyfin)
        per_lib_rows = {}
        for lib in libs:
            lp = lib.get("path", "")
            lib_name = lib.get("name") or Path(lp).name or "Library"
            is_movie_lib = (lib.get("mode") == "movies")
            if not lp or not os.path.isdir(lp):
                continue
            row_id = f"lib_recent_{hashlib.md5(os.path.abspath(lp).encode('utf-8')).hexdigest()[:8]}"
            lib_events = []
            try:
                with os.scandir(lp) as it:
                    for entry in it:
                        if entry.name.startswith("."):
                            continue
                        try:
                            st = entry.stat()
                            mtime = max(st.st_mtime, getattr(st, "st_birthtime", st.st_ctime))
                        except OSError:
                            continue
                        if is_movie_lib and entry.is_file() and Path(entry.name).suffix.lower() in VIDEO_EXTS:
                            lib_events.append((mtime, entry.path, True, entry.path))
                        elif entry.is_dir():
                            latest_ep_ts = mtime
                            latest_ep_file = ""
                            try:
                                with os.scandir(entry.path) as sub_it:
                                    for sub_e in sub_it:
                                        if sub_e.name.startswith("."):
                                            continue
                                        if sub_e.is_file() and Path(sub_e.name).suffix.lower() in VIDEO_EXTS:
                                            sst = sub_e.stat()
                                            ts = max(sst.st_mtime, getattr(sst, "st_birthtime", sst.st_ctime))
                                            if ts >= latest_ep_ts or not latest_ep_file:
                                                latest_ep_ts = max(latest_ep_ts, ts)
                                                latest_ep_file = sub_e.path
                                        elif sub_e.is_dir() and self.backend.jf_bridge.is_season_folder_name(sub_e.name):
                                            with os.scandir(sub_e.path) as s_it:
                                                for se in s_it:
                                                    if se.is_file() and not se.name.startswith(".") and Path(se.name).suffix.lower() in VIDEO_EXTS:
                                                        sst = se.stat()
                                                        ts = max(sst.st_mtime, getattr(sst, "st_birthtime", sst.st_ctime))
                                                        if ts >= latest_ep_ts or not latest_ep_file:
                                                            latest_ep_ts = max(latest_ep_ts, ts)
                                                            latest_ep_file = se.path
                            except OSError:
                                pass
                            lib_events.append((latest_ep_ts, entry.path, False, latest_ep_file))
            except OSError:
                pass

            lib_events.sort(key=lambda x: x[0], reverse=True)
            lib_cards = []
            for ts, target_p, is_mov, latest_file in lib_events[:25]:
                p_info = self.backend.config_mgr.get_media_progress(target_p) if not os.path.isdir(target_p) else {"progress": 0.0, "position": 0.0}
                if _is_hidden_item(target_p, float(p_info.get("progress", 0.0)), float(p_info.get("position", 0.0))):
                    continue
                show_jf = self.backend.jf_bridge.get_cached_item(target_p)
                poster_p = show_jf.get("poster", "") if show_jf else ""
                show_title = (show_jf.get("title") if show_jf else "") or (Path(target_p).stem if is_mov else ((show_jf.get("title") if show_jf else "") or Path(target_p).name))
                if is_mov:
                    badge_s = "MOVIE"
                    sub_d = lib_name
                else:
                    if latest_file:
                        ep_b, _ = self.backend._parse_episode_info(Path(latest_file).name)
                        badge_s = f"Latest EP {ep_b.lstrip('0') or '1'}" if ep_b else "SERIES"
                    else:
                        badge_s = "SERIES"
                    sub_d = lib_name
                card = self._build_entry_dict(
                    target_p,
                    badge_text=badge_s,
                    subtitle_text=sub_d,
                    override_poster=poster_p
                )
                card["display_title"] = show_title
                card["subtitle"] = sub_d
                card["show_path"] = target_p
                card["is_movie_item"] = True
                card["is_recently_added_card"] = not is_mov
                lib_cards.append(card)

            per_lib_rows[row_id] = {
                "id": row_id,
                "title": f"📂  Recently Added — {lib_name}",
                "subtitle": f"Latest titles added to {lib_name} ({lp})",
                "items": lib_cards
            }

        # Sequential Run-Length Grouping: only merge consecutive events that belong to the same show_path!
        chronological_runs = []
        for ev in raw_recent_events:
            if ev["is_movie"]:
                chronological_runs.append([ev])
                continue
            if chronological_runs and not chronological_runs[-1][0]["is_movie"] and chronological_runs[-1][0]["show_path"] == ev["show_path"]:
                chronological_runs[-1].append(ev)
            else:
                chronological_runs.append([ev])

        recently_added_items = []
        for batch in chronological_runs:
            first_ev = batch[0]
            if first_ev["is_movie"]:
                target_p = first_ev["file_path"]
                badge_s = "NEW MOVIE"
                sub_d = first_ev["file_name"]
                poster_p = first_ev["poster"]
                show_title = first_ev["show_name"]
            else:
                ep_nums = [x["ep_val"] for x in batch if x["ep_val"] is not None]
                badge_s = self._compress_ep_ranges(ep_nums) if ep_nums else (f"{len(batch)} EP added" if len(batch) > 1 else "New EP added")
                poster_p = first_ev["poster"]
                show_title = first_ev["show_name"]
                # Always navigate to the show's folder page when clicking a card in New Episodes
                target_p = first_ev["show_path"]
                if len(batch) == 1:
                    ep_b, _ = self.backend._parse_episode_info(first_ev["file_name"])
                    ep_headline = f"Episode {ep_b.lstrip('0') or '1'}" if ep_b else Path(first_ev["file_name"]).stem
                else:
                    ep_headline = f"{len(batch)} Episodes ({badge_s.replace(' added', '')})"
                sub_d = show_title

            batch_watched = True
            batch_prog_sum = 0.0
            for bev in batch:
                bp_info = self.backend.config_mgr.get_media_progress(bev["file_path"])
                b_w = bool(bp_info.get("watched", False))
                b_pr = float(bp_info.get("progress", 0.0) or 0.0)
                if not b_w and b_pr < 0.90:
                    batch_watched = False
                batch_prog_sum += (1.0 if b_w else b_pr)
            avg_batch_prog = batch_prog_sum / max(1, len(batch))

            p_info = self.backend.config_mgr.get_media_progress(target_p) if not os.path.isdir(target_p) else {"progress": avg_batch_prog, "position": 0.0}
            if _is_hidden_item(target_p, float(p_info.get("progress", 0.0)), float(p_info.get("position", 0.0))):
                continue

            card = self._build_entry_dict(
                target_p,
                badge_text=badge_s,
                subtitle_text=sub_d,
                override_poster=poster_p,
                override_prog=1.0 if batch_watched else avg_batch_prog,
                override_watched=batch_watched
            )
            if first_ev["is_movie"]:
                if show_title:
                    card["display_title"] = show_title
            else:
                card["display_title"] = ep_headline
                card["subtitle"] = show_title
                card["show_path"] = first_ev["show_path"]
                latest_file_p = first_ev["file_path"]
                try:
                    f_mtime = os.path.getmtime(latest_file_p)
                    c_hdr = self.backend.config_mgr.get_cached_hdr(latest_file_p, f_mtime)
                    if c_hdr is not None:
                        card["is_hdr"] = bool(c_hdr)
                    else:
                        self._unprobed_hdr_items.append((latest_file_p, f_mtime))
                except OSError:
                    pass
            card["is_new"] = not batch_watched
            card["is_recently_added_card"] = True
            recently_added_items.append(card)
            if len(recently_added_items) >= 25:
                break

        if dirty_hidden:
            self.backend.config_mgr.set("media_hub_hidden", hidden_map)

        # 4. Airing Weekly Tracker (100% Instant Local Read — Never blocks Media Hub on network I/O!)
        airing_items = []
        try:
            self.backend.airing_tracker.check_and_advance_airing_timers_sync(send_os_notification=True)
            airing_items = self.backend._build_airing_hub_items()
            if self.backend.airing_tracker.needs_background_sync():
                self.backend._trigger_background_airing_sync(force=False)
        except Exception:
            pass

        row_map = {
            "continue_watching": {
                "id": "continue_watching",
                "title": "▶  Continue Watching",
                "subtitle": "Resume in-progress episodes & movies (Synced with Jellyfin)",
                "items": continue_items
            },
            "recently_added": {
                "id": "recently_added",
                "title": "✨  New Episodes",
                "subtitle": "Latest episode batches added to your media libraries",
                "items": recently_added_items
            },
            "next_up": {
                "id": "next_up",
                "title": "⏭️  Next Up",
                "subtitle": "Next unwatched episodes ready to play",
                "items": next_up_items
            },
            "airing": {
                "id": "airing",
                "title": "📡  Airing Weekly Tracker",
                "subtitle": f"Live airing schedule & episode progress ({self.backend.airing_tracker.mal_username})",
                "items": airing_items
            },
            **per_lib_rows
        }

        final_sections = []
        for r_cfg in rows_cfg:
            if not r_cfg.get("visible", True):
                continue
            rid = r_cfg.get("id", "")
            if rid in row_map:
                sec = dict(row_map[rid])
                if r_cfg.get("title"):
                    sec["raw_title"] = r_cfg["title"]
                final_sections.append(sec)

        if self._unprobed_hdr_items:
            hdr_task = HdrBatchDetectorTask(self._unprobed_hdr_items, self.backend.config_mgr, self.signals)
            self.backend.thread_pool.start(hdr_task)

        self.signals.mediaHubSectionsReady.emit(final_sections)


class FileManagerBackend(QObject):
    currentPathChanged = Signal()
    breadcrumbsChanged = Signal()
    canGoBackChanged = Signal()
    canGoForwardChanged = Signal()
    viewModeChanged = Signal()
    gridColumnsChanged = Signal()
    gridStyleChanged = Signal()
    sidebarModeChanged = Signal()
    sortByChanged = Signal()
    sortOrderChanged = Signal()
    selectedItemChanged = Signal()
    selectedPathsChanged = Signal()
    showHiddenChanged = Signal()
    swapMouseButtonsChanged = Signal()
    autoPlayHdrChanged = Signal()
    mpvAutoFullscreenChanged = Signal()
    recentFoldersChanged = Signal()
    isLoadingRecentChanged = Signal()
    daemonStateChanged = Signal()
    mediaLibraryStateChanged = Signal()
    showSubtitlesChanged = Signal()
    tabsChanged = Signal()
    cacheSizeChanged = Signal()
    maxCacheMbChanged = Signal()
    transparentBlurChanged = Signal()
    sidebarUpdated = Signal()
    favoritesUpdated = Signal()
    desktopAppsUpdated = Signal()
    fontsDirChanged = Signal()
    defaultFmStateChanged = Signal()
    sessionConfigChanged = Signal()
    iconGalleryChanged = Signal()
    toastMessage = Signal(str)
    compressionProgressChanged = Signal()
    jellyfinConfigChanged = Signal()
    anonymousModeChanged = Signal()
    mediaHubDataChanged = Signal()
    mediaHubConfigChanged = Signal()
    clipboardChanged = Signal()
    renameConflictDetected = Signal(str, str, str)
    trashInfoChanged = Signal()
    searchResultsChanged = Signal()
    searchScopeChanged = Signal()
    searchFiltersChanged = Signal()
    analyzerStateChanged = Signal()
    folderSizeReady = Signal(str, str)
    pickerCompleted = Signal(list)

    scaleFactorChanged = Signal()
    scrollSpeedChanged = Signal()
    themeColorChanged = Signal()
    windowActivationRequested = Signal()
    notificationSettingsChanged = Signal()
    requestRefreshSignal = Signal()

    def __init__(self, parent=None, is_picker_mode: bool = False, is_mediahub_mode: bool = False):
        super().__init__(parent)
        self._launched_as_picker = bool(is_picker_mode)
        self._launched_as_mediahub = bool(is_mediahub_mode)
        self.config_mgr = ConfigManager()
        self.jf_bridge = JellyfinBridge(self.config_mgr)
        self.airing_tracker = AiringTracker(self.config_mgr)
        self.jf_signals = JellyfinSignals()
        self.jf_signals.folderMetadataReady.connect(self._on_jellyfin_folder_metadata_ready)
        self.picker_ctx = PickerContext(self)

        self._default_view_mode = self.config_mgr.get("view_mode", "details")
        self._default_sort_by = self.config_mgr.get("sort_by", "name")
        self._default_sort_ascending = self.config_mgr.get("sort_ascending", True)

        self._view_mode = self._default_view_mode
        self._icon_gallery_items = []

        # Determine initial startup path or restore previous session
        startup_raw = str(self.config_mgr.get("startup_path", str(Path.home()))).strip()
        if startup_raw not in ("favorites://", "recent://", "trash://", "mediahub://") and not startup_raw.startswith("analyzer://"):
            startup_raw = os.path.abspath(os.path.expanduser(startup_raw))
            if not os.path.isdir(startup_raw):
                startup_raw = os.path.abspath(str(Path.home()))

        restore_enabled = bool(self.config_mgr.get("restore_last_session", True))
        saved_session = self.config_mgr.get("last_session", {}) if restore_enabled else {}
        saved_tabs = saved_session.get("tabs", []) if isinstance(saved_session, dict) else []

        valid_restored_tabs = []
        for st in saved_tabs:
            if isinstance(st, dict) and st.get("path"):
                tp = st["path"]
                if tp in ("favorites://", "recent://", "trash://", "mediahub://") or tp.startswith("analyzer://") or os.path.isdir(tp):
                    valid_restored_tabs.append({
                        "path": tp,
                        "title": st.get("title") or self._tab_title_for_path(tp),
                        "history": [tp],
                        "history_idx": 0
                    })

        if self._launched_as_mediahub:
            self._current_path = "mediahub://"
            self._history = ["mediahub://"]
            self._history_idx = 0
            self._tabs = [{
                "path": "mediahub://",
                "title": "Media Hub",
                "history": ["mediahub://"],
                "history_idx": 0
            }]
            self._active_tab_index = 0
        elif valid_restored_tabs:
            self._tabs = valid_restored_tabs
            act_idx = int(saved_session.get("active_index", 0) or 0)
            self._active_tab_index = max(0, min(len(self._tabs) - 1, act_idx))
            self._current_path = self._tabs[self._active_tab_index]["path"]
            self._history = list(self._tabs[self._active_tab_index]["history"])
            self._history_idx = 0
        else:
            self._current_path = startup_raw
            self._history = [self._current_path]
            self._history_idx = 0
            self._tabs = [{
                "path": self._current_path,
                "title": self._tab_title_for_path(self._current_path),
                "history": [self._current_path],
                "history_idx": 0
            }]
            self._active_tab_index = 0
        self._grid_columns = self.config_mgr.get("grid_columns", 0)
        self._grid_style = self.config_mgr.get("grid_style", "floating")
        self._sidebar_mode = self.config_mgr.get("sidebar_mode", "auto")
        self._sort_by = self.config_mgr.get("sort_by", "name")
        self._sort_ascending = self.config_mgr.get("sort_ascending", True)
        self._transparent_blur = self.config_mgr.get("transparent_blur", True)
        self._show_hidden = bool(self.config_mgr.get("show_hidden", False))
        self._swap_mouse_buttons = bool(self.config_mgr.get("swap_mouse_buttons", False))
        self._auto_play_hdr = bool(self.config_mgr.get("auto_play_hdr", True))
        self._mpv_auto_fullscreen = bool(self.config_mgr.get("mpv_auto_fullscreen", True))
        # Always reset Anonymous Mode to False on startup/shutdown
        self._anonymous_mode = False
        self.config_mgr.set("anonymous_mode", False)
        self._media_hub_sections = []
        self._is_loading_media_hub = False
        self._is_loading_recent = False
        self._show_subtitles_in_media = False
        self._active_hdr_pids = set()
        self._selected_item = {}
        self._selected_paths = []
        self._last_selected_row = -1
        self._search_results = []
        self._search_scope = "recursive"
        self._search_match_mode = "contains"
        self._search_target_type = "all"
        self._search_ext_filter = ""
        self._last_search_query = ""
        self._is_analyzing_storage = False
        self._analyzer_total_size_str = "0 B"
        self._analyzer_item_count = 0
        self._clipboard_cut = False
        self._clipboard_path = ""
        self._clipboard_paths = []
        self._pending_extract_archive = ""
        self._is_compressing = False
        self._compression_progress = 0.0
        self._compression_status = ""
        self._pending_highlight_paths = []
        self._folder_size_cache = {}
        self._calculating_folders = set()
        self._selection_calc_token = ""
        self._trash_total_size_str = "0 B"
        self._trash_item_count = 0
        self._mime_apps_cache = {}
        self._media_info_cache = {}

        self._cached_drives = []
        self._last_drives_ts = 0.0

        self.file_model = FileListModel(self)
        self.media_hub_model = MediaHubSectionModel(self)
        self.sys_bridge = SystemIntegrationBridge(self, self) if not self._launched_as_picker else None

        # Separate high-priority directory pool from heavy background size/transfer workers
        self.dir_pool = QThreadPool(self)
        self.dir_pool.setMaxThreadCount(4)
        self.thread_pool = QThreadPool(self)
        self.thread_pool.setMaxThreadCount(4)
        self._active_bg_tasks = set()

        self.signals = AsyncWorkerSignals()
        self.signals.directoryLoaded.connect(self._on_directory_loaded)
        self._raw_toast_emit = self.toastMessage.emit
        self.signals.directoryLoadError.connect(lambda _p, msg: self.emitToastFiltered(msg, "file_ops"))
        self.signals.folderSizeReady.connect(self._on_folder_size_calculated)
        self.signals.multiSelectionSizeReady.connect(self._on_multi_selection_size_ready)
        self.signals.trashSizeReady.connect(self._on_trash_size_ready)
        self.signals.recentEntriesReady.connect(self._on_recent_entries_ready)
        self.signals.mediaInfoReady.connect(self._on_media_info_ready)
        self.signals.mpvProgressUpdated.connect(self._on_mpv_progress_updated)
        self.signals.mpvExternalSubDetected.connect(self._on_mpv_external_sub_detected)
        self.signals.mpvHdrSessionEnded.connect(self._on_mpv_hdr_session_ended)
        self.signals.hdrStatusDetected.connect(self._on_hdr_status_detected)
        self.signals.externalPickerFinished.connect(self._on_external_picker_finished)
        self.signals.iconGalleryReady.connect(self._on_icon_gallery_ready)
        self.signals.archiveProgress.connect(self._on_archive_progress)
        self.signals.archiveFinished.connect(self._on_archive_finished)
        self.signals.mediaHubSectionsReady.connect(self._on_media_hub_sections_ready)
        self.signals.storageAnalyzerReady.connect(self._on_storage_analyzer_ready)

        # Debounce timers for QFileSystemWatcher so rapid file downloads or daemon writes never thrash the UI
        self._dir_reload_debounce = QTimer(self)
        self._dir_reload_debounce.setSingleShot(True)
        self._dir_reload_debounce.setInterval(120)
        self._dir_reload_debounce.timeout.connect(self.refresh)
        self.signals.requestRefresh.connect(self._trigger_immediate_refresh, Qt.ConnectionType.QueuedConnection)
        self.requestRefreshSignal.connect(self._trigger_immediate_refresh, Qt.ConnectionType.QueuedConnection)

        self._progress_reload_debounce = QTimer(self)
        self._progress_reload_debounce.setSingleShot(True)
        self._progress_reload_debounce.setInterval(450)
        self._progress_reload_debounce.timeout.connect(self._apply_debounced_progress_reload)

        self.watcher = QFileSystemWatcher(self)
        self.watcher.directoryChanged.connect(self._on_dir_changed_externally)

        self.mounts_watcher = QFileSystemWatcher(self)
        if os.path.exists("/proc/mounts"):
            self.mounts_watcher.addPath("/proc/mounts")
        for media_root in ("/run/media", f"/run/media/{os.environ.get('USER', '')}", "/media", "/mnt"):
            if os.path.isdir(media_root):
                self.mounts_watcher.addPath(media_root)
        self.mounts_watcher.fileChanged.connect(self._on_mounts_changed)
        self.mounts_watcher.directoryChanged.connect(self._on_mounts_changed)

        self.progress_watcher = QFileSystemWatcher(self)
        if not self._launched_as_picker:
            if not self.config_mgr.progress_file.exists():
                self.config_mgr.save_progress()
            self.progress_watcher.addPath(str(self.config_mgr.progress_file))
            self.progress_watcher.addPath(str(self.config_mgr.config_dir))
            self.progress_watcher.fileChanged.connect(self._on_progress_file_changed_externally)
            self.progress_watcher.directoryChanged.connect(self._on_progress_dir_changed_externally)

            if bool(self.config_mgr.get("daemon_autostart", True)):
                QThreadPool.globalInstance().start(self._ensure_media_daemon_running)

            self.jf_auto_sync_timer = QTimer(self)
            self.jf_auto_sync_timer.setInterval(25000)
            self.jf_auto_sync_timer.timeout.connect(self._on_auto_jellyfin_poll)
            self.jf_auto_sync_timer.start()

            self.airing_timer = QTimer(self)
            self.airing_timer.setInterval(60000)
            self.airing_timer.timeout.connect(self._on_airing_minute_tick)
            self.airing_timer.start()

        self.thumb_mgr = ThumbnailManager(self.config_mgr.cache_dir, self)
        self.thumb_mgr.thumbnailReady.connect(self._on_thumbnail_ready)
        self.thumb_mgr.folderPreviewReady.connect(self._on_folder_preview_ready)

        self.search_mgr = SearchManager(self.config_mgr.cache_dir, self, load_on_init=not self._launched_as_picker)
        self.search_mgr.searchResultsReady.connect(self._on_search_results_ready)

        self.load_directory(self._current_path)

        if not self._launched_as_picker:
            QThreadPool.globalInstance().start(self.config_mgr.clean_cache)
            QThreadPool.globalInstance().start(lambda: self.search_mgr.build_incremental_index(self._get_indexable_roots()))

    @Property(float, notify=scaleFactorChanged)
    def uiScaleFactor(self) -> float:
        return float(self.config_mgr.get("scale_factor", 1.35) or 1.35)

    @Slot(float)
    def setUiScaleFactor(self, val: float):
        clamped = round(min(2.2, max(0.85, float(val))), 2)
        self.config_mgr.set("scale_factor", clamped)
        self.scaleFactorChanged.emit()

    @Property(float, notify=scrollSpeedChanged)
    def scrollSpeedMultiplier(self) -> float:
        return float(self.config_mgr.get("scroll_speed_multiplier", 1.25) or 1.25)

    @Slot(float)
    def setScrollSpeedMultiplier(self, val: float):
        clamped = round(min(4.0, max(0.3, float(val))), 2)
        self.config_mgr.set("scroll_speed_multiplier", clamped)
        self.scrollSpeedChanged.emit()

    @Property(bool, notify=sessionConfigChanged)
    def keepAliveInBackground(self) -> bool:
        return bool(self.config_mgr.get("keep_alive_in_background", True))

    @Slot(bool)
    def setKeepAliveInBackground(self, enabled: bool):
        self.config_mgr.set("keep_alive_in_background", bool(enabled))
        self.sessionConfigChanged.emit()

    def emitToastFiltered(self, msg: str, category: str = "general"):
        ncfg = self.airing_tracker.get_notification_config()
        if not ncfg.get("master_enabled", True) or not ncfg.get("in_app_toasts_enabled", True):
            return
        if category == "file_ops" and not ncfg.get("toast_file_ops", True):
            return
        if category == "archive" and not ncfg.get("toast_archive_ops", True):
            return
        if category == "jellyfin" and not ncfg.get("toast_jellyfin_sync", True):
            return
        if category == "clipboard" and not ncfg.get("toast_clipboard", True):
            return
        self.toastMessage.emit(msg)

    @Property(str, notify=mediaHubConfigChanged)
    def mediaHubTheme(self) -> str:
        return str(self.config_mgr.get("media_hub_theme", "obsidian") or "obsidian")

    @Slot(str)
    def setMediaHubTheme(self, theme_id: str):
        valid_themes = ("obsidian", "oled", "crimson", "violet", "emerald", "ocean", "match_app")
        clean_id = str(theme_id or "obsidian").strip().lower()
        if clean_id not in valid_themes:
            clean_id = "obsidian"
        if self.config_mgr.get("media_hub_theme") != clean_id:
            self.config_mgr.set("media_hub_theme", clean_id)
            self.mediaHubConfigChanged.emit()
            self.toastMessage.emit(f"🎨 Media Hub theme set to '{clean_id.replace('_', ' ').title()}'")

    @Property(str, notify=themeColorChanged)
    def accentColor(self) -> str:
        return str(self.config_mgr.get("accent_color", "#0078d4") or "#0078d4")

    @Property(str, notify=themeColorChanged)
    def accentHoverColor(self) -> str:
        c = QColor(self.accentColor)
        if c.isValid():
            return c.lighter(118).name()
        return "#1a88e0"

    @Property(list, notify=themeColorChanged)
    def recentAccentColors(self) -> list:
        raw = self.config_mgr.get("recent_accent_colors", [])
        if not isinstance(raw, list) or not raw:
            return ["#0078d4", "#8b5cf6", "#10b981", "#f59e0b", "#ec4899"]
        return [str(x) for x in raw[:5] if str(x).startswith("#")]

    @Slot(str)
    def setAccentColor(self, hex_color: str):
        clean = str(hex_color or "").strip()
        if not clean.startswith("#"):
            clean = "#" + clean
        c = QColor(clean)
        if not c.isValid():
            self.toastMessage.emit("⚠️ Invalid color code")
            return
        norm_hex = c.name().lower()
        self.config_mgr.set("accent_color", norm_hex)

        recent = [x.lower() for x in self.recentAccentColors if x.lower() != norm_hex]
        recent.insert(0, norm_hex)
        self.config_mgr.set("recent_accent_colors", recent[:5])
        self.themeColorChanged.emit()

    @Slot(list, bool)
    def handleExternalIpcRequest(self, paths_list: list, select_mode: bool = False):
        # Always wake up, unhide, and focus the application window when a new launch request arrives!
        self.windowActivationRequested.emit()
        if not paths_list:
            return
        first_p = paths_list[0]
        if select_mode and os.path.exists(first_p):
            parent_d = first_p if os.path.isdir(first_p) else os.path.dirname(first_p)
            self.addTab(parent_d)
            self.selectMultiplePaths(paths_list)
            return
        for p in paths_list:
            if not p:
                continue
            if os.path.isdir(p) or p in ("recent://", "trash://", "favorites://", "mediahub://") or p.startswith("analyzer://"):
                self.addTab(p)
            elif os.path.exists(p):
                parent_d = os.path.dirname(p)
                self.addTab(parent_d)
                self.selectMultiplePaths([p])

    @Slot()
    def quitApplicationCompletely(self):
        self.shutdownCleanup()
        QGuiApplication.quit()

    def _on_mounts_changed(self, _path: str = ""):
        self._last_drives_ts = 0.0
        self.sidebarUpdated.emit()

    @Slot(str, result=dict)
    def getEpisodeDetailedInfo(self, file_path_str: str) -> dict:
        """Retrieves exact duration, formatted size, and checks metadata strictly for Arabic subtitles ('ar')."""
        if not file_path_str or not os.path.isfile(file_path_str):
            return {"duration_str": "", "size_str": "", "has_arabic_sub": False, "sub_tag": ""}

        p_info = self.config_mgr.get_media_progress(file_path_str)
        dur = float(p_info.get("duration", 0.0) or 0.0)
        if dur <= 0:
            if file_path_str in self._media_info_cache:
                c_dur = self._media_info_cache[file_path_str].get("duration_sec", 0.0)
                dur = float(c_dur or 0.0)
            if dur <= 0 and shutil.which("ffprobe"):
                try:
                    pr = subprocess.run([
                        "ffprobe", "-v", "error", "-show_entries", "format=duration",
                        "-of", "default=noprint_wrappers=1:nokey=1", file_path_str
                    ], capture_output=True, text=True, timeout=1.2)
                    if pr.returncode == 0 and pr.stdout.strip():
                        dur = float(pr.stdout.strip())
                        self.config_mgr.set_media_progress(file_path_str, float(p_info.get("position", 0.0) or 0.0), dur)
                except Exception:
                    pass

        mins, secs = divmod(int(dur), 60)
        hrs, mins = divmod(mins, 60)
        if hrs > 0:
            dur_str = f"{hrs}h {mins:02d}m"
        elif mins > 0:
            dur_str = f"{mins}m {secs:02d}s"
        elif secs > 0:
            dur_str = f"{secs}s"
        else:
            dur_str = ""

        size_str = ""
        try:
            sz = os.path.getsize(file_path_str)
            size_str = self._format_size(sz)
        except OSError:
            pass

        has_ar = False
        mi = self._media_info_cache.get(file_path_str)
        if mi and isinstance(mi.get("sub_langs"), list):
            has_ar = any("ar" in str(x).lower() for x in mi["sub_langs"])
        else:
            # Fallback 1: Check external subtitles
            matching_exts = find_matching_external_subs_for_video(file_path_str)
            if matching_exts and any(any(k in Path(x).stem.lower() for k in (".ar", "_ar", "-ar", "arabic", "ara")) for x in matching_exts):
                has_ar = True
            elif shutil.which("ffprobe"):
                # Fallback 2: Direct ffprobe stream metadata check
                try:
                    cmd = [
                        "ffprobe", "-v", "quiet", "-select_streams", "s",
                        "-show_entries", "stream_tags=language,title", "-of", "json", file_path_str
                    ]
                    res = subprocess.run(cmd, capture_output=True, text=True, timeout=1.2)
                    if res.returncode == 0 and res.stdout:
                        s_data = json.loads(res.stdout)
                        for st in s_data.get("streams", []):
                            tags = st.get("tags") or {}
                            lang = str(tags.get("language") or "").lower()
                            title = str(tags.get("title") or "").lower()
                            if any(k in lang for k in ("ara", "arabic", "ar")) or any(k in title for k in ("arabic", "عربي", "ترجمة")):
                                has_ar = True
                                break
                except Exception:
                    pass

        return {
            "duration_str": dur_str,
            "size_str": size_str,
            "has_arabic_sub": has_ar,
            "sub_tag": "ar" if has_ar else ""
        }

    @Slot(str, result=dict)
    def getFolderMediaSummary(self, folder_path_str: str) -> dict:
        """Calculates total episodes, accurate total duration, total disk size, and resume state for Show header."""
        target_dir = os.path.abspath(folder_path_str) if folder_path_str else ""
        if not target_dir or not os.path.isdir(target_dir):
            return {}

        total_bytes = 0
        total_duration = 0.0
        episode_count = 0
        has_watched_any = False
        resume_ep_path = self._find_resume_episode_in_folder(target_dir)

        try:
            for root, _, files in os.walk(target_dir):
                for f in files:
                    ext = Path(f).suffix.lower()
                    if ext in VIDEO_EXTS and not f.startswith("."):
                        episode_count += 1
                        fp = os.path.join(root, f)
                        try:
                            st = os.stat(fp)
                            total_bytes += st.st_size
                        except OSError:
                            pass
                        p_info = self.config_mgr.get_media_progress(fp)
                        dur = float(p_info.get("duration", 0.0) or 0.0)
                        if dur <= 0 and shutil.which("ffprobe"):
                            try:
                                pr = subprocess.run([
                                    "ffprobe", "-v", "error", "-show_entries", "format=duration",
                                    "-of", "default=noprint_wrappers=1:nokey=1", fp
                                ], capture_output=True, text=True, timeout=1.0)
                                if pr.returncode == 0 and pr.stdout.strip():
                                    dur = float(pr.stdout.strip())
                                    self.config_mgr.set_media_progress(fp, float(p_info.get("position", 0.0) or 0.0), dur)
                            except Exception:
                                pass
                        total_duration += dur
                        if p_info.get("watched") or float(p_info.get("progress", 0.0) or 0.0) > 0.02:
                            has_watched_any = True
        except Exception:
            pass

        resume_info = {}
        resume_progress_ratio = 0.0
        if resume_ep_path and os.path.exists(resume_ep_path):
            p_inf = self.config_mgr.get_media_progress(resume_ep_path)
            pos = float(p_inf.get("position", 0.0) or 0.0)
            dur = float(p_inf.get("duration", 0.0) or 0.0)
            if dur > 0:
                resume_progress_ratio = min(1.0, max(0.0, pos / dur))
            badge, ep_v = self._parse_episode_info(Path(resume_ep_path).name)
            mins, secs = divmod(int(pos), 60)
            resume_info = {
                "path": resume_ep_path,
                "name": Path(resume_ep_path).name,
                "ep_num": str(int(ep_v)) if (ep_v is not None and float(ep_v).is_integer()) else (badge or "1"),
                "position": pos,
                "duration": dur,
                "time_str": f"{mins:02d}:{secs:02d}" if pos > 5.0 else "",
                "ratio": resume_progress_ratio,
                "is_resumable": pos > 5.0 and not p_inf.get("watched", False)
            }

        # Format Total Duration accurately (e.g. 5h 24m or 48m)
        tot_mins = int(total_duration // 60)
        tot_hrs, rem_mins = divmod(tot_mins, 60)
        dur_str = f"{tot_hrs}h {rem_mins}m" if tot_hrs > 0 else (f"{rem_mins}m" if rem_mins > 0 else "-")

        jf_meta = self.jf_bridge.get_cached_item(target_dir) or {}
        year = jf_meta.get("year", "")
        rating = jf_meta.get("rating", "")
        overview = jf_meta.get("overview", "")
        poster = jf_meta.get("poster", "")

        return {
            "title": jf_meta.get("title") or Path(target_dir).name,
            "path": target_dir,
            "episode_count": episode_count,
            "total_size": self._format_size(total_bytes),
            "total_duration": dur_str,
            "year": str(year) if year else "",
            "rating": str(rating) if rating else "",
            "overview": overview,
            "poster": poster,
            "resume": resume_info
        }

    @Slot(str, result=dict)
    def getItemProperties(self, file_path_str: str) -> dict:
        target = file_path_str.strip() if file_path_str else str(self._current_path)
        if target.startswith("analyzer://"):
            target = target[11:]
        if not target or target in ("recent://", "trash://", "favorites://", "mediahub://") or not os.path.exists(target):
            return {}
        try:
            p = Path(target)
            st = p.lstat()
            is_link = stat_mod.S_ISLNK(st.st_mode)
            real_st = p.stat() if p.exists() else st
            is_dir = stat_mod.S_ISDIR(real_st.st_mode)
            mode_bits = real_st.st_mode & 0o777
            try:
                owner_name = pwd.getpwuid(real_st.st_uid).pw_name
            except Exception:
                owner_name = str(real_st.st_uid)
            try:
                group_name = grp.getgrgid(real_st.st_gid).gr_name
            except Exception:
                group_name = str(real_st.st_gid)

            icon, ftype = self._determine_icon_and_type(p, is_dir)
            if is_dir:
                cached_sz = self._folder_size_cache.get(str(p))
                size_str = self._format_size(cached_sz) if cached_sz is not None else "Folder"
            else:
                size_str = self._format_size(max(0, int(real_st.st_size)))

            ctime = getattr(real_st, "st_birthtime", real_st.st_ctime)
            return {
                "name": p.name or str(p),
                "path": os.path.abspath(str(p)),
                "parent_dir": str(p.parent),
                "is_dir": is_dir,
                "is_symlink": is_link,
                "symlink_target": os.readlink(str(p)) if is_link else "",
                "icon": icon,
                "type": ftype,
                "size": size_str,
                "raw_size": int(real_st.st_size) if not is_dir else int(self._folder_size_cache.get(str(p), 0)),
                "modified": datetime.fromtimestamp(real_st.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
                "created": datetime.fromtimestamp(ctime).strftime("%Y-%m-%d %H:%M:%S"),
                "accessed": datetime.fromtimestamp(real_st.st_atime).strftime("%Y-%m-%d %H:%M:%S"),
                "owner": owner_name,
                "group": group_name,
                "octal": f"0{oct(mode_bits)[2:].zfill(3)}",
                "u_r": bool(mode_bits & stat_mod.S_IRUSR),
                "u_w": bool(mode_bits & stat_mod.S_IWUSR),
                "u_x": bool(mode_bits & stat_mod.S_IXUSR),
                "g_r": bool(mode_bits & stat_mod.S_IRGRP),
                "g_w": bool(mode_bits & stat_mod.S_IWGRP),
                "g_x": bool(mode_bits & stat_mod.S_IXGRP),
                "o_r": bool(mode_bits & stat_mod.S_IROTH),
                "o_w": bool(mode_bits & stat_mod.S_IWOTH),
                "o_x": bool(mode_bits & stat_mod.S_IXOTH),
            }
        except Exception:
            return {}

    @Slot(str, int, result=bool)
    def setItemPermissions(self, file_path_str: str, mode_int: int) -> bool:
        if not file_path_str or not os.path.exists(file_path_str):
            return False
        try:
            os.chmod(file_path_str, int(mode_int) & 0o777)
            self.toastMessage.emit(f"✔ Updated permissions to 0{oct(int(mode_int) & 0o777)[2:].zfill(3)}")
            self.refresh()
            return True
        except Exception as e:
            self.toastMessage.emit(f"⚠️ Failed to change permissions: {e}")
            return False

    @Property(QObject, constant=True)
    def picker(self):
        return self.picker_ctx

    @Property(str, notify=currentPathChanged)
    def currentPath(self):
        return str(self._current_path)

    @Property(str, constant=True)
    def trashPath(self):
        return "trash://"

    @Property(bool, notify=currentPathChanged)
    def isTrashView(self) -> bool:
        return str(self._current_path) == "trash://"

    @Property(bool, notify=currentPathChanged)
    def isStorageAnalyzerView(self) -> bool:
        return str(self._current_path).startswith("analyzer://")

    @Property(bool, notify=analyzerStateChanged)
    def isAnalyzingStorage(self) -> bool:
        return self._is_analyzing_storage

    @Property(str, notify=analyzerStateChanged)
    def analyzerTotalSize(self) -> str:
        return self._analyzer_total_size_str

    @Property(int, notify=analyzerStateChanged)
    def analyzerItemCount(self) -> int:
        return self._analyzer_item_count

    @Slot(str)
    def openStorageAnalyzer(self, target_dir: str = ""):
        raw = target_dir.strip() if target_dir else str(self._current_path)
        if raw.startswith("analyzer://"):
            raw = raw[11:]
        if not raw or raw in ("recent://", "trash://", "favorites://", "mediahub://"):
            raw = str(Path.home())
        norm = os.path.abspath(os.path.expanduser(raw))
        if not os.path.isdir(norm):
            norm = os.path.dirname(norm)
        self.addTab(f"analyzer://{norm}")

    @Property(str, notify=trashInfoChanged)
    def trashTotalSize(self) -> str:
        return self._trash_total_size_str

    @Property(int, notify=trashInfoChanged)
    def trashItemCount(self) -> int:
        return self._trash_item_count

    @Property(bool, notify=showHiddenChanged)
    def showHidden(self):
        return self._show_hidden

    @showHidden.setter
    def showHidden(self, val: bool):
        if self._show_hidden != val:
            self._show_hidden = bool(val)
            self.config_mgr.set("show_hidden", self._show_hidden)
            self.thumb_mgr.folder_cache.clear()
            self.thumb_mgr.requested_folders.clear()
            self.showHiddenChanged.emit()
            self.refresh()

    @Slot(bool)
    def setShowHidden(self, val: bool):
        self.showHidden = val

    @Property(bool, notify=swapMouseButtonsChanged)
    def swapMouseButtons(self):
        return self._swap_mouse_buttons

    @swapMouseButtons.setter
    def swapMouseButtons(self, val: bool):
        if self._swap_mouse_buttons != bool(val):
            self._swap_mouse_buttons = bool(val)
            self.config_mgr.set("swap_mouse_buttons", self._swap_mouse_buttons)
            self.swapMouseButtonsChanged.emit()

    @Slot(bool)
    def setSwapMouseButtons(self, val: bool):
        self.swapMouseButtons = val

    @Property(bool, notify=autoPlayHdrChanged)
    def autoPlayHdr(self):
        return self._auto_play_hdr

    @autoPlayHdr.setter
    def autoPlayHdr(self, val: bool):
        if self._auto_play_hdr != bool(val):
            self._auto_play_hdr = bool(val)
            self.config_mgr.set("auto_play_hdr", self._auto_play_hdr)
            self.autoPlayHdrChanged.emit()

    @Slot(bool)
    def setAutoPlayHdr(self, val: bool):
        self.autoPlayHdr = val

    @Property(bool, notify=mpvAutoFullscreenChanged)
    def mpvAutoFullscreen(self) -> bool:
        return self._mpv_auto_fullscreen

    @mpvAutoFullscreen.setter
    def mpvAutoFullscreen(self, val: bool):
        if self._mpv_auto_fullscreen != bool(val):
            self._mpv_auto_fullscreen = bool(val)
            self.config_mgr.set("mpv_auto_fullscreen", self._mpv_auto_fullscreen)
            self.mpvAutoFullscreenChanged.emit()

    @Slot(bool)
    def setMpvAutoFullscreen(self, val: bool):
        self.mpvAutoFullscreen = val

    @Property(bool, notify=isLoadingRecentChanged)
    def isLoadingRecent(self) -> bool:
        return self._is_loading_recent

    @Slot(result=list)
    def getRecentWatchedFolders(self) -> list:
        raw = self.config_mgr.get("recent_watched_folders", [])
        if not isinstance(raw, list):
            return []
        return [str(p) for p in raw if p and os.path.isdir(str(p))]

    @Slot(str)
    def addRecentWatchedFolder(self, folder_path: str):
        if not folder_path:
            return
        norm = os.path.abspath(os.path.expanduser(folder_path.strip()))
        if not os.path.isdir(norm):
            return
        current = self.getRecentWatchedFolders()
        if norm not in current:
            current.append(norm)
            self.config_mgr.set("recent_watched_folders", current)
            self.recentFoldersChanged.emit()
            if str(self._current_path) == "recent://":
                self.refresh()

    @Slot(str)
    def removeRecentWatchedFolder(self, folder_path: str):
        if not folder_path:
            return
        norm = os.path.abspath(os.path.expanduser(folder_path.strip()))
        current = [p for p in self.getRecentWatchedFolders() if os.path.abspath(p) != norm and p != folder_path]
        self.config_mgr.set("recent_watched_folders", current)
        self.recentFoldersChanged.emit()
        if str(self._current_path) == "recent://":
            self.refresh()

    @Slot()
    def clearRecentWatchedFolders(self):
        self.config_mgr.set("recent_watched_folders", [])
        self.recentFoldersChanged.emit()
        if str(self._current_path) == "recent://":
            self.refresh()

    @Slot()
    def shutdownCleanup(self):
        if self._anonymous_mode:
            self._anonymous_mode = False
        self.config_mgr.set("anonymous_mode", False)

    # ==========================================================================
    # Media Library Background Daemon Manager (systemd --user + fallback process)
    # ==========================================================================

    def _get_daemon_service_path(self) -> Path:
        xdg_config = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
        return Path(xdg_config) / "systemd" / "user" / "find-media-daemon.service"

    def _get_daemon_script_path(self) -> Path:
        return Path(__file__).resolve().parent / "media_daemon.py"

    def _get_daemon_pid_file(self) -> Path:
        rt_pid = _get_secure_runtime_dir() / "find_media_daemon.pid"
        if rt_pid.exists():
            return rt_pid
        return Path("/tmp") / f"find_media_daemon_{os.getuid()}.pid"

    def _is_daemon_process_alive(self) -> bool:
        pid_file = self._get_daemon_pid_file()
        if pid_file.exists():
            try:
                pid = int(pid_file.read_text(encoding="utf-8").strip())
                os.kill(pid, 0)
                return True
            except Exception:
                pass
        try:
            res = subprocess.run(
                ["systemctl", "--user", "is-active", "find-media-daemon.service"],
                capture_output=True, text=True, timeout=1.5
            )
            if res.returncode == 0 and res.stdout.strip() == "active":
                return True
        except Exception:
            pass
        return False

    def _ensure_media_daemon_running(self):
        if self._is_daemon_process_alive():
            return
        srv_file = self._get_daemon_service_path()
        if srv_file.exists() and shutil.which("systemctl"):
            try:
                subprocess.run(["systemctl", "--user", "start", "find-media-daemon.service"], timeout=2.0)
                if self._is_daemon_process_alive():
                    self.daemonStateChanged.emit()
                    return
            except Exception:
                pass
        cmd_daemon = [sys.executable, "--daemon"] if getattr(sys, "frozen", False) else [sys.executable, str(self._get_daemon_script_path())]
        if getattr(sys, "frozen", False) or self._get_daemon_script_path().exists():
            try:
                subprocess.Popen(
                    cmd_daemon,
                    start_new_session=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                time.sleep(0.15)
                self.daemonStateChanged.emit()
            except Exception:
                pass

    @Property(bool, notify=daemonStateChanged)
    def isDaemonRunning(self) -> bool:
        return self._is_daemon_process_alive()

    @Property(bool, notify=daemonStateChanged)
    def isDaemonInstalled(self) -> bool:
        return self._get_daemon_service_path().exists()

    @Property(bool, notify=daemonStateChanged)
    def daemonAutostart(self) -> bool:
        return bool(self.config_mgr.get("daemon_autostart", True))

    @Slot(bool)
    def setDaemonAutostart(self, enabled: bool):
        self.config_mgr.set("daemon_autostart", bool(enabled))
        if self._get_daemon_service_path().exists() and shutil.which("systemctl"):
            try:
                action = "enable" if enabled else "disable"
                subprocess.run(["systemctl", "--user", action, "find-media-daemon.service"], timeout=2.5)
            except Exception:
                pass
        if enabled:
            self._ensure_media_daemon_running()
        self.daemonStateChanged.emit()

    @Slot(result=str)
    def getDaemonServiceContent(self) -> str:
        srv = self._get_daemon_service_path()
        if srv.exists():
            try:
                return srv.read_text(encoding="utf-8")
            except Exception:
                pass
        script = self._get_daemon_script_path()
        exec_line = f'"{sys.executable}" --daemon' if getattr(sys, "frozen", False) else f'"{sys.executable}" "{script}"'
        return (
            "[Unit]\n"
            "Description=Find Media Library MPV Tracker & HDR Daemon\n"
            "After=graphical-session.target\n\n"
            "[Service]\n"
            "Type=simple\n"
            f"ExecStart={exec_line}\n"
            "Restart=on-failure\n"
            "RestartSec=2\n\n"
            "[Install]\n"
            "WantedBy=default.target\n"
        )

    @Slot(str)
    def installOrSaveDaemonService(self, custom_unit_content: str = ""):
        srv = self._get_daemon_service_path()
        srv.parent.mkdir(parents=True, exist_ok=True)
        content = custom_unit_content.strip() if custom_unit_content.strip() else self.getDaemonServiceContent()
        try:
            srv.write_text(content + "\n", encoding="utf-8")
            if shutil.which("systemctl"):
                subprocess.run(["systemctl", "--user", "daemon-reload"], timeout=2.5)
                if self.daemonAutostart:
                    subprocess.run(["systemctl", "--user", "enable", "--now", "find-media-daemon.service"], timeout=3.0)
                else:
                    subprocess.run(["systemctl", "--user", "restart", "find-media-daemon.service"], timeout=3.0)
            else:
                self.restartMediaDaemon()
        except Exception:
            pass
        self.daemonStateChanged.emit()

    @Slot()
    def startMediaDaemon(self):
        self._ensure_media_daemon_running()
        self.daemonStateChanged.emit()

    @Slot()
    def stopMediaDaemon(self):
        if self._get_daemon_service_path().exists() and shutil.which("systemctl"):
            try:
                subprocess.run(["systemctl", "--user", "stop", "find-media-daemon.service"], timeout=2.5)
            except Exception:
                pass
        pid_file = self._get_daemon_pid_file()
        if pid_file.exists():
            try:
                pid = int(pid_file.read_text(encoding="utf-8").strip())
                os.kill(pid, 15)
            except Exception:
                pass
            try:
                pid_file.unlink()
            except OSError:
                pass
        self.daemonStateChanged.emit()

    @Slot()
    def restartMediaDaemon(self):
        self.stopMediaDaemon()
        time.sleep(0.15)
        self._ensure_media_daemon_running()
        self.daemonStateChanged.emit()

    @Slot()
    def removeDaemonService(self):
        self.stopMediaDaemon()
        srv = self._get_daemon_service_path()
        if srv.exists():
            if shutil.which("systemctl"):
                try:
                    subprocess.run(["systemctl", "--user", "disable", "find-media-daemon.service"], timeout=2.5)
                except Exception:
                    pass
            try:
                srv.unlink()
            except OSError:
                pass
            if shutil.which("systemctl"):
                try:
                    subprocess.run(["systemctl", "--user", "daemon-reload"], timeout=2.5)
                except Exception:
                    pass
        self.daemonStateChanged.emit()

    def _on_progress_dir_changed_externally(self, _dir_path: str):
        p_str = str(self.config_mgr.progress_file)
        if os.path.exists(p_str) and p_str not in self.progress_watcher.files():
            self.progress_watcher.addPath(p_str)
            self._on_progress_file_changed_externally(p_str)

    def _on_progress_file_changed_externally(self, path_str: str):
        if os.path.exists(path_str) and path_str not in self.progress_watcher.files():
            self.progress_watcher.addPath(path_str)
        self._progress_reload_debounce.start()

    def _apply_debounced_progress_reload(self):
        self.config_mgr.reload_progress_from_disk()
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()
            return
        if self.isMediaLibraryView:
            total = self.file_model.rowCount()
            for r in range(total):
                ent = self.file_model.get_entry_at(r)
                if ent and not ent.get("is_dir", False):
                    p_info = self.config_mgr.get_media_progress(ent["path"])
                    self.file_model.update_media_progress(
                        ent["path"],
                        float(p_info.get("progress", 0.0)),
                        bool(p_info.get("watched", False))
                    )

    def _on_hdr_status_detected(self, file_path_str: str, is_hdr: bool):
        self.file_model.update_hdr_status(file_path_str, is_hdr)
        self.media_hub_model.update_hdr_in_place(file_path_str, is_hdr)
        if self._selected_item.get("path") == file_path_str:
            updated = dict(self._selected_item)
            updated["is_hdr"] = bool(is_hdr)
            self._selected_item = updated
            self.selectedItemChanged.emit()

    # ==========================================================================
    # Media Library & Movie Folder Management + MPV Integration
    # ==========================================================================

    def _check_path_in_media_library(self, path_str: str):
        """Returns (is_in_library: bool, is_movie_folder: bool)."""
        if path_str == "mediahub://":
            return True, False
        if not path_str or path_str in ("recent://", "trash://", "favorites://"):
            return False, False
        try:
            norm_p = os.path.abspath(path_str)
        except Exception:
            return False, False

        movie_dirs = set(self.config_mgr.get("movie_folders", []))
        for mf in movie_dirs:
            if norm_p == mf or norm_p.startswith(mf.rstrip(os.sep) + os.sep):
                return True, True

        libs = self.config_mgr.get("media_libraries", [])
        matched_lib = None
        for item in libs:
            lp = item.get("path", "") if isinstance(item, dict) else str(item)
            if not lp:
                continue
            if norm_p == lp or norm_p.startswith(lp.rstrip(os.sep) + os.sep):
                matched_lib = item
                break

        if matched_lib is not None:
            is_movie = (matched_lib.get("mode") == "movies") if isinstance(matched_lib, dict) else False
            return True, is_movie
        return False, False

    @Property(bool, notify=mediaLibraryStateChanged)
    def isMediaLibraryView(self):
        in_lib, _ = self._check_path_in_media_library(str(self._current_path))
        return in_lib

    @Property(bool, notify=currentPathChanged)
    def isMediaHubView(self) -> bool:
        return str(self._current_path) == "mediahub://"

    @Property(bool, notify=anonymousModeChanged)
    def anonymousMode(self) -> bool:
        return bool(self._anonymous_mode)

    @Slot(bool)
    def setAnonymousMode(self, enabled: bool):
        if self._anonymous_mode != bool(enabled):
            self._anonymous_mode = bool(enabled)
            self.config_mgr.set("anonymous_mode", self._anonymous_mode)
            self.anonymousModeChanged.emit()
            if self._anonymous_mode:
                self.toastMessage.emit("🕵️ Anonymous Mode ON — No watch progress saved locally or to Jellyfin")
            else:
                self.toastMessage.emit("🌐 Anonymous Mode OFF — Normal progress tracking active")

    @Slot()
    def toggleAnonymousMode(self):
        self.setAnonymousMode(not self._anonymous_mode)

    @Property(list, notify=mediaHubDataChanged)
    def mediaHubSections(self) -> list:
        return self._media_hub_sections

    @Property(QObject, constant=True)
    def mediaHubModel(self):
        return self.media_hub_model

    @Property(bool, notify=mediaHubDataChanged)
    def isLoadingMediaHub(self) -> bool:
        return self._is_loading_media_hub

    @Slot(result=list)
    def getMediaHubRowConfig(self) -> list:
        raw = self.config_mgr.get("media_hub_rows", [])
        defaults = [
            {"id": "continue_watching", "title": "Continue Watching", "visible": True},
            {"id": "recently_added", "title": "New Episodes", "visible": True},
            {"id": "next_up", "title": "Next Up", "visible": True},
            {"id": "airing", "title": "Airing Weekly Tracker", "visible": True},
        ]
        for lib in self.getMediaLibraries():
            lp = lib.get("path", "")
            if not lp:
                continue
            lib_name = lib.get("name") or Path(lp).name or "Library"
            rid = f"lib_recent_{hashlib.md5(os.path.abspath(lp).encode("utf-8")).hexdigest()[:8]}"
            defaults.append({
                "id": rid,
                "title": f"Recently Added — {lib_name}",
                "visible": True
            })

        valid_ids = {d["id"]: d["title"] for d in defaults}
        if not isinstance(raw, list) or not raw:
            return defaults
        seen = set()
        out = []
        for item in raw:
            if isinstance(item, dict) and item.get("id") in valid_ids:
                rid = item["id"]
                if rid not in seen:
                    seen.add(rid)
                    raw_t = str(item.get("title") or valid_ids[rid])
                    if rid == "recently_added" and raw_t == "Recently Added Episodes":
                        raw_t = "New Episodes"
                    elif rid.startswith("lib_recent_"):
                        raw_t = valid_ids[rid]
                    out.append({
                        "id": rid,
                        "title": raw_t,
                        "visible": bool(item.get("visible", True))
                    })
        for d in defaults:
            if d["id"] not in seen:
                out.append(d)
        return out

    @Slot(int, int)
    def moveMediaHubRow(self, from_idx: int, to_idx: int):
        rows = self.getMediaHubRowConfig()
        if not (0 <= from_idx < len(rows)) or not (0 <= to_idx < len(rows)) or from_idx == to_idx:
            return
        item = rows.pop(from_idx)
        rows.insert(to_idx, item)
        self.config_mgr.set("media_hub_rows", rows)
        self.mediaHubConfigChanged.emit()
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    @Slot(str, bool)
    def setMediaHubRowVisible(self, row_id: str, visible: bool):
        rows = self.getMediaHubRowConfig()
        for r in rows:
            if r["id"] == row_id:
                r["visible"] = bool(visible)
        self.config_mgr.set("media_hub_rows", rows)
        self.mediaHubConfigChanged.emit()
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    @Slot(str)
    def hideFromMediaHub(self, target_path_str: str):
        if not target_path_str:
            return
        norm = os.path.abspath(target_path_str)
        hidden = dict(self.config_mgr.get("media_hub_hidden", {}) or {})
        p_info = self.config_mgr.get_media_progress(norm)
        hidden[norm] = {
            "progress": float(p_info.get("progress", 0.0) or 0.0),
            "position": float(p_info.get("position", 0.0) or 0.0),
            "hidden_at": round(time.time(), 2)
        }
        self.config_mgr.set("media_hub_hidden", hidden)
        self.toastMessage.emit(f"👁️ Hidden '{Path(norm).name}' from Media Hub until watch progress changes")
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    @Slot()
    def clearMediaHubHiddenItems(self):
        self.config_mgr.set("media_hub_hidden", {})
        self.mediaHubConfigChanged.emit()
        self.toastMessage.emit("✔ Restored all hidden Media Hub items")
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    @Slot(result=int)
    def getMediaHubHiddenCount(self) -> int:
        hidden = self.config_mgr.get("media_hub_hidden", {})
        return len(hidden) if isinstance(hidden, dict) else 0

    @Slot()
    def refreshMediaHub(self):
        # Do NOT emit mediaHubDataChanged before MediaHubBuilderTask finishes, to prevent QML full-window redraw flashing!
        if not self._media_hub_sections and not self._is_loading_media_hub:
            self._is_loading_media_hub = True
            self.mediaHubDataChanged.emit()
        task = MediaHubBuilderTask(self, self.signals)
        self.thread_pool.start(task)

    def _on_media_hub_sections_ready(self, sections: list):
        was_loading = self._is_loading_media_hub
        self._is_loading_media_hub = False
        old_len = len(self._media_hub_sections)
        self._media_hub_sections = sections

        # Update persistent QAbstractListModels in-place (Zero delegate destruction, zero poster flashing!)
        self.media_hub_model.sync_sections(sections)

        if was_loading or old_len != len(sections):
            self.mediaHubDataChanged.emit()

        if str(self._current_path) == "mediahub://":
            flat_entries = []
            seen = set()
            for sec in sections:
                for itm in sec.get("items", []):
                    p = itm.get("path", "")
                    if p and p not in seen:
                        seen.add(p)
                        flat_entries.append(itm)
            self.file_model.set_entries(flat_entries, context_key="mediahub://")

    def _load_media_hub_directory(self):
        self._current_path = "mediahub://"
        self.currentPathChanged.emit()
        self.breadcrumbsChanged.emit()
        self.mediaLibraryStateChanged.emit()
        self._selected_item = {}
        self._selected_paths = []
        self._last_selected_row = -1
        self.selectedItemChanged.emit()
        self.selectedPathsChanged.emit()
        self.refreshMediaHub()

    @Property(bool, notify=mediaLibraryStateChanged)
    def isMovieFolderView(self):
        _, is_mov = self._check_path_in_media_library(str(self._current_path))
        return is_mov

    @Property(bool, notify=showSubtitlesChanged)
    def showSubtitlesInMedia(self):
        return self._show_subtitles_in_media

    @Slot()
    def toggleSubtitlesInMedia(self):
        self._show_subtitles_in_media = not self._show_subtitles_in_media
        self.showSubtitlesChanged.emit()
        if self.isMediaLibraryView:
            self.refresh()

    @Slot(result=list)
    def getMediaLibraries(self):
        raw = self.config_mgr.get("media_libraries", [])
        out = []
        for item in raw:
            if isinstance(item, dict):
                out.append({
                    "name": item.get("name", Path(item.get("path", "")).name or "Library"),
                    "path": item.get("path", ""),
                    "mode": item.get("mode", "series")
                })
            elif isinstance(item, str) and item:
                out.append({"name": Path(item).name or item, "path": item, "mode": "series"})
        return out

    @Slot(str, str)
    def addMediaLibrary(self, folder_path: str, mode: str = "series"):
        if not folder_path:
            return
        norm_p = os.path.abspath(os.path.expanduser(folder_path))
        if not os.path.isdir(norm_p):
            return
        libs = self.getMediaLibraries()
        for entry in libs:
            if entry["path"] == norm_p:
                entry["mode"] = mode if mode in ("series", "movies") else "series"
                self.config_mgr.set("media_libraries", libs)
                self.mediaLibraryStateChanged.emit()
                self.mediaHubConfigChanged.emit()
                self.refresh()
                return
        libs.append({
            "name": Path(norm_p).name or norm_p,
            "path": norm_p,
            "mode": mode if mode in ("series", "movies") else "series"
        })
        self.config_mgr.set("media_libraries", libs)
        self.mediaLibraryStateChanged.emit()
        self.mediaHubConfigChanged.emit()
        self.refresh()

    @Slot(str)
    def removeMediaLibrary(self, folder_path: str):
        norm_p = os.path.abspath(os.path.expanduser(folder_path)) if folder_path else ""
        libs = [x for x in self.getMediaLibraries() if x["path"] != norm_p and x["path"] != folder_path]
        self.config_mgr.set("media_libraries", libs)
        self.mediaLibraryStateChanged.emit()
        self.mediaHubConfigChanged.emit()
        self.refresh()

    @Slot(str, str)
    def setMediaLibraryMode(self, folder_path: str, mode: str):
        libs = self.getMediaLibraries()
        for entry in libs:
            if entry["path"] == folder_path:
                entry["mode"] = mode if mode in ("series", "movies") else "series"
        self.config_mgr.set("media_libraries", libs)
        self.mediaLibraryStateChanged.emit()
        self.refresh()

    @Slot(str, result=bool)
    def isFolderMarkedAsMovie(self, folder_path: str) -> bool:
        if not folder_path:
            return False
        _, is_mov = self._check_path_in_media_library(folder_path)
        return is_mov

    @Slot(str)
    def toggleMovieFolderStatus(self, folder_path: str):
        if not folder_path:
            return
        norm_p = os.path.abspath(folder_path)
        movie_dirs = list(self.config_mgr.get("movie_folders", []))
        if norm_p in movie_dirs:
            movie_dirs.remove(norm_p)
        else:
            movie_dirs.append(norm_p)
            # Also ensure it's registered as a media library if not already inside one
            in_lib, _ = self._check_path_in_media_library(norm_p)
            if not in_lib:
                self.addMediaLibrary(norm_p, "movies")
        self.config_mgr.set("movie_folders", movie_dirs)
        self.mediaLibraryStateChanged.emit()
        self.refresh()

    @Slot(str, bool)
    def markMediaWatched(self, file_path_str: str, watched: bool):
        if not file_path_str:
            return
        targets = (
            list(self._selected_paths)
            if (file_path_str in self._selected_paths and len(self._selected_paths) > 1)
            else [file_path_str]
        )
        now_ts = time.time()
        for fp in targets:
            if not fp or not os.path.exists(fp) or os.path.isdir(fp):
                continue
            cur = self.config_mgr.get_media_progress(fp)
            dur = cur.get("duration", 100.0) or 100.0
            pos = 0.0
            updated = self.config_mgr.set_media_progress(fp, pos, dur, watched=watched, updated_at=now_ts)
            self.jf_bridge.update_local_cached_progress(fp, pos, dur, watched)
            self.file_model.update_media_progress(fp, updated["progress"], updated["watched"])
            if not self._anonymous_mode:
                self.jf_bridge.mark_watched_async(fp, watched, QThreadPool.globalInstance())

        for fp in targets:
            if fp and os.path.exists(fp) and not os.path.isdir(fp):
                p_info = self.config_mgr.get_media_progress(fp)
                self.media_hub_model.update_progress_in_place(fp, float(p_info.get("progress", 0.0)), bool(p_info.get("watched", False)))
        action_lbl = "Marked as Watched" if watched else "Reset watch progress"
        self.toastMessage.emit(f"✔ {action_lbl} ({len(targets)} item{'s' if len(targets) > 1 else ''})")
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    def _on_auto_jellyfin_poll(self):
        """Periodically polls Jellyfin in the background so external changes appear automatically."""
        if self._anonymous_mode or not self.jf_bridge.is_enabled or not self.isMediaLibraryView:
            return
        cur_p = str(self._current_path)
        if cur_p == "mediahub://":
            return
        if cur_p in ("recent://", "trash://", "favorites://") or not os.path.isdir(cur_p):
            return
        total = self.file_model.rowCount()
        if total <= 0:
            return
        entries_snapshot = []
        for r in range(total):
            ent = self.file_model.get_entry_at(r)
            if ent:
                entries_snapshot.append(dict(ent))
        if entries_snapshot:
            jf_task = JellyfinFolderSyncTask(self.jf_bridge, cur_p, entries_snapshot, self.jf_signals)
            self.thread_pool.start(jf_task)

    @Slot()
    def syncJellyfinAndRefresh(self):
        """Fast shortcut (Ctrl+R) to force-sync Jellyfin and refresh Find immediately."""
        self.config_mgr.reload_progress_from_disk()
        if self.jf_bridge.is_enabled:
            self.jf_bridge._server_online = True
            self.jf_bridge._last_fail_ts = 0.0
            self.toastMessage.emit("🔄 Syncing latest progress & metadata with Jellyfin...")
        else:
            self.toastMessage.emit("⟳ Refreshed folder")
        self.refresh()

    # ==========================================================================
    # Jellyfin Server Settings & Metadata Sync
    # ==========================================================================

    @Property(bool, notify=jellyfinConfigChanged)
    def jellyfinEnabled(self) -> bool:
        return bool(self.config_mgr.get("jellyfin_enabled", True))

    @Property(str, notify=jellyfinConfigChanged)
    def jellyfinUrl(self) -> str:
        return str(self.config_mgr.get("jellyfin_url", "http://localhost:8096"))

    @Property(str, notify=jellyfinConfigChanged)
    def jellyfinToken(self) -> str:
        return str(self.config_mgr.get("jellyfin_token", ""))

    @Property(bool, notify=jellyfinConfigChanged)
    def jellyfinStreamMode(self) -> bool:
        return bool(self.config_mgr.get("jellyfin_stream_mode", False))

    @Property(bool, notify=jellyfinConfigChanged)
    def showSeriesPosters(self) -> bool:
        return bool(self.config_mgr.get("show_series_posters", True))

    @Slot(bool)
    def setShowSeriesPosters(self, enabled: bool):
        if bool(self.config_mgr.get("show_series_posters", True)) != bool(enabled):
            self.config_mgr.set("show_series_posters", bool(enabled))
            self.jellyfinConfigChanged.emit()

    @Slot(bool, str, str, bool)
    def saveJellyfinConfig(self, enabled: bool, url: str, token: str, stream_mode: bool):
        self.config_mgr.set("jellyfin_enabled", bool(enabled))
        self.config_mgr.set("jellyfin_url", url.strip().rstrip("/"))
        self.config_mgr.set("jellyfin_token", token.strip())
        self.config_mgr.set("jellyfin_stream_mode", bool(stream_mode))
        self.jellyfinConfigChanged.emit()
        self.toastMessage.emit("✔ Saved Jellyfin settings")
        if self.isMediaLibraryView:
            self.refresh()

    @Slot(str, str, result=str)
    def testJellyfinConnection(self, url: str, token: str) -> str:
        ok, msg = self.jf_bridge.test_connection_sync(url, token)
        self.jellyfinConfigChanged.emit()
        self.toastMessage.emit(msg)
        if ok and self.isMediaLibraryView:
            self.refresh()
        return msg

    def _on_jellyfin_folder_metadata_ready(self, folder_path: str, meta_map: dict):
        for fpath, meta in meta_map.items():
            self.media_hub_model.update_jellyfin_in_place(fpath, meta)
        if str(self._current_path) != folder_path:
            return
        self.mediaLibraryStateChanged.emit()
        for fpath, meta in meta_map.items():
            self.file_model.update_jellyfin_metadata(
                fpath,
                meta.get("title", ""),
                meta.get("overview", ""),
                meta.get("progress"),
                meta.get("watched"),
                meta.get("rating"),
                meta.get("poster", "")
            )
            if self._selected_item.get("path") == fpath:
                updated = dict(self._selected_item)
                if meta.get("title"):
                    updated["episode_title"] = meta["title"]
                if meta.get("overview"):
                    updated["overview"] = meta["overview"]
                if meta.get("rating"):
                    updated["rating"] = str(meta["rating"])
                if meta.get("poster"):
                    updated["poster"] = meta["poster"]
                self._selected_item = updated
                self.selectedItemChanged.emit()

    def _on_mpv_progress_updated(self, file_path_str: str, pos: float, duration: float, is_done: bool):
        if self._anonymous_mode:
            return
        updated = self.config_mgr.set_media_progress(file_path_str, pos, duration, watched=is_done)
        self.jf_bridge.update_local_cached_progress(file_path_str, pos, duration, updated["watched"])
        self.file_model.update_media_progress(file_path_str, updated["progress"], updated["watched"])
        self.media_hub_model.update_progress_in_place(file_path_str, updated["progress"], updated["watched"])

    def _on_mpv_external_sub_detected(self, file_path_str: str, sub_path_str: str):
        if self._anonymous_mode:
            return
        self.config_mgr.set_media_external_sub(file_path_str, sub_path_str)

    @Slot(str)
    def clearMediaEntryCache(self, target_path_str: str):
        if not target_path_str or not os.path.exists(target_path_str):
            return
        norm_p = os.path.abspath(target_path_str)
        self.thumb_mgr.remove_thumbnail_for_path(norm_p)
        prefix = norm_p.rstrip(os.sep) + os.sep
        for k in list(self.thumb_mgr.folder_cache.keys()):
            if k == norm_p or k.startswith(prefix):
                self.thumb_mgr.folder_cache.pop(k, None)
        for k in list(self.thumb_mgr.requested):
            if k == norm_p or k.startswith(prefix):
                self.thumb_mgr.requested.discard(k)
        for k in list(self.thumb_mgr.requested_folders):
            if k == norm_p or k.startswith(prefix):
                self.thumb_mgr.requested_folders.discard(k)
        for k in list(self.config_mgr._hdr_cache.keys()):
            if k == norm_p or k.startswith(prefix):
                self.config_mgr._hdr_cache.pop(k, None)
        self.config_mgr.save_hdr_cache()
        self.jf_bridge.clear_cache_for_path(norm_p)
        self.cacheSizeChanged.emit()
        self.toastMessage.emit(f"🧹 Cleared local cache for '{Path(norm_p).name}' — Refreshing from server...")
        self.syncJellyfinAndRefresh()

    def _on_mpv_hdr_session_ended(self, pid: int):
        self._active_hdr_pids.discard(pid)
        if not self._active_hdr_pids:
            _run_toggle_hdr_script("--off")

    def _write_system_mpv_conf(self, hdr_mode: bool = False) -> str:
        """
        Completely replaces ~/.config/mpv/mpv.conf by merging:
        1) 'Both' (Shared Base & Subtitles)
        2) 'SDR' (when hdr_mode=False) OR 'HDR' (when hdr_mode=True)
        Any key redefined in SDR or HDR cleanly overrides the key from 'Both'!
        """
        shader_cache = self.config_mgr.cache_dir / "mpv_shaders"
        shader_cache.mkdir(parents=True, exist_ok=True)
        fonts_dir = str(Path.home() / ".local" / "share" / "fonts")

        def _format_vars(text: str) -> str:
            return text.replace("{shader_cache}", str(shader_cache)).replace("{fonts_dir}", fonts_dir)

        both_raw = _format_vars(self.getMpvBothConfig())
        mode_raw = _format_vars(self.getMpvHdrConfig() if hdr_mode else self.getMpvSdrConfig())

        def _normalize_key(k: str) -> str:
            return k.strip().replace("_", "-")

        mode_lines = []
        overridden_keys = set()
        for raw_ln in mode_raw.splitlines():
            ln = raw_ln.strip()
            if not ln or ln.startswith("#"):
                continue
            if "=" in ln and not ln.startswith("["):
                k = _normalize_key(ln.split("=", 1)[0])
                overridden_keys.add(k)
            mode_lines.append(ln)

        final_lines = []
        seen_both_keys = set()
        for raw_ln in both_raw.splitlines():
            ln = raw_ln.strip()
            if not ln or ln.startswith("#"):
                continue
            if ln in ("input-default-bindings=no", "input_default_bindings=no"):
                ln = "input-default-bindings=yes"
            elif ln in ("input-vo-keyboard=no", "input_vo_keyboard=no"):
                ln = "input-vo-keyboard=yes"

            if "=" in ln and not ln.startswith("["):
                k = _normalize_key(ln.split("=", 1)[0])
                seen_both_keys.add(k)
                if k in overridden_keys:
                    continue
            final_lines.append(ln)

        all_keys = seen_both_keys | overridden_keys
        if "input-default-bindings" not in all_keys:
            final_lines.append("input-default-bindings=yes")
        if "input-vo-keyboard" not in all_keys:
            final_lines.append("input-vo-keyboard=yes")
        if "save-position-on-quit" not in all_keys:
            final_lines.append("save-position-on-quit=yes")
        if "osd-on-seek" not in all_keys:
            final_lines.append("osd-on-seek=no")

        if mode_lines:
            final_lines.append("")
            final_lines.extend(mode_lines)

        find_mpv_conf = self.config_mgr.config_dir / "mpv_find.conf"
        try:
            with open(find_mpv_conf, "w", encoding="utf-8") as f:
                f.write("\n".join(final_lines) + "\n")
        except Exception:
            pass
        return str(find_mpv_conf)

    def _launch_in_mpv_with_tracking(self, file_path_str: str, hdr_mode: bool = None):
        ordered_videos = []
        abs_clicked = os.path.abspath(file_path_str)
        cur_p_str = str(self._current_path)
        if cur_p_str not in ("mediahub://", "favorites://", "recent://") and not cur_p_str.startswith("analyzer://"):
            total_rows = self.file_model.rowCount()
            for r in range(total_rows):
                ent = self.file_model.get_entry_at(r)
                if ent and not ent.get("is_dir") and Path(ent["name"]).suffix.lower() in VIDEO_EXTS:
                    ordered_videos.append(os.path.abspath(ent["path"]))

        def _worker():
            use_hdr = hdr_mode
            if use_hdr is None:
                use_hdr = False
                in_lib, _ = self._check_path_in_media_library(abs_clicked)
                if in_lib and self._auto_play_hdr:
                    try:
                        mtime = os.path.getmtime(abs_clicked)
                        cached_hdr = self.config_mgr.get_cached_hdr(abs_clicked, mtime)
                        if cached_hdr is None:
                            cached_hdr = detect_video_hdr_sync(abs_clicked)
                            self.config_mgr.set_cached_hdr(abs_clicked, mtime, cached_hdr)
                            self.signals.hdrStatusDetected.emit(abs_clicked, cached_hdr)
                        use_hdr = bool(cached_hdr)
                    except Exception:
                        use_hdr = False

            if use_hdr:
                _run_toggle_hdr_script("--on")

            rt_dir = _get_secure_runtime_dir()
            base_id = f"find_mpv_{os.getpid()}_{int(time.time() * 1000)}"
            sock_path = str(rt_dir / f"{base_id}.sock")
            meta_path = str(rt_dir / f"{base_id}.json")
            conf_file = self._write_system_mpv_conf(hdr_mode=bool(use_hdr))
            saved = dict(self.config_mgr.get_media_progress(abs_clicked))

            if saved.get("watched", False):
                try:
                    md5_hex = hashlib.md5(abs_clicked.encode("utf-8")).hexdigest().upper()
                    for wl_f in (
                        Path.home() / ".local" / "state" / "mpv" / "watch_later" / md5_hex,
                        Path.home() / ".config" / "mpv" / "watch_later" / md5_hex,
                    ):
                        if wl_f.exists():
                            wl_f.unlink()
                except Exception:
                    pass

            jf_session_meta = {}
            if self.jf_bridge.is_enabled and not self._anonymous_mode:
                jf_session_meta = self.jf_bridge.resolve_item_for_playback_sync(abs_clicked)
                if jf_session_meta:
                    local_pos = float(saved.get("position", 0.0) or 0.0)
                    srv_pos = float(jf_session_meta.get("position", 0.0) or 0.0)
                    if srv_pos > local_pos and not jf_session_meta.get("watched", False) and not saved.get("watched", False):
                        saved["position"] = srv_pos
            elif self._anonymous_mode:
                cached_local_jf = self.jf_bridge.get_cached_item(abs_clicked)
                if cached_local_jf and cached_local_jf.get("chapters"):
                    jf_session_meta = {"chapters": cached_local_jf.get("chapters", []), "title": cached_local_jf.get("title", "")}

            initial_pos = 0.0
            if not saved.get("watched", False) and saved.get("position", 0.0) > 5.0:
                initial_pos = float(saved["position"])

            cmd = [
                "mpv",
                f"--include={conf_file}",
                f"--input-ipc-server={sock_path}",
                "--no-resume-playback"
            ]
            if self._mpv_auto_fullscreen:
                cmd.append("--fs")
            if self._anonymous_mode:
                cmd.append("--no-save-position-on-quit")
            loaded_initial_subs = set()
            ext_sub = saved.get("ext_sub", "")
            if ext_sub and os.path.exists(ext_sub):
                cmd.append(f"--sub-file={ext_sub}")
                loaded_initial_subs.add(os.path.abspath(ext_sub))
            for auto_sub in find_matching_external_subs_for_video(abs_clicked):
                if auto_sub not in loaded_initial_subs:
                    cmd.append(f"--sub-file={auto_sub}")
                    loaded_initial_subs.add(auto_sub)

            vids = list(ordered_videos)
            if abs_clicked not in vids:
                parent_d = os.path.dirname(abs_clicked)
                try:
                    siblings = [
                        os.path.join(parent_d, fn)
                        for fn in os.listdir(parent_d)
                        if Path(fn).suffix.lower() in VIDEO_EXTS and not fn.startswith(".")
                    ]
                    siblings.sort(key=lambda p: [int(c) if c.isdecimal() else c for c in re.split(r'(\d+)', os.path.basename(p).lower())])
                    vids = siblings if abs_clicked in siblings else [abs_clicked]
                except Exception:
                    vids = [abs_clicked]

            playlist_m3u_or_file, start_idx, stream_to_local = self.jf_bridge.build_playlist_for_folder(
                abs_clicked,
                vids,
                base_id=base_id
            )
            if str(playlist_m3u_or_file).endswith(".m3u8"):
                cmd.append(f"--playlist={playlist_m3u_or_file}")
                cmd.append(f"--playlist-start={start_idx}")
            else:
                if initial_pos > 5.0:
                    cmd.append(f"--start={initial_pos:.2f}")
                cmd.append(playlist_m3u_or_file)

            self._ensure_media_daemon_running()

            try:
                with open(meta_path, "w", encoding="utf-8") as mf:
                    json.dump({
                        "file_path": abs_clicked,
                        "playlist_file": playlist_m3u_or_file if str(playlist_m3u_or_file).endswith(".m3u8") else "",
                        "hdr_mode": bool(use_hdr),
                        "initial_pos": initial_pos,
                        "initial_seek_done": False,
                        "anonymous_mode": bool(self._anonymous_mode),
                        "jellyfin": {} if self._anonymous_mode else jf_session_meta,
                        "stream_to_local": stream_to_local
                    }, mf)
                try:
                    os.chmod(meta_path, 0o600)
                except OSError:
                    pass
            except Exception:
                pass

            proc = subprocess.Popen(
                cmd,
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )

            # Always run the in-app MPV session monitor alongside the daemon so progress & resume never fail!
            if use_hdr:
                self._active_hdr_pids.add(int(proc.pid))
            monitor = MpvSessionMonitorTask(
                abs_clicked,
                sock_path,
                proc,
                bool(use_hdr),
                initial_pos,
                self.config_mgr.get_media_progress,
                self.signals,
                jf_session_meta,
                stream_to_local
            )
            QThreadPool.globalInstance().start(monitor)

        QThreadPool.globalInstance().start(_worker)

    def _tab_title_for_path(self, path_str: str) -> str:
        if path_str.startswith("analyzer://"):
            sub_p = path_str[11:] or "/"
            name = "Root /" if sub_p == "/" else (Path(sub_p).name or sub_p)
            return f"📊 {name}"
        if path_str == "mediahub://":
            return "Media Hub"
        if path_str == "favorites://":
            return "Favorites"
        if path_str == "recent://":
            return "Recently Added"
        if path_str == "trash://":
            return "Trash"
        if path_str == str(Path.home()):
            return "Home"
        if path_str == "/":
            return "Root /"
        name = Path(path_str).name
        return name if name else path_str

    def _save_session_state(self):
        if getattr(self, "_launched_as_picker", False) or getattr(self, "_launched_as_mediahub", False):
            return
        serialized_tabs = []
        for t in self._tabs:
            serialized_tabs.append({
                "path": t.get("path", str(Path.home())),
                "title": t.get("title", "Home")
            })
        self.config_mgr.set("last_session", {
            "tabs": serialized_tabs,
            "active_index": self._active_tab_index
        })

    def _sync_current_tab_state(self):
        if 0 <= self._active_tab_index < len(self._tabs):
            tab = self._tabs[self._active_tab_index]
            tab["path"] = str(self._current_path)
            tab["title"] = self._tab_title_for_path(str(self._current_path))
            tab["history"] = list(self._history)
            tab["history_idx"] = self._history_idx
            self._save_session_state()
            self.tabsChanged.emit()

    @Property(list, notify=tabsChanged)
    def tabs(self):
        out = []
        for idx, t in enumerate(self._tabs):
            out.append({
                "index": idx,
                "title": t["title"],
                "path": t["path"],
                "active": idx == self._active_tab_index
            })
        return out

    @Property(int, notify=tabsChanged)
    def activeTabIndex(self):
        return self._active_tab_index

    @Slot()
    @Slot(str)
    def addTab(self, path_str: str = ""):
        target = path_str if path_str else str(self._current_path)
        if target not in ("recent://", "trash://", "favorites://", "mediahub://") and not target.startswith("analyzer://"):
            target = os.path.expanduser(os.path.expandvars(target))
            if target.startswith("file://"):
                target = QUrl(target).toLocalFile() or target[7:]
            target = os.path.abspath(target)
            if not os.path.exists(target) or not os.path.isdir(target):
                target = str(Path.home())

        self._sync_current_tab_state()
        new_tab = {
            "path": target,
            "title": self._tab_title_for_path(target),
            "history": [target],
            "history_idx": 0
        }
        self._tabs.append(new_tab)
        self._active_tab_index = len(self._tabs) - 1
        self._history = list(new_tab["history"])
        self._history_idx = 0
        self.load_directory(target)
        self._update_history_state()
        self.tabsChanged.emit()

    @Slot(int)
    def switchTab(self, index: int):
        if not (0 <= index < len(self._tabs)) or index == self._active_tab_index:
            return
        self._sync_current_tab_state()
        self._active_tab_index = index
        tab = self._tabs[index]
        self._history = list(tab["history"])
        self._history_idx = tab["history_idx"]
        self.load_directory(tab["path"])
        self._update_history_state()
        self.tabsChanged.emit()

    @Slot(int)
    def closeTab(self, index: int):
        if len(self._tabs) <= 1:
            self.navigateTo(str(Path.home()))
            return
        if not (0 <= index < len(self._tabs)):
            return
        self._tabs.pop(index)
        if self._active_tab_index >= len(self._tabs):
            self._active_tab_index = len(self._tabs) - 1
        elif index < self._active_tab_index:
            self._active_tab_index -= 1

        tab = self._tabs[self._active_tab_index]
        self._history = list(tab["history"])
        self._history_idx = tab["history_idx"]
        self.load_directory(tab["path"])
        self._update_history_state()
        self.tabsChanged.emit()

    @Slot()
    def nextTab(self):
        if len(self._tabs) > 1:
            self.switchTab((self._active_tab_index + 1) % len(self._tabs))

    @Slot(int, int)
    def moveTab(self, from_idx: int, to_idx: int):
        if not (0 <= from_idx < len(self._tabs)) or not (0 <= to_idx < len(self._tabs)):
            return
        if from_idx == to_idx:
            return
        self._sync_current_tab_state()
        item = self._tabs.pop(from_idx)
        self._tabs.insert(to_idx, item)
        if self._active_tab_index == from_idx:
            self._active_tab_index = to_idx
        elif from_idx < self._active_tab_index <= to_idx:
            self._active_tab_index -= 1
        elif to_idx <= self._active_tab_index < from_idx:
            self._active_tab_index += 1
        self.tabsChanged.emit()

    @Slot(int)
    def detachTabToNewWindow(self, index: int):
        if not (0 <= index < len(self._tabs)):
            return
        target_path = self._tabs[index].get("path", str(Path.home()))
        if target_path in ("recent://", "trash://"):
            target_path = str(Path.home())
        main_script = Path(__file__).resolve().parent.parent / "main.py"
        cmd_detach = [sys.executable, target_path] if getattr(sys, "frozen", False) else [sys.executable, str(main_script), target_path]
        try:
            subprocess.Popen(
                cmd_detach,
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            if len(self._tabs) > 1:
                self.closeTab(index)
        except Exception:
            pass

    @Slot(str, str, str)
    def startSystemDrag(self, file_path_str: str, display_name: str = "", icon_glyph: str = "📄"):
        try:
            p = Path(file_path_str)
            if not p.exists():
                return
            targets = list(self._selected_paths) if (file_path_str in self._selected_paths and len(self._selected_paths) > 1) else [file_path_str]
            valid_paths = [Path(fp).resolve() for fp in targets if os.path.exists(fp)]
            if not valid_paths:
                return

            drag = QDrag(self)
            mime = QMimeData()
            urls = [QUrl.fromLocalFile(str(vp)) for vp in valid_paths]
            mime.setUrls(urls)
            mime.setText("\n".join(str(vp) for vp in valid_paths))
            drag.setMimeData(mime)

            # Render a clean native drag badge pixmap so external apps & Wayland compositor show it
            label = f"{len(valid_paths)} items selected" if len(valid_paths) > 1 else (display_name if display_name else p.name)
            if len(label) > 26:
                label = label[:23] + "..."
            pm = QPixmap(220, 38)
            pm.fill(Qt.GlobalColor.transparent)
            painter = QPainter(pm)
            painter.setRenderHint(QPainter.RenderHint.Antialiasing)
            painter.setBrush(QColor(30, 30, 36, 235))
            painter.setPen(QColor(0, 120, 212))
            painter.drawRoundedRect(1, 1, 218, 36, 8, 8)
            painter.setPen(QColor(248, 250, 252))
            font = QFont()
            font.setPixelSize(13)
            font.setBold(True)
            painter.setFont(font)
            painter.drawText(12, 24, f"{icon_glyph}  {label}")
            painter.end()
            drag.setPixmap(pm)
            drag.setHotSpot(pm.rect().topLeft())

            drag.exec(Qt.DropAction.CopyAction | Qt.DropAction.MoveAction | Qt.DropAction.LinkAction)
        except Exception:
            pass

    @Slot(list, str, result=list)
    def filterValidDropSources(self, urls_list: list, dest_dir_str: str) -> list:
        """Filters out any source files that already reside directly inside dest_dir_str."""
        if not dest_dir_str or dest_dir_str in ("recent://", "trash://"):
            return []
        try:
            dest_resolved = os.path.abspath(dest_dir_str)
        except Exception:
            return []

        valid = []
        for raw_u in urls_list:
            u = str(raw_u).strip()
            if not u:
                continue
            if u.startswith("file://"):
                u = QUrl(u).toLocalFile() or u[7:]
            if not u or not os.path.exists(u):
                continue
            src_abs = os.path.abspath(u)
            src_parent = os.path.dirname(src_abs)
            # Ignore dropping an item into its own current parent directory or onto itself
            if src_abs == dest_resolved or src_parent == dest_resolved:
                continue
            # Ignore dropping a parent folder into its own subfolder
            if dest_resolved.startswith(src_abs.rstrip(os.sep) + os.sep):
                continue
            if src_abs not in valid:
                valid.append(src_abs)
        return valid

    @Property(bool, notify=transparentBlurChanged)
    def transparentBlur(self):
        return self._transparent_blur

    @transparentBlur.setter
    def transparentBlur(self, val: bool):
        if self._transparent_blur != val:
            self._transparent_blur = val
            self.config_mgr.set("transparent_blur", val)
            self.transparentBlurChanged.emit()

    @Property(list, notify=breadcrumbsChanged)
    def breadcrumbs(self):
        if str(self._current_path).startswith("analyzer://"):
            real_p = str(self._current_path)[11:] or "/"
            parts = []
            try:
                p = Path(real_p)
                full = list(reversed(p.parents)) + [p]
                for idx, item in enumerate(full):
                    nm = item.name if item.name else "/"
                    if idx == 0:
                        nm = "📊 Root" if nm == "/" else f"📊 {nm}"
                    parts.append({"name": nm, "path": f"analyzer://{str(item)}"})
            except Exception:
                parts = [{"name": f"📊 {real_p}", "path": str(self._current_path)}]
            return parts
        if str(self._current_path) == "mediahub://":
            return [{"name": "🎬 Media Hub", "path": "mediahub://"}]
        if str(self._current_path) == "favorites://":
            return [{"name": "⭐ Favorites", "path": "favorites://"}]
        if str(self._current_path) == "recent://":
            return [{"name": "Recently Added", "path": "recent://"}]
        if str(self._current_path) == "trash://":
            return [{"name": "Trash (All Drives)", "path": "trash://"}]

        parts = []
        try:
            p = Path(self._current_path)
            parents = list(reversed(p.parents))
            full = parents + [p]

            for item in full:
                name = item.name if item.name else "/"
                if str(item) == str(Path.home()):
                    name = "Home"
                elif str(item) == self.trashPath:
                    name = "Trash"
                parts.append({"name": name, "path": str(item)})
        except Exception:
            parts = [{"name": str(self._current_path), "path": str(self._current_path)}]
        return parts

    @Property(bool, notify=canGoBackChanged)
    def canGoBack(self):
        return self._history_idx > 0

    @Property(bool, notify=canGoForwardChanged)
    def canGoForward(self):
        return self._history_idx < len(self._history) - 1

    @Property(str, notify=viewModeChanged)
    def viewMode(self):
        return self._view_mode

    @viewMode.setter
    def viewMode(self, mode: str):
        if self._view_mode != mode and mode in ("details", "grid"):
            self._view_mode = mode
            self.config_mgr.set_folder_view(str(self._current_path), self._view_mode, self._sort_by, self._sort_ascending)
            self.viewModeChanged.emit()

    @Property(int, notify=gridColumnsChanged)
    def gridColumns(self):
        return self._grid_columns

    @gridColumns.setter
    def gridColumns(self, cols: int):
        if self._grid_columns != cols:
            self._grid_columns = cols
            self.config_mgr.set("grid_columns", cols)
            self.gridColumnsChanged.emit()

    @Property(str, notify=gridStyleChanged)
    def gridStyle(self):
        return self._grid_style

    @gridStyle.setter
    def gridStyle(self, style: str):
        if self._grid_style != style and style in ("floating", "cards"):
            self._grid_style = style
            self.config_mgr.set("grid_style", style)
            self.gridStyleChanged.emit()

    @Property(str, notify=sidebarModeChanged)
    def sidebarMode(self):
        return self._sidebar_mode

    @sidebarMode.setter
    def sidebarMode(self, mode: str):
        if self._sidebar_mode != mode and mode in ("auto", "full", "rail", "topbar"):
            self._sidebar_mode = mode
            self.config_mgr.set("sidebar_mode", mode)
            self.sidebarModeChanged.emit()

    @Property(str, notify=sortByChanged)
    def sortBy(self):
        return self._sort_by

    @Property(bool, notify=sortOrderChanged)
    def sortAscending(self):
        return self._sort_ascending

    @Property(dict, notify=selectedItemChanged)
    def selectedItem(self):
        return self._selected_item

    @Property(list, notify=selectedPathsChanged)
    def selectedPaths(self):
        return self._selected_paths

    @Property(list, notify=searchResultsChanged)
    def searchResults(self):
        return self._search_results

    @Property(str, notify=cacheSizeChanged)
    def currentCacheSize(self):
        return self._format_size(self.config_mgr.get_cache_size_bytes())

    @Property(int, notify=maxCacheMbChanged)
    def maxCacheMb(self):
        return self.config_mgr.get("max_cache_mb", 500)

    @Property(QObject, constant=True)
    def files(self):
        return self.file_model

    def _run_bg_task(self, fn):
        task = CallableTask(fn, on_done=lambda t: self._active_bg_tasks.discard(t))
        self._active_bg_tasks.add(task)
        self.thread_pool.start(task)

    def _trigger_immediate_refresh(self):
        self.refresh()
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    def _on_dir_changed_externally(self, path):
        if path == str(self._current_path):
            self._dir_reload_debounce.start()

    def _on_thumbnail_ready(self, file_path, thumb_path):
        self.file_model.update_thumbnail(file_path, thumb_path)
        self.media_hub_model.update_thumbnail_in_place(file_path, thumb_path)
        if self._selected_item.get("path") == file_path:
            self._selected_item["thumb"] = thumb_path
            self.selectedItemChanged.emit()

    def _on_folder_preview_ready(self, folder_path, previews):
        self.file_model.update_folder_previews(folder_path, previews)
        self.media_hub_model.update_folder_previews_in_place(folder_path, previews)
        if self._selected_item.get("path") == folder_path:
            self._selected_item["folder_previews"] = previews
            self.selectedItemChanged.emit()

    def _on_search_results_ready(self, results):
        self._search_results = results
        self.searchResultsChanged.emit()

    def _update_history_state(self):
        self.canGoBackChanged.emit()
        self.canGoForwardChanged.emit()

    def _determine_icon_and_type(self, path_obj: Path, is_dir: bool):
        defaults = self.config_mgr.get("default_type_icons", {})
        if path_obj.is_symlink():
            return "🔗", "Symbolic Link"
        if is_dir:
            return defaults.get("folder", "📁"), "Folder"

        suffix = path_obj.suffix.lower()
        if suffix == ".py":
            return defaults.get("py", "🐍"), "Python Script"
        if suffix == ".rs":
            return defaults.get("rs", "🦀"), "Rust Source"
        if suffix == ".json":
            return defaults.get("json", "📋"), "JSON Document"
        if suffix in IMAGE_EXTS:
            return defaults.get("image", "🖼️"), "Image"
        if suffix in VIDEO_EXTS:
            return defaults.get("video", "🎬"), "Video"
        if suffix in {".mp3", ".flac", ".wav", ".ogg", ".m4a", ".aac"}:
            return defaults.get("audio", "🎵"), "Audio"
        if suffix in {".zip", ".tar", ".gz", ".xz", ".7z", ".rar"}:
            return defaults.get("archive", "📦"), "Archive"

        return defaults.get("file", "📄"), "File"

    def _get_indexable_roots(self):
        roots = [str(Path.home())]
        for d in self.getDrives():
            mp = d.get("path", "")
            if mp and mp != "/" and os.path.exists(mp) and mp not in roots:
                roots.append(mp)
        return roots

    def _get_all_trash_dirs(self):
        uid = os.getuid()
        xdg_data = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))
        home_trash = os.path.join(xdg_data, "Trash", "files")
        os.makedirs(home_trash, exist_ok=True)
        trash_dirs = [str(Path(home_trash).resolve())]

        for d in self.getDrives():
            mp = d.get("path", "")
            if not mp or mp == "/":
                continue
            candidates = [
                os.path.join(mp, f".Trash-{uid}", "files"),
                os.path.join(mp, ".Trash", str(uid), "files"),
            ]
            for c in candidates:
                if os.path.isdir(c):
                    rc = str(Path(c).resolve())
                    if rc not in trash_dirs:
                        trash_dirs.append(rc)
        return trash_dirs

    def _apply_saved_view_for_path(self, target_key: str, default_view_override: str = None):
        """Restores the exact saved viewMode, sortBy, and sortAscending for target_key without polluting other folders."""
        fv = self.config_mgr.get_folder_view(target_key)
        if not fv and target_key not in ("favorites://", "recent://", "trash://"):
            views = self.config_mgr.get("folder_views", {})
            try:
                for ancestor in Path(target_key).parents:
                    anc_str = str(ancestor)
                    if anc_str in views and views[anc_str].get("cascade"):
                        fv = views[anc_str]
                        break
            except Exception:
                pass

        fallback_vm = default_view_override if default_view_override else self._default_view_mode
        new_vm = fv.get("view_mode", fallback_vm) if fv else fallback_vm
        new_sb = fv.get("sort_by", self._default_sort_by) if fv else self._default_sort_by
        new_sa = fv.get("sort_ascending", self._default_sort_ascending) if fv else self._default_sort_ascending

        if self._view_mode != new_vm:
            self._view_mode = new_vm
            self.viewModeChanged.emit()
        if self._sort_by != new_sb:
            self._sort_by = new_sb
            self.sortByChanged.emit()
        if self._sort_ascending != new_sa:
            self._sort_ascending = new_sa
            self.sortOrderChanged.emit()

    def _load_trash_directory(self):
        self._current_path = "trash://"
        self.currentPathChanged.emit()
        self.breadcrumbsChanged.emit()
        self.mediaLibraryStateChanged.emit()
        self._apply_saved_view_for_path("trash://", default_view_override="details")

        entries = []
        seen_paths = set()
        for t_dir in self._get_all_trash_dirs():
            try:
                with os.scandir(t_dir) as it:
                    for entry in it:
                        if not self._show_hidden and entry.name.startswith("."):
                            continue
                        if entry.path in seen_paths:
                            continue
                        seen_paths.add(entry.path)
                        try:
                            is_dir = entry.is_dir(follow_symlinks=False)
                        except OSError:
                            is_dir = False

                        raw_size = 0
                        raw_mod = 0
                        raw_created = 0
                        size_str = "-"
                        mod_str = "-"
                        created_str = "-"
                        try:
                            st = entry.stat(follow_symlinks=False)
                            raw_mod = st.st_mtime
                            mod_str = datetime.fromtimestamp(raw_mod).strftime("%Y-%m-%d %H:%M")
                            raw_created = getattr(st, "st_birthtime", st.st_ctime)
                            created_str = datetime.fromtimestamp(raw_created).strftime("%Y-%m-%d %H:%M")
                            if not is_dir:
                                raw_size = max(0, int(st.st_size))
                                size_str = self._format_size(raw_size)
                        except OSError:
                            pass

                        icon, file_type = self._determine_icon_and_type(Path(entry.path), is_dir)
                        existing_thumb = self.thumb_mgr.get_existing_thumbnail(entry.path) if not is_dir else ""
                        folder_previews = self.thumb_mgr.get_cached_folder_preview(entry.path) if is_dir else []

                        entries.append({
                            "name": entry.name,
                            "path": entry.path,
                            "is_dir": is_dir,
                            "size": size_str,
                            "modified": mod_str,
                            "created": created_str,
                            "icon": icon,
                            "type": file_type,
                            "raw_size": raw_size,
                            "raw_mod": raw_mod,
                            "raw_created": raw_created,
                            "thumb": existing_thumb,
                            "folder_previews": folder_previews
                        })
            except OSError:
                pass

        self._sort_entries(entries)
        self.file_model.set_entries(entries, context_key="trash://")
        surviving = [p for p in self._selected_paths if self.file_model.get_row_for_path(p) >= 0]
        if surviving != self._selected_paths:
            self._selected_paths = surviving
            if not surviving:
                self._selected_item = {}
                self._last_selected_row = -1
            self.selectedItemChanged.emit()
            self.selectedPathsChanged.emit()

        self._trash_item_count = len(entries)
        self._trash_total_size_str = "Calculating..." if entries else "0 B"
        self.trashInfoChanged.emit()
        if entries:
            t_task = TrashSizeTask(self._get_all_trash_dirs(), self.signals)
            self.thread_pool.start(t_task)

    def _load_favorites_directory(self):
        self._current_path = "favorites://"
        self.currentPathChanged.emit()
        self.breadcrumbsChanged.emit()
        self.mediaLibraryStateChanged.emit()
        self._apply_saved_view_for_path("favorites://", default_view_override="details")

        fav_items = self.getFavorites()
        entries = []
        for item in fav_items:
            p_str = item.get("path", "")
            if not p_str or not os.path.exists(p_str):
                continue
            p_obj = Path(p_str)
            is_dir = p_obj.is_dir()
            raw_size = 0
            raw_mod = 0
            raw_created = 0
            size_str = "-"
            mod_str = "-"
            created_str = "-"
            try:
                st = p_obj.stat()
                raw_mod = st.st_mtime
                mod_str = datetime.fromtimestamp(raw_mod).strftime("%Y-%m-%d %H:%M")
                raw_created = getattr(st, "st_birthtime", st.st_ctime)
                created_str = datetime.fromtimestamp(raw_created).strftime("%Y-%m-%d %H:%M")
                if not is_dir:
                    raw_size = max(0, int(st.st_size))
                    size_str = self._format_size(raw_size)
                else:
                    cached_sz = self._folder_size_cache.get(p_str)
                    if cached_sz is not None:
                        raw_size = cached_sz
                        size_str = self._format_size(cached_sz)
            except OSError:
                pass

            icon, file_type = self._determine_icon_and_type(p_obj, is_dir)
            existing_thumb = self.thumb_mgr.get_existing_thumbnail(p_str) if not is_dir else ""
            folder_previews = self.thumb_mgr.get_cached_folder_preview(p_str) if is_dir else []

            entries.append({
                "name": item.get("name", p_obj.name or p_str),
                "path": p_str,
                "is_dir": is_dir,
                "size": size_str,
                "modified": mod_str,
                "created": created_str,
                "icon": icon,
                "type": file_type,
                "raw_size": raw_size,
                "raw_mod": raw_mod,
                "raw_created": raw_created,
                "thumb": existing_thumb,
                "folder_previews": folder_previews,
                "episode_num": "",
                "progress": 0.0,
                "is_watched": False,
                "is_new": False,
                "is_movie_item": False,
                "is_hdr": False
            })

        # Keep exact user drag-to-order sequence in favorites:// with in-place diffing
        self.file_model.set_entries(entries, context_key="favorites://")
        surviving = [p for p in self._selected_paths if self.file_model.get_row_for_path(p) >= 0]
        if surviving != self._selected_paths:
            self._selected_paths = surviving
            if not surviving:
                self._selected_item = {}
                self._last_selected_row = -1
            self.selectedItemChanged.emit()
            self.selectedPathsChanged.emit()

    def _load_storage_analyzer_directory(self, analyzer_uri: str):
        real_dir = analyzer_uri[11:].strip() if analyzer_uri.startswith("analyzer://") else analyzer_uri
        if not real_dir:
            real_dir = "/"
        real_dir = os.path.abspath(os.path.expanduser(real_dir))
        if not os.path.isdir(real_dir):
            return

        full_uri = f"analyzer://{real_dir}"
        self._current_path = full_uri
        self.currentPathChanged.emit()
        self.breadcrumbsChanged.emit()
        self.mediaLibraryStateChanged.emit()

        if self._view_mode != "details":
            self._view_mode = "details"
            self.viewModeChanged.emit()
        if self._sort_by != "size":
            self._sort_by = "size"
            self.sortByChanged.emit()
        if self._sort_ascending:
            self._sort_ascending = False
            self.sortOrderChanged.emit()

        self._selected_item = {}
        self._selected_paths = []
        self._last_selected_row = -1
        self.selectedItemChanged.emit()
        self.selectedPathsChanged.emit()

        self.file_model.set_entries([])
        self._is_analyzing_storage = True
        self._analyzer_total_size_str = "Calculating..."
        self._analyzer_item_count = 0
        self.analyzerStateChanged.emit()

        task = StorageAnalyzerTask(
            real_dir,
            self._show_hidden,
            self._format_size,
            self._determine_icon_and_type,
            self.thumb_mgr,
            self._folder_size_cache,
            self.signals
        )
        self.thread_pool.start(task)

    def _on_storage_analyzer_ready(self, target_dir: str, entries: list, total_bytes: object):
        if str(self._current_path) != f"analyzer://{target_dir}":
            return
        self._is_analyzing_storage = False
        self._analyzer_total_size_str = self._format_size(max(0, int(total_bytes)))
        self._analyzer_item_count = len(entries)
        self.analyzerStateChanged.emit()
        self.file_model.set_entries(entries, context_key=f"analyzer://{target_dir}")

    def load_directory(self, target_path_str: str):
        if target_path_str.startswith("analyzer://"):
            self._load_storage_analyzer_directory(target_path_str)
            return
        if target_path_str == "mediahub://":
            self._load_media_hub_directory()
            return
        if target_path_str == "favorites://":
            self._load_favorites_directory()
            return
        if target_path_str == "recent://":
            self._load_recent_directory()
            return
        if target_path_str == "trash://":
            self._load_trash_directory()
            return

        target_path = Path(os.path.abspath(target_path_str))
        if not target_path.exists() or not target_path.is_dir():
            return

        target_resolved = str(target_path)
        if self._current_path != target_resolved:
            self._current_path = target_resolved
            self.currentPathChanged.emit()
            self.breadcrumbsChanged.emit()

        watched = self.watcher.directories()
        if watched:
            self.watcher.removePaths(watched)
        self.watcher.addPath(target_resolved)

        in_lib, is_movie = self._check_path_in_media_library(target_resolved)
        self.mediaLibraryStateChanged.emit()
        self._apply_saved_view_for_path(target_resolved)

        task = DirectoryLoaderTask(
            target_resolved,
            self._show_hidden,
            in_lib,
            is_movie,
            self._show_subtitles_in_media,
            self.picker_ctx,
            self._format_size,
            self._determine_icon_and_type,
            self.config_mgr.get_media_progress,
            self.config_mgr.get_cached_hdr,
            self.thumb_mgr,
            self._folder_size_cache,
            self.signals
        )
        self.dir_pool.start(task)

    def _parse_episode_info(self, filename: str):
        """
        Ultra-accurate torrent/anime/series episode parser handling S01E02, multi-season,
        fansub brackets, decimal episodes (12.5), and complex release strings.
        Returns (badge_str: str or None, sort_float: float or None).
        """
        stem = Path(filename).stem

        def _fmt(raw_num_str: str):
            val = float(raw_num_str)
            if "." in raw_num_str:
                parts = raw_num_str.split(".", 1)
                return f"{int(parts[0]):02d}.{parts[1]}", val
            return f"{int(val):02d}", val

        # 0. Direct fast-path on original stem for standard S01E02 / S01E02v2 / S1x02 patterns
        m_se = re.search(r'(?:^|[\s\._\-\[\(])[Ss](\d{1,2})[\s\._\-]*[Ee](\d{1,4}(?:\.\d)?)(?:v\d+)?(?:$|[\s\._\-\]\)]|\b)', stem)
        if m_se:
            return _fmt(m_se.group(2))

        m_x = re.search(r'(?:^|[\s\._\-\[\(])(\d{1,2})[xX](\d{1,3}(?:\.\d)?)(?:v\d+)?(?:$|[\s\._\-\]\)]|\b)', stem)
        if m_x and int(m_x.group(1)) < 50:
            return _fmt(m_x.group(2))

        # 1. Strip CRC32 hashes like [A1B2C3D4] or (0F8E9A12)
        s = re.sub(r'[\[\(][0-9A-Fa-f]{8}[\]\)]', ' ', stem)

        # 2. Extract any explicit episode inside brackets before stripping brackets e.g. [05] or [12.5] or [03v2]
        bracket_ep = None
        for bm in re.finditer(r'\[(\d{1,3}(?:\.\d)?)(?:v\d+)?\]', s, flags=re.I):
            val = float(bm.group(1))
            if 0 <= val < 1900 and int(val) not in (480, 576, 720, 1080, 264, 265):
                bracket_ep = bm.group(1)

        # 3. Strip all remaining [...] and (...) metadata blocks
        s = re.sub(r'\[[^\]]*\]|\([^\)]*\)', ' ', s)

        # 4. Replace dots and underscores with spaces (preserve decimal points only for .5 episodes)
        s = re.sub(r'(\d)\.5\b', r'\1_HALF_EP_', s)
        s = re.sub(r'[\._]+', ' ', s)
        s = s.replace('_HALF_EP_', '.5')

        # 5. Strip technical video/audio/release tokens & resolutions
        tech_noise = (
            r'\b(?:'
            r'\d{3,4}p|\d{3,4}x\d{3,4}|4K|8K|UHD|FHD|HD|SD|'
            r'[xh]\s*26[45]|HEVC|AVC|AV1|VP9|XviD|DivX|10\s*bit|8\s*bit|12\s*bit|Hi10P|Hi10|'
            r'HDR10\+?|HDR|DV|DoVi|Dolby\s*Vision|HLG|SDR|'
            r'WEB\s*DL|WEBRip|WEB|Blu\s*Ray|BDRip|BD|BRRip|DVDRip|HDTV|REMUX|'
            r'AAC\d*|FLAC|EAC3|AC3|DDP\d*|DD\d*|Opus|MP3|TrueHD|Atmos|DTS(?:\s*HD)?(?:\s*MA)?|'
            r'Dual\s*Audio|Multi\s*Subs?|Multiple\s*Subtitles?|Subbed|Dubbed|Uncensored|PROPER|REPACK|RERIP|'
            r'CH\d+|2CH|6CH|8CH|5\s*1|7\s*1|2\s*0|'
            r'(?:19|20)\d{2}'
            r')\b'
        )
        s = re.sub(tech_noise, ' ', s, flags=re.I)

        # Remove standalone season descriptors before further matching
        s_no_season = re.sub(
            r'\b(?:Season\s*\d{1,2}|S\d{1,2}|\d{1,2}(?:st|nd|rd|th)\s+Season|Part\s*\d{1,2}|Cour\s*\d{1,2})\b',
            ' ',
            s,
            flags=re.I
        )

        # Rule B: Explicit Episode keywords: EP05, Ep 05, Episode 05, E05, #05, 第05話
        m = re.search(r'(?:\b(?:Ep?(?:isode)?|Cap(?:itulo)?)|\#)\s*(\d{1,4}(?:\.\d)?)(?:v\d+)?\b', s_no_season, flags=re.I)
        if m:
            return _fmt(m.group(1))

        m = re.search(r'第\s*(\d{1,4}(?:\.\d)?)\s*[話话集]', s_no_season)
        if m:
            return _fmt(m.group(1))

        # Rule C: Anime/Torrent dash separator: "Title - 05", "Title - 05v2", "Title - 12.5 - EpTitle"
        dash_matches = list(re.finditer(r'-\s*(\d{1,4}(?:\.\d)?)(?:v\d+)?(?:\b|\s|-|$)', s_no_season, flags=re.I))
        if dash_matches:
            return _fmt(dash_matches[0].group(1))

        # Rule D: Bracketed episode number e.g. [05] found earlier
        if bracket_ep is not None:
            return _fmt(bracket_ep)

        # Rule E: Standalone number in cleaned title
        s_clean = re.sub(r'\s+', ' ', s_no_season).strip()
        tokens = list(re.finditer(r'\b(\d{1,4}(?:\.\d)?)(?:v\d+)?\b', s_clean, flags=re.I))
        if tokens:
            chosen = tokens[-1]
            if chosen.start() == 0 and len(tokens) == 1 and len(s_clean) > len(chosen.group(0)) + 2:
                return None, None
            val = float(chosen.group(1))
            if 0 <= val <= 1999:
                return _fmt(chosen.group(1))

        return None, None

    def _is_predominantly_video_folder(self, entries: list) -> bool:
        """
        Returns True ONLY if the current folder's items (ignoring subtitle & font files)
        consist of >= 90% video files (and at least 1 video file).
        """
        relevant_total = 0
        video_count = 0
        for e in entries:
            if e["is_dir"]:
                relevant_total += 1
            else:
                ext = Path(e["name"]).suffix.lower()
                if ext in SUBTITLE_EXTS or ext in FONT_EXTS:
                    continue
                relevant_total += 1
                if ext in VIDEO_EXTS:
                    video_count += 1
        if relevant_total == 0 or video_count == 0:
            return False
        return (video_count / relevant_total) >= 0.90

    def _on_directory_loaded(self, path_loaded, entries):
        if str(self._current_path) in ("recent://", "trash://", "favorites://", "mediahub://") or path_loaded != str(self._current_path):
            return

        in_lib, is_movie = self._check_path_in_media_library(path_loaded)
        is_episode_folder = (in_lib and not is_movie and self._is_predominantly_video_folder(entries))

        # When the current directory is an episode folder (>= 90% videos),
        # ignore inherited parent folder sort (like Date Modified on the root Anime folder)
        # and sort episodes strictly by their episode number in ascending order!
        if is_episode_folder:
            exact_fv = self.config_mgr.get_folder_view(path_loaded)
            # Only use a custom sort if the user explicitly clicked Sort inside THIS exact episode folder (not cascaded from parent)
            if not exact_fv or exact_fv.get("cascade", False):
                if self._sort_by != "name":
                    self._sort_by = "name"
                    self.sortByChanged.emit()
                if not self._sort_ascending:
                    self._sort_ascending = True
                    self.sortOrderChanged.emit()

        if in_lib:
            unprobed_hdr = []
            for e in entries:
                if not e["is_dir"] and Path(e["name"]).suffix.lower() in VIDEO_EXTS:
                    if is_movie:
                        e["episode_num"] = ""
                        e["is_movie_item"] = True
                    else:
                        badge, ep_sort = self._parse_episode_info(e["name"])
                        e["_ep_sort"] = ep_sort
                        e["_ep_badge"] = badge
                        e["is_movie_item"] = False

                    if self.config_mgr.get_cached_hdr(e["path"], e["raw_mod"]) is None:
                        unprobed_hdr.append((e["path"], e["raw_mod"]))

            self._sort_entries(entries, is_series_lib=is_episode_folder)

            if not is_movie:
                ep_counter = 1
                for e in entries:
                    if not e["is_dir"] and Path(e["name"]).suffix.lower() in VIDEO_EXTS:
                        badge = e.pop("_ep_badge", None)
                        e.pop("_ep_sort", None)
                        e["episode_num"] = badge if badge is not None else f"{ep_counter:02d}"
                        ep_counter += 1

            # Apply any cached Jellyfin titles/overviews/posters immediately, then trigger async background sync
            for e in entries:
                if is_movie and e["is_dir"]:
                    e["is_movie_item"] = True
                cached_jf = self.jf_bridge.get_cached_item(e["path"])
                if cached_jf:
                    e["episode_title"] = cached_jf.get("title", "")
                    e["overview"] = cached_jf.get("overview", "")
                    e["rating"] = str(cached_jf.get("rating", "")) if cached_jf.get("rating") else ""
                    e["poster"] = cached_jf.get("poster", "")

            if unprobed_hdr:
                hdr_task = HdrBatchDetectorTask(unprobed_hdr, self.config_mgr, self.signals)
                self.thread_pool.start(hdr_task)

            if self.jf_bridge.is_enabled:
                jf_task = JellyfinFolderSyncTask(self.jf_bridge, path_loaded, list(entries), self.jf_signals)
                self.thread_pool.start(jf_task)
        else:
            self._sort_entries(entries)

        is_same_dir = (self.file_model._current_context_key == path_loaded)
        self.file_model.set_entries(entries, context_key=path_loaded)

        if self._pending_highlight_paths:
            to_sel = [p for p in self._pending_highlight_paths if self.file_model.get_row_for_path(p) >= 0]
            self._pending_highlight_paths = []
            if to_sel:
                self._selected_paths = to_sel
                first_r = self.file_model.get_row_for_path(to_sel[0])
                ent = self.file_model.get_entry_at(first_r)
                if ent:
                    self._last_selected_row = first_r
                    self._selected_item = dict(ent)
            self.selectedItemChanged.emit()
            self.selectedPathsChanged.emit()
        elif is_same_dir and self._selected_paths:
            surviving = [p for p in self._selected_paths if self.file_model.get_row_for_path(p) >= 0]
            if surviving != self._selected_paths:
                self._selected_paths = surviving
                if surviving:
                    first_r = self.file_model.get_row_for_path(surviving[0])
                    ent = self.file_model.get_entry_at(first_r)
                    self._last_selected_row = first_r
                    if ent and len(surviving) == 1:
                        self._selected_item = dict(ent)
                else:
                    self._selected_item = {}
                    self._last_selected_row = -1
                self.selectedItemChanged.emit()
                self.selectedPathsChanged.emit()
        elif not is_same_dir:
            self._selected_item = {}
            self._selected_paths = []
            self._last_selected_row = -1
            self.selectedItemChanged.emit()
            self.selectedPathsChanged.emit()

    def _load_recent_directory(self):
        self._current_path = "recent://"
        self.currentPathChanged.emit()
        self.breadcrumbsChanged.emit()
        self.mediaLibraryStateChanged.emit()
        self._apply_saved_view_for_path("recent://", default_view_override="details")

        self._selected_item = {}
        self._selected_paths = []
        self._last_selected_row = -1
        self.selectedItemChanged.emit()
        self.selectedPathsChanged.emit()

        # Clear previous folder entries immediately and show loading state so UX never lags
        self.file_model.set_entries([])
        self._is_loading_recent = True
        self.isLoadingRecentChanged.emit()

        custom_recent = self.getRecentWatchedFolders()
        scan_roots = []
        seen_r = set()

        if custom_recent:
            for cr in custom_recent:
                if cr and os.path.isdir(cr) and cr not in seen_r:
                    seen_r.add(cr)
                    scan_roots.append((cr, 6))
        else:
            hidden_mounts = set(self.config_mgr.get("hidden_sidebar_paths", []))
            priority_dirs = [
                str(Path.home() / "Downloads"),
                str(Path.home() / "Desktop"),
                str(Path.home() / "Documents"),
                str(Path.home() / "Videos"),
                str(Path.home() / "Pictures"),
                str(Path.home() / "Music"),
                str(Path.home()),
            ]
            for lib in self.getMediaLibraries():
                if lib.get("path"):
                    priority_dirs.insert(0, lib["path"])

            for pd in priority_dirs:
                if pd and os.path.isdir(pd) and pd not in seen_r and pd not in hidden_mounts:
                    seen_r.add(pd)
                    scan_roots.append((pd, 5 if pd != str(Path.home()) else 3))

            for drv in self.getDrives():
                mp = drv.get("path", "")
                if mp and mp != "/" and os.path.isdir(mp) and mp not in seen_r and mp not in hidden_mounts:
                    seen_r.add(mp)
                    scan_roots.append((mp, 5))

        task = RecentScannerTask(
            scan_roots,
            self._show_hidden,
            self._format_size,
            self._determine_icon_and_type,
            self.thumb_mgr,
            self.signals
        )
        self.thread_pool.start(task)

    def _on_recent_entries_ready(self, entries: list):
        self._is_loading_recent = False
        self.isLoadingRecentChanged.emit()
        if str(self._current_path) != "recent://":
            return
        self.file_model.set_entries(entries, context_key="recent://")

    def _on_trash_size_ready(self, total_bytes: int, item_count: int):
        self._trash_total_size_str = self._format_size(max(0, int(total_bytes)))
        self._trash_item_count = int(item_count)
        self.trashInfoChanged.emit()

    def _sort_entries(self, entries, is_series_lib: bool = False):
        rev = not self._sort_ascending

        def natural_keys(text):
            return [int(c) if idx % 2 == 1 else c for idx, c in enumerate(re.split(r'(\d+)', text.lower()))]

        if self._sort_by == "size":
            base_key = lambda x: x["raw_size"]
        elif self._sort_by == "modified":
            base_key = lambda x: x["raw_mod"]
        elif self._sort_by == "created":
            base_key = lambda x: x["raw_created"]
        else:
            base_key = lambda x: natural_keys(x["name"])

        dirs = sorted([e for e in entries if e["is_dir"]], key=base_key, reverse=rev)

        if is_series_lib:
            # In a >=90% video episode folder, sort video files strictly by their extracted episode number!
            ep_key = lambda x: (
                0 if x.get("_ep_sort") is not None else 1,
                float(x["_ep_sort"]) if x.get("_ep_sort") is not None else float("inf"),
                natural_keys(x["name"])
            )
            exact_fv = self.config_mgr.get_folder_view(str(self._current_path))
            has_manual_override = bool(exact_fv and not exact_fv.get("cascade", False) and self._sort_by != "name")
            if has_manual_override:
                files = sorted([e for e in entries if not e["is_dir"]], key=base_key, reverse=rev)
            else:
                ep_rev = (not self._sort_ascending) if (exact_fv and not exact_fv.get("cascade", False)) else False
                files = sorted([e for e in entries if not e["is_dir"]], key=ep_key, reverse=ep_rev)
        else:
            files = sorted([e for e in entries if not e["is_dir"]], key=base_key, reverse=rev)

        entries[:] = dirs + files

    def _format_size(self, size):
        try:
            val = max(0.0, float(size))
        except (ValueError, TypeError):
            return "0 B"
        if val < 1024.0:
            return f"{int(val)} B"
        for unit in ['KB', 'MB', 'GB', 'TB']:
            val /= 1024.0
            if val < 1024.0:
                return f"{val:.1f} {unit}"
        return f"{val:.1f} PB"

    @Slot(str)
    def requestItemThumbnail(self, file_path_str: str):
        self.thumb_mgr.request_thumbnail(file_path_str)

    @Slot(str)
    def requestFolderPreview(self, folder_path_str: str):
        self.thumb_mgr.request_folder_preview(folder_path_str, self._show_hidden)

    def _trigger_background_airing_sync(self, force: bool = False):
        if getattr(self.airing_tracker, "_sync_in_progress", False):
            return
        self.airing_tracker._sync_in_progress = True

        def _bg_worker():
            try:
                mal_changed = self.airing_tracker.sync_mal_cache_sync(force=force)
                ani_changed = self.airing_tracker.sync_anilist_schedules_sync(force=force)
                aired = self.airing_tracker.check_and_advance_airing_timers_sync(send_os_notification=True)
                if (mal_changed or ani_changed or aired or force) and str(self._current_path) == "mediahub://":
                    self.refreshMediaHub()
            except Exception:
                pass
            finally:
                self.airing_tracker._sync_in_progress = False

        QThreadPool.globalInstance().start(_bg_worker)

    def _on_airing_minute_tick(self):
        # Fast local timer check + trigger background sync only if 30m/6h TTL expired
        try:
            aired = self.airing_tracker.check_and_advance_airing_timers_sync(send_os_notification=True)
            if str(self._current_path) == "mediahub://":
                self.refreshMediaHub()
            if self.airing_tracker.needs_background_sync():
                self._trigger_background_airing_sync(force=False)
        except Exception:
            pass

    def _get_highest_watched_ep_in_folder(self, folder_path: str) -> int:
        if not folder_path or not os.path.isdir(folder_path):
            return 0
        highest = 0
        stack = [(os.path.abspath(folder_path), 0)]
        visited = 0
        while stack and visited < 15:
            curr_d, depth = stack.pop(0)
            visited += 1
            try:
                with os.scandir(curr_d) as it:
                    for entry in it:
                        if entry.name.startswith("."):
                            continue
                        if entry.is_dir(follow_symlinks=True) and depth < 2:
                            stack.append((entry.path, depth + 1))
                        elif entry.is_file(follow_symlinks=True) and Path(entry.name).suffix.lower() in VIDEO_EXTS:
                            p_info = self.config_mgr.get_media_progress(entry.path)
                            if p_info.get("watched", False) or float(p_info.get("progress", 0.0) or 0.0) >= 0.90:
                                _, ep_val = self._parse_episode_info(entry.name)
                                if ep_val is not None and int(ep_val) > highest:
                                    highest = int(ep_val)
            except OSError:
                pass
        return highest

    def _build_airing_hub_items(self) -> list:
        """
        100% Local & Instant Builder:
        - Reads local anime_cache.json and schedules.json without any network requests.
        - Uses ONLY explicit user links (no false-positive auto-linking).
        - Calculates episode progress strictly from local watched episodes (linked folder + manual +/- counter), NOT from MAL watched count.
        - Automatically marks and removes anime from Airing once finished (just like the Discord bot).
        """
        cache = self.airing_tracker._load_json(self.airing_tracker.cache_file)
        schedules = self.airing_tracker._load_json(self.airing_tracker.schedules_file)
        user_items = cache.get(self.airing_tracker.mal_username, {})
        ignored_ids = set(str(x) for x in (self.config_mgr.get("airing_ignored_ids", []) or []))
        links_map = dict(self.config_mgr.get("airing_links", {}) or {})
        local_ep_map = dict(self.config_mgr.get("airing_local_eps", {}) or {})
        dirty_schedules = False

        items_out = []
        now_ts = time.time()

        for aid, udata in user_items.items():
            aid_str = str(aid)
            if aid_str.startswith("manga_") or aid_str in ignored_ids:
                continue
            if udata.get("status") not in ("watching", "plan_to_watch"):
                continue

            sched = schedules.get(aid_str, {})
            if sched and sched.get("status") == "finished":
                continue
            if not sched and udata.get("airing_status", "currently_airing") != "currently_airing":
                continue

            title = str(sched.get("title") or udata.get("title") or f"Anime #{aid_str}")
            poster_local = self.airing_tracker.get_cached_poster_path(aid_str)

            # Strictly explicit manual link only — never auto-link!
            linked_path = str(links_map.get(aid_str, "") or "")
            if linked_path and not os.path.exists(linked_path):
                linked_path = ""

            folder_watched_eps = self._get_highest_watched_ep_in_folder(linked_path) if linked_path else 0
            if aid_str in local_ep_map:
                effective_watched = max(int(local_ep_map.get(aid_str, 0) or 0), folder_watched_eps)
            else:
                effective_watched = folder_watched_eps

            next_ep = int(sched.get("next_ep", 0) or 0)
            next_air_ts = float(sched.get("next_air_timestamp", 0) or 0)
            total_eps = int(sched.get("total_eps") or udata.get("total_episodes") or 0)
            latest_aired_ep = max(0, next_ep - 1) if next_ep > 0 else effective_watched

            # Auto-remove from Airing if the user completed all episodes of the show
            if total_eps > 0 and effective_watched >= total_eps:
                if aid_str in schedules and schedules[aid_str].get("status") != "finished":
                    schedules[aid_str]["status"] = "finished"
                    dirty_schedules = True
                continue

            behind_count = max(0, latest_aired_ep - effective_watched)
            if latest_aired_ep == 0:
                status_label = f"📡 Ep 1 Soon"
                is_going_tight = True
            elif behind_count == 0:
                status_label = f"Going tight!"
                is_going_tight = True
            elif behind_count == 1:
                status_label = f"1 episode behind..."
                is_going_tight = False
            else:
                status_label = f"{behind_count} episodes behind..."
                is_going_tight = False

            if next_air_ts > now_ts:
                rem_sec = int(next_air_ts - now_ts)
                days, rem = divmod(rem_sec, 86400)
                hours, rem = divmod(rem, 3600)
                mins = rem // 60
                if days > 0:
                    air_badge = f"EP {next_ep} in {days}d {hours}h"
                elif hours > 0:
                    air_badge = f"EP {next_ep} in {hours}h {mins}m"
                else:
                    air_badge = f"EP {next_ep} in {mins}m"
            elif next_ep > 0:
                air_badge = f"EP {next_ep} Airing"
            else:
                air_badge = f"Watched {effective_watched}"

            denom = total_eps if total_eps > 0 else max(1, latest_aired_ep)
            prog_ratio = min(1.0, max(0.0, float(effective_watched) / float(denom))) if denom > 0 else 0.0

            card_path = linked_path if linked_path else f"airing://{aid_str}"
            items_out.append({
                "name": title,
                "display_title": title,
                "subtitle": status_label,
                "badge": air_badge,
                "path": card_path,
                "is_dir": True if linked_path else False,
                "size": f"Local: Ep {effective_watched} / {total_eps if total_eps > 0 else '?'}",
                "modified": str(sched.get("last_sync") or udata.get("updated_at") or ""),
                "created": "",
                "icon": "📡",
                "type": "Airing Anime",
                "raw_size": 0,
                "raw_mod": next_air_ts if next_air_ts > 0 else 9999999999.0,
                "raw_created": 0,
                "thumb": poster_local,
                "folder_previews": [],
                "episode_num": str(latest_aired_ep) if latest_aired_ep > 0 else "",
                "progress": round(prog_ratio, 4),
                "is_watched": False,
                "is_new": behind_count > 0,
                "is_movie_item": True,
                "is_hdr": False,
                "episode_title": f"{title} ({status_label})",
                "overview": (
                    f"Tracking Status: {status_label}\n"
                    f"Local Watched Progress: {effective_watched} / {total_eps if total_eps > 0 else '?'} episodes\n"
                    f"Latest Aired Episode: EP {latest_aired_ep}\n"
                    f"Linked Media Hub Folder: {linked_path if linked_path else 'Not linked (Right-click -> Link with Media Hub Work)'}"
                ),
                "rating": str(udata.get("score", "")) if udata.get("score") else "",
                "poster": poster_local,
                "is_airing_card": True,
                "airing_id": aid_str,
                "linked_path": linked_path,
                "local_watched_eps": effective_watched,
                "behind_count": behind_count,
                "is_going_tight": is_going_tight
            })

        if dirty_schedules:
            self.airing_tracker._save_json(self.airing_tracker.schedules_file, schedules)

        items_out.sort(key=lambda x: (0 if x.get("raw_mod", 0) > now_ts else 1, x.get("raw_mod", 0)))
        return items_out

    @Property(str, notify=mediaHubConfigChanged)
    def malUsername(self) -> str:
        return self.airing_tracker.mal_username

    @Property(str, notify=mediaHubConfigChanged)
    def malClientId(self) -> str:
        return self.airing_tracker.mal_client_id

    @Property(str, notify=mediaHubConfigChanged)
    def malAccessToken(self) -> str:
        return self.airing_tracker.mal_access_token

    @Slot(str, str, str)
    def saveAiringConfig(self, username: str, client_id: str, access_token: str):
        self.config_mgr.set("mal_username", username.strip() or "CriticalweebR18")
        self.config_mgr.set("mal_client_id", client_id.strip())
        self.config_mgr.set("mal_access_token", access_token.strip())
        self.mediaHubConfigChanged.emit()
        self.toastMessage.emit("✔ Saved Airing Tracker settings — Syncing MAL & AniList...")
        self.forceSyncAiringNow()

    @Slot()
    def forceSyncAiringNow(self):
        self.toastMessage.emit("Syncing MAL & AniList Airing schedules in background...")
        self._trigger_background_airing_sync(force=True)

    @Slot(str, int)
    def adjustAiringEpisode(self, airing_id: str, delta: int):
        clean_id = str(airing_id).replace("airing://", "").strip()
        if not clean_id:
            return
        local_ep_map = dict(self.config_mgr.get("airing_local_eps", {}) or {})
        links_map = dict(self.config_mgr.get("airing_links", {}) or {})
        linked_path = str(links_map.get(clean_id, "") or "")
        folder_eps = self._get_highest_watched_ep_in_folder(linked_path) if (linked_path and os.path.exists(linked_path)) else 0

        cur_val = int(local_ep_map.get(clean_id, folder_eps) or 0)
        new_val = max(0, cur_val + int(delta))

        schedules = self.airing_tracker._load_json(self.airing_tracker.schedules_file)
        cache = self.airing_tracker._load_json(self.airing_tracker.cache_file).get(self.airing_tracker.mal_username, {})
        sched = schedules.get(clean_id, {})
        udata = cache.get(clean_id, {})
        total_eps = int(sched.get("total_eps") or udata.get("total_episodes") or 0)
        if total_eps > 0:
            new_val = min(total_eps, new_val)

        local_ep_map[clean_id] = new_val
        self.config_mgr.set("airing_local_eps", local_ep_map)

        # Also mark/unmark matching episode inside linked local folder if present!
        if linked_path and os.path.isdir(linked_path):
            target_ep_to_toggle = new_val if delta > 0 else (cur_val if delta < 0 else -1)
            mark_watched_state = True if delta > 0 else False
            if target_ep_to_toggle > 0:
                try:
                    for root_d, _, files in os.walk(linked_path):
                        for fn in files:
                            if Path(fn).suffix.lower() in VIDEO_EXTS and not fn.startswith("."):
                                _, ep_v = self._parse_episode_info(fn)
                                if ep_v is not None and int(ep_v) == target_ep_to_toggle:
                                    fp = os.path.join(root_d, fn)
                                    cur_p = self.config_mgr.get_media_progress(fp)
                                    dur = cur_p.get("duration", 100.0) or 100.0
                                    self.config_mgr.set_media_progress(fp, 0.0, dur, watched=mark_watched_state)
                except Exception:
                    pass

        title = str(sched.get("title") or udata.get("title") or f"Anime #{clean_id}")
        if total_eps > 0 and new_val >= total_eps:
            if clean_id in schedules:
                schedules[clean_id]["status"] = "finished"
                self.airing_tracker._save_json(self.airing_tracker.schedules_file, schedules)
            self.toastMessage.emit(f"🏁 Completed '{title}' (Ep {new_val}/{total_eps}) — Removed from Airing!")
        else:
            self.toastMessage.emit(f"📺 {title}: Local Progress set to Episode {new_val}")

        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    @Slot()
    def clearAllAiringLinks(self):
        self.config_mgr.set("airing_links", {})
        self.mediaHubConfigChanged.emit()
        self.toastMessage.emit("⛓️‍💥 Cleared all Airing folder links")
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    @Slot(str)
    def ignoreAiringItem(self, airing_id: str):
        clean_id = str(airing_id).replace("airing://", "").strip()
        if not clean_id:
            return
        ignored = list(self.config_mgr.get("airing_ignored_ids", []) or [])
        if clean_id not in ignored:
            ignored.append(clean_id)
            self.config_mgr.set("airing_ignored_ids", ignored)
            self.mediaHubConfigChanged.emit()
            self.toastMessage.emit("🚫 Ignored anime from Airing tab (Can be restored in Settings)")
            if str(self._current_path) == "mediahub://":
                self.refreshMediaHub()

    @Slot(str)
    def restoreIgnoredAiringItem(self, airing_id: str):
        clean_id = str(airing_id).strip()
        ignored = [str(x) for x in (self.config_mgr.get("airing_ignored_ids", []) or []) if str(x) != clean_id]
        self.config_mgr.set("airing_ignored_ids", ignored)
        self.mediaHubConfigChanged.emit()
        self.toastMessage.emit("✔ Restored anime to Airing tab")
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    # ==========================================================================
    # Notification Center Full Configuration & Per-Work Controls
    # ==========================================================================

    @Slot(result=dict)
    def getNotificationSettings(self) -> dict:
        return self.airing_tracker.get_notification_config()

    @Slot(str, "QVariant")
    def updateNotificationSetting(self, key: str, value):
        cfg = self.airing_tracker.get_notification_config()
        cfg[key] = value
        self.config_mgr.set("notification_settings", cfg)
        self.notificationSettingsChanged.emit()

    @Slot(dict)
    def saveNotificationSettings(self, new_cfg: dict):
        cfg = self.airing_tracker.get_notification_config()
        if isinstance(new_cfg, dict):
            cfg.update(new_cfg)
        self.config_mgr.set("notification_settings", cfg)
        self.notificationSettingsChanged.emit()
        self.toastMessage.emit("🔔 Saved Notification Center settings")

    @Slot(result=list)
    def getTrackedWorksNotificationList(self) -> list:
        """
        Returns all tracked/airing works so the user can toggle notifications per anime.
        All works are ON by default unless explicitly in disabled_anime_ids.
        """
        ncfg = self.airing_tracker.get_notification_config()
        disabled_ids = {str(x) for x in (ncfg.get("disabled_anime_ids") or [])}
        ignored_ids = {str(x) for x in (self.config_mgr.get("airing_ignored_ids", []) or [])}
        cache = self.airing_tracker._load_json(self.airing_tracker.cache_file).get(self.airing_tracker.mal_username, {})
        schedules = self.airing_tracker._load_json(self.airing_tracker.schedules_file)
        local_ep_overrides = dict(self.config_mgr.get("airing_local_eps", {}) or {})
        links_map = dict(self.config_mgr.get("airing_links", {}) or {})

        works = []
        seen_ids = set()

        for aid, udata in cache.items():
            aid_str = str(aid)
            if aid_str.startswith("manga_") or aid_str in ignored_ids:
                continue
            if udata.get("status") not in ("watching", "plan_to_watch"):
                continue
            sched = schedules.get(aid_str, {})
            if sched and sched.get("status") == "finished":
                continue
            if not sched and udata.get("airing_status", "currently_airing") != "currently_airing":
                continue

            seen_ids.add(aid_str)
            title = str(sched.get("title") or udata.get("title") or f"Anime #{aid_str}")
            poster = self.airing_tracker.get_cached_poster_path(aid_str)
            next_ep = int(sched.get("next_ep", 1) or 1)
            next_ts = float(sched.get("next_air_timestamp", 0) or 0)
            watched_eps = self.airing_tracker._compute_local_watched_eps(aid_str, local_ep_overrides, links_map)
            works.append({
                "id": aid_str,
                "title": title,
                "poster": poster,
                "next_ep": next_ep,
                "next_ts": next_ts,
                "watched_eps": watched_eps,
                "enabled": aid_str not in disabled_ids
            })

        works.sort(key=lambda w: w["title"].lower())
        return works

    @Slot(str, bool)
    def setWorkNotificationEnabled(self, anime_id: str, enabled: bool):
        clean_id = str(anime_id).strip()
        if not clean_id:
            return
        ncfg = self.airing_tracker.get_notification_config()
        disabled = [str(x) for x in (ncfg.get("disabled_anime_ids") or []) if str(x) != clean_id]
        if not enabled:
            disabled.append(clean_id)
        ncfg["disabled_anime_ids"] = disabled
        self.config_mgr.set("notification_settings", ncfg)
        self.notificationSettingsChanged.emit()

    @Slot(bool)
    def setAllWorksNotificationsEnabled(self, enabled: bool):
        ncfg = self.airing_tracker.get_notification_config()
        if enabled:
            ncfg["disabled_anime_ids"] = []
        else:
            all_works = self.getTrackedWorksNotificationList()
            ncfg["disabled_anime_ids"] = [w["id"] for w in all_works]
        self.config_mgr.set("notification_settings", ncfg)
        self.notificationSettingsChanged.emit()
        self.toastMessage.emit("🔔 Enabled notifications for all works" if enabled else "🔕 Muted notifications for all works")

    @Slot()
    def sendTestNotification(self):
        works = self.getTrackedWorksNotificationList()
        sample_title = works[0]["title"] if works else "The Eminence in Shadow"
        sample_poster = works[0]["poster"] if works else ""
        sample_ep = works[0]["next_ep"] if works else 15
        sample_watched = works[0]["watched_eps"] if works else 14
        self.airing_tracker.dispatch_formatted_notification(
            aid_str="test",
            title=sample_title,
            ep_num=sample_ep,
            watched_eps=sample_watched,
            poster_local=sample_poster,
            event_type="test",
            event_label="🔔 Test Notification from Find Notification Center!",
            force_send=True
        )
        self.toastMessage.emit("🔔 Sent test desktop notification")

    @Slot()
    def clearAllIgnoredAiringItems(self):
        self.config_mgr.set("airing_ignored_ids", [])
        self.mediaHubConfigChanged.emit()
        self.toastMessage.emit("✔ Restored all ignored Airing items")
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    @Slot(result=list)
    def getIgnoredAiringItems(self) -> list:
        ignored = [str(x) for x in (self.config_mgr.get("airing_ignored_ids", []) or [])]
        if not ignored:
            return []
        cache = self.airing_tracker._load_json(self.airing_tracker.cache_file).get(self.airing_tracker.mal_username, {})
        schedules = self.airing_tracker._load_json(self.airing_tracker.schedules_file)
        out = []
        for aid in ignored:
            t = (schedules.get(aid) or {}).get("title") or (cache.get(aid) or {}).get("title") or f"Anime ID #{aid}"
            out.append({"id": aid, "title": t})
        return out

    @Slot(result=list)
    def getMediaHubLinkCandidates(self) -> list:
        candidates = []
        seen = set()
        for lib in self.getMediaLibraries():
            lp = lib.get("path", "")
            if not lp or not os.path.isdir(lp):
                continue
            try:
                with os.scandir(lp) as it:
                    for entry in it:
                        if entry.is_dir() and not entry.name.startswith("."):
                            ap = os.path.abspath(entry.path)
                            if ap not in seen:
                                seen.add(ap)
                                candidates.append({"name": entry.name, "path": ap, "lib_name": lib.get("name", "")})
            except OSError:
                pass
        candidates.sort(key=lambda x: x["name"].lower())
        return candidates

    @Slot(str, str)
    def linkAiringToMediaFolder(self, airing_id: str, folder_path: str):
        clean_id = str(airing_id).replace("airing://", "").strip()
        if not clean_id:
            return
        links = dict(self.config_mgr.get("airing_links", {}) or {})
        if not folder_path or not folder_path.strip():
            links.pop(clean_id, None)
            self.config_mgr.set("airing_links", links)
            self.toastMessage.emit("🔗 Unlinked local folder from Airing entry")
        else:
            norm_p = os.path.abspath(os.path.expanduser(folder_path.strip()))
            if os.path.exists(norm_p):
                links[clean_id] = norm_p
                self.config_mgr.set("airing_links", links)
                self.toastMessage.emit(f"🔗 Linked Airing anime to '{Path(norm_p).name}'")
        self.mediaHubConfigChanged.emit()
        if str(self._current_path) == "mediahub://":
            self.refreshMediaHub()

    @Slot(str)
    def openEntry(self, file_path_str: str):
        if file_path_str.startswith("airing://"):
            aid = file_path_str.replace("airing://", "").strip()
            links = dict(self.config_mgr.get("airing_links", {}) or {})
            linked_p = links.get(aid, "")
            if linked_p and os.path.exists(linked_p):
                if os.path.isdir(linked_p) and self.canResumeFolder(linked_p):
                    self.resumeMediaFolder(linked_p)
                else:
                    self.openEntry(linked_p)
            else:
                self.toastMessage.emit("🔗 Right-click this Airing card -> 'Link with Media Hub Work' to link its local folder")
            return
        if file_path_str in ("recent://", "trash://", "favorites://", "mediahub://") or file_path_str.startswith("analyzer://"):
            self.navigateTo(file_path_str)
            return

        path = Path(file_path_str)
        if path.is_dir():
            if str(self._current_path).startswith("analyzer://"):
                self.navigateTo(f"analyzer://{str(path)}")
            else:
                self.navigateTo(str(path))
        else:
            if self.picker_ctx.isActive:
                self.picker_ctx.setSelectedPath(str(path))
                self.confirmPickerSelection()
            else:
                if path.suffix.lower() in VIDEO_EXTS and shutil.which("mpv"):
                    self._launch_in_mpv_with_tracking(str(path), hdr_mode=None)
                else:
                    subprocess.Popen(["xdg-open", str(path)], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        @Slot(str, bool)
        def runExecutable(self, file_path_str: str, in_terminal: bool = False):
            if not file_path_str or not os.path.isfile(file_path_str):
                return
            try:
                abs_p = os.path.abspath(file_path_str)
                parent_d = os.path.dirname(abs_p)
                if not os.access(abs_p, os.X_OK):
                    st = os.stat(abs_p)
                    os.chmod(abs_p, st.st_mode | stat_mod.S_IXUSR)
                if in_terminal:
                    term_env = os.environ.get("TERMINAL")
                    terms = [[term_env, "-e", abs_p]] if term_env else []
                    terms += [
                        ["kitty", abs_p],
                        ["alacritty", "-e", abs_p],
                        ["ghostty", "-e", abs_p],
                        ["konsole", "-e", abs_p],
                        ["gnome-terminal", "--", abs_p],
                        ["xterm", "-e", abs_p],
                    ]
                    for t in terms:
                        if t[0] and shutil.which(t[0]):
                            subprocess.Popen(t, cwd=parent_d, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            return
                subprocess.Popen([abs_p], cwd=parent_d, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                self.toastMessage.emit(f"⚠️ Failed to run executable: {e}")

    @Slot(str, result=bool)
    def isVideoFile(self, file_path_str: str) -> bool:
        if not file_path_str:
            return False
        return Path(file_path_str).suffix.lower() in VIDEO_EXTS

    @Slot(result=str)
    def getMpvBothConfig(self) -> str:
        val = self.config_mgr.get("mpv_both_config")
        if not val:
            val = self.config_mgr.get("mpv_base_config", self.config_mgr.DEFAULT_CONFIG["mpv_both_config"])
        return val

    @Slot(result=str)
    def getMpvSdrConfig(self) -> str:
        return self.config_mgr.get("mpv_sdr_config", self.config_mgr.DEFAULT_CONFIG["mpv_sdr_config"])

    @Slot(result=str)
    def getMpvHdrConfig(self) -> str:
        return self.config_mgr.get("mpv_hdr_config", self.config_mgr.DEFAULT_CONFIG["mpv_hdr_config"])

    @Slot(str, str, str)
    def saveMpvConfigs(self, both_cfg: str, sdr_cfg: str, hdr_cfg: str):
        self.config_mgr.set("mpv_both_config", both_cfg.strip())
        self.config_mgr.set("mpv_sdr_config", sdr_cfg.strip())
        self.config_mgr.set("mpv_hdr_config", hdr_cfg.strip())
        self._write_system_mpv_conf(hdr_mode=False)

    @Slot()
    def resetMpvConfigsToDefault(self):
        self.config_mgr.set("mpv_both_config", self.config_mgr.DEFAULT_CONFIG["mpv_both_config"])
        self.config_mgr.set("mpv_sdr_config", self.config_mgr.DEFAULT_CONFIG["mpv_sdr_config"])
        self.config_mgr.set("mpv_hdr_config", self.config_mgr.DEFAULT_CONFIG["mpv_hdr_config"])
        self._write_system_mpv_conf(hdr_mode=False)

    @Slot(str, bool)
    def openInMpvCustom(self, file_path_str: str, hdr_mode: bool = False):
        if not file_path_str or not os.path.exists(file_path_str):
            return
        if shutil.which("mpv"):
            self._launch_in_mpv_with_tracking(file_path_str, hdr_mode=hdr_mode)

    @Slot(str, str)
    def openWithApp(self, file_path_str: str, app_cmd: str):
        try:
            if app_cmd == "mpv" and Path(file_path_str).suffix.lower() in VIDEO_EXTS:
                self._launch_in_mpv_with_tracking(file_path_str, hdr_mode=False)
                return
            subprocess.Popen([app_cmd, file_path_str], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    @Slot(str, result=str)
    def getDefaultApp(self, file_path_str: str):
        try:
            res = subprocess.run(["xdg-mime", "query", "filetype", file_path_str], capture_output=True, text=True)
            if res.returncode == 0:
                mime = res.stdout.strip()
                res2 = subprocess.run(["xdg-mime", "query", "default", mime], capture_output=True, text=True)
                if res2.returncode == 0:
                    d = res2.stdout.strip().replace(".desktop", "")
                    return d.capitalize()
        except Exception:
            pass
        return "Default Application"

    def _clean_desktop_exec(self, raw_exec: str) -> str:
        cleaned = re.sub(r'@@u?|%[fFuUickdDnNickvm]', '', raw_exec).strip()
        return cleaned

    @Slot(str, str)
    def openWithApp(self, file_path_str: str, app_cmd: str):
        try:
            if not file_path_str or not app_cmd:
                return
            import shlex
            needs_term = False
            if app_cmd.startswith("TERM:"):
                needs_term = True
                app_cmd = app_cmd[5:]
            if app_cmd == "mpv" or app_cmd.endswith("/mpv"):
                if Path(file_path_str).suffix.lower() in VIDEO_EXTS:
                    self._launch_in_mpv_with_tracking(file_path_str, hdr_mode=False)
                    return
            parts = shlex.split(self._clean_desktop_exec(app_cmd))
            if not parts:
                return
            parts.append(file_path_str)
            if needs_term:
                for term_bin in ("kitty", "alacritty", "ghostty", "konsole", "xterm"):
                    if shutil.which(term_bin):
                        cmd_t = [term_bin, "-e"] + parts if term_bin != "kitty" else [term_bin] + parts
                        subprocess.Popen(cmd_t, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        return
            subprocess.Popen(parts, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            self.toastMessage.emit(f"⚠️ Failed to launch app: {e}")

    @Slot(str, result=list)
    def getAvailableApps(self, file_path_str: str):
        if not file_path_str or not os.path.exists(file_path_str):
            return []

        p = Path(file_path_str)
        is_dir = p.is_dir()
        mime_type = "inode/directory" if is_dir else ""

        if not mime_type:
            try:
                res = subprocess.run(["xdg-mime", "query", "filetype", file_path_str], capture_output=True, text=True, timeout=1.2)
                if res.returncode == 0 and res.stdout.strip():
                    mime_type = res.stdout.strip().lower()
            except Exception:
                pass
        if not mime_type:
            guessed, _ = mimetypes.guess_type(file_path_str)
            mime_type = (guessed or "application/octet-stream").lower()

        if mime_type in self._mime_apps_cache:
            return self._mime_apps_cache[mime_type]

        major_type = mime_type.split("/")[0] if "/" in mime_type else ""
        app_dirs = [
            Path.home() / ".local" / "share" / "applications",
            Path("/var/lib/flatpak/exports/share/applications"),
            Path.home() / ".local" / "share" / "flatpak" / "exports" / "share" / "applications",
            Path("/usr/local/share/applications"),
            Path("/usr/share/applications"),
        ]

        exact_matches = []
        wildcard_matches = []
        seen_names = set()

        for adir in app_dirs:
            if not adir.is_dir():
                continue
            try:
                for entry in os.scandir(str(adir)):
                    if not entry.name.endswith(".desktop"):
                        continue
                    try:
                        with open(entry.path, "r", encoding="utf-8", errors="ignore") as f:
                            content = f.read()
                        if "[Desktop Entry]" not in content:
                            continue
                        name_val = ""
                        exec_val = ""
                        mimes_val = ""
                        no_display = False
                        is_term_app = False
                        in_entry = False
                        for ln in content.splitlines():
                            s = ln.strip()
                            if s.startswith("["):
                                in_entry = (s == "[Desktop Entry]")
                                continue
                            if not in_entry or not s or s.startswith("#"):
                                continue
                            if s.startswith("NoDisplay=") and s.split("=", 1)[1].strip().lower() == "true":
                                no_display = True
                            elif s.startswith("Terminal=") and s.split("=", 1)[1].strip().lower() == "true":
                                is_term_app = True
                            elif s.startswith("Name=") and not name_val:
                                name_val = s.split("=", 1)[1].strip()
                            elif s.startswith("Exec=") and not exec_val:
                                exec_val = s.split("=", 1)[1].strip()
                            elif s.startswith("MimeType="):
                                mimes_val = s.split("=", 1)[1].strip().lower()

                        if no_display or not name_val or not exec_val or not mimes_val:
                            continue
                        if name_val.lower() in ("find",):
                            continue

                        import shlex
                        cleaned_exec = self._clean_desktop_exec(exec_val)
                        parts = shlex.split(cleaned_exec)
                        if not parts:
                            continue
                        bin_cmd = parts[0]
                        if not (os.path.isabs(bin_cmd) and os.access(bin_cmd, os.X_OK)) and not shutil.which(bin_cmd):
                            continue

                        mime_list = [m.strip() for m in mimes_val.split(";") if m.strip()]
                        is_exact = mime_type in mime_list
                        is_wild = (f"{major_type}/*" in mime_list) or (major_type == "text" and "text/plain" in mime_list)
                        if not is_exact and not is_wild:
                            continue

                        key_lower = name_val.lower()
                        if key_lower in seen_names:
                            continue
                        seen_names.add(key_lower)
                        item_obj = {"name": name_val, "cmd": ("TERM:" + cleaned_exec) if is_term_app else cleaned_exec}
                        if is_exact:
                            exact_matches.append(item_obj)
                        else:
                            wildcard_matches.append(item_obj)
                    except Exception:
                        pass
            except OSError:
                pass

        combined = exact_matches + wildcard_matches
        self._mime_apps_cache[mime_type] = combined[:20]
        return self._mime_apps_cache[mime_type]

    @Slot(str)
    def duplicateItem(self, file_path_str: str):
        targets = list(self._selected_paths) if (file_path_str in self._selected_paths and len(self._selected_paths) > 1) else [file_path_str]

        def _dup_worker():
            ok_cnt = 0
            for fp in targets:
                try:
                    p = Path(fp)
                    if not p.exists():
                        continue
                    target = self._get_unique_path(p.parent, f"{p.stem} (Copy)", p.suffix)
                    if p.is_dir():
                        shutil.copytree(p, target, symlinks=True)
                    else:
                        shutil.copy2(p, target)
                    ok_cnt += 1
                except Exception as e:
                    self.toastMessage.emit(f"⚠️ Duplicate failed: {e}")
            if ok_cnt > 0:
                self.toastMessage.emit(f"✔ Duplicated {ok_cnt} item(s)")
                self.signals.requestRefresh.emit()

        self._run_bg_task(_dup_worker)

    @Slot(str, str)
    def renameItem(self, file_path_str: str, new_name: str):
        try:
            p = Path(file_path_str)
            clean_new = new_name.strip()
            if not p.exists() or not clean_new:
                return
            if "/" in clean_new or "\\" in clean_new or clean_new in (".", "..") or "\0" in clean_new:
                self.toastMessage.emit("⚠️ Invalid file name: slashes and relative '..' paths are not allowed")
                return
            target = p.parent / clean_new
            if os.path.abspath(str(p)) == os.path.abspath(str(target)):
                return
            if target.exists():
                self.renameConflictDetected.emit(str(p), clean_new, str(target))
                return
            p.rename(target)
            self.toastMessage.emit(f"✔ Renamed to '{clean_new}'")
            self.refresh()
        except Exception as e:
            self.toastMessage.emit(f"⚠️ Rename failed: {e}")

    @Slot(str, str, str)
    def resolveRenameByRenamingConflict(self, original_path_str: str, desired_name: str, new_name_for_conflicting: str):
        try:
            src_p = Path(original_path_str)
            clean_desired = desired_name.strip()
            clean_conflict_new = new_name_for_conflicting.strip()
            if not src_p.exists() or not clean_desired or not clean_conflict_new:
                return
            conflict_p = src_p.parent / clean_desired
            conflict_dest = src_p.parent / clean_conflict_new
            if conflict_dest.exists():
                self.toastMessage.emit(f"⚠️ '{clean_conflict_new}' also already exists!")
                return
            if conflict_p.exists():
                conflict_p.rename(conflict_dest)
            src_p.rename(conflict_p)
            self.toastMessage.emit(f"✔ Renamed conflicting item to '{clean_conflict_new}' and applied '{clean_desired}'")
            self.refresh()
        except Exception as e:
            self.toastMessage.emit(f"⚠️ Rename failed: {e}")

    @Property(bool, notify=clipboardChanged)
    def hasClipboardItems(self) -> bool:
        return len(self.getClipboardPaths()) > 0

    @Slot(str, bool)
    def stageClipboard(self, file_path_str: str = "", is_cut: bool = False):
        raw_targets = []
        if file_path_str and file_path_str in self._selected_paths and len(self._selected_paths) > 1:
            raw_targets = list(self._selected_paths)
        elif file_path_str:
            raw_targets = [file_path_str]
        elif self._selected_paths:
            raw_targets = list(self._selected_paths)
        elif self._selected_item and self._selected_item.get("path"):
            raw_targets = [self._selected_item["path"]]

        valid_paths = [os.path.abspath(fp) for fp in raw_targets if fp and os.path.exists(fp)]
        if not valid_paths:
            return
        self._clipboard_path = valid_paths[0]
        self._clipboard_paths = valid_paths
        self._clipboard_cut = bool(is_cut)
        try:
            clipboard = QGuiApplication.clipboard()
            mime = QMimeData()
            urls = [QUrl.fromLocalFile(vp) for vp in valid_paths]
            mime.setUrls(urls)
            mime.setText("\n".join(valid_paths))
            op_word = "cut" if is_cut else "copy"
            gnome_payload = op_word + "\n" + "\n".join(u.toString() for u in urls)
            mime.setData("x-special/gnome-copied-files", gnome_payload.encode("utf-8"))
            clipboard.setMimeData(mime)
        except Exception:
            pass
        self.clipboardChanged.emit()
        action_str = "✂️ Cut" if is_cut else "📋 Copied"
        self.toastMessage.emit(f"{action_str} {len(valid_paths)} item{'s' if len(valid_paths) > 1 else ''}")

    @Slot(result=list)
    def getClipboardPaths(self) -> list:
        out = []
        try:
            clipboard = QGuiApplication.clipboard()
            mime = clipboard.mimeData()
            if mime is not None:
                if mime.hasFormat("x-special/gnome-copied-files"):
                    raw_gnome = bytes(mime.data("x-special/gnome-copied-files")).decode("utf-8", errors="ignore").splitlines()
                    if raw_gnome:
                        self._clipboard_cut = (raw_gnome[0].strip().lower() == "cut")
                        for ln in raw_gnome[1:]:
                            local = QUrl(ln.strip()).toLocalFile() or ln.strip()
                            if local and os.path.exists(local) and local not in out:
                                out.append(os.path.abspath(local))
                if not out and mime.hasUrls():
                    for u in mime.urls():
                        local = u.toLocalFile()
                        if local and os.path.exists(local) and local not in out:
                            out.append(os.path.abspath(local))
                if not out and mime.hasText():
                    for ln in mime.text().strip().splitlines():
                        s = ln.strip()
                        if s.startswith("file://"):
                            s = QUrl(s).toLocalFile() or s[7:]
                        if s and os.path.exists(s) and s not in out:
                            out.append(os.path.abspath(s))
        except Exception:
            pass
        if out:
            return out
        if self._clipboard_paths:
            return [p for p in self._clipboard_paths if os.path.exists(p)]
        return []

    @Slot(result=str)
    def getClipboardPath(self):
        paths = self.getClipboardPaths()
        return paths[0] if paths else ""

    @Slot(result=bool)
    def isClipboardCut(self):
        self.getClipboardPaths()
        return self._clipboard_cut

    @Slot()
    def clearClipboardStage(self):
        self._clipboard_path = ""
        self._clipboard_paths = []
        self._clipboard_cut = False
        self.clipboardChanged.emit()

    @Slot(str)
    def pasteToFolder(self, dest_folder_str: str):
        try:
            if not dest_folder_str or dest_folder_str in ("recent://", "trash://", "favorites://", "mediahub://"):
                return
            clip_paths = self.getClipboardPaths()
            if not clip_paths:
                self.toastMessage.emit("⚠️ Clipboard is empty")
                return
            op = "move" if self._clipboard_cut else "copy"
            count_ok = 0
            for cp in clip_paths:
                if os.path.exists(cp):
                    if self.executeDropTransfer(cp, dest_folder_str, op, "keep_both"):
                        count_ok += 1
            if count_ok > 0:
                if self._clipboard_cut:
                    self.clearClipboardStage()
                self.toastMessage.emit(f"✔ Pasted {count_ok} item{'s' if count_ok > 1 else ''}")
                self.refresh()
        except Exception as e:
            self.toastMessage.emit(f"⚠️ Paste failed: {e}")

    @Slot(str, str, result=bool)
    def checkTransferConflict(self, src_path_str: str, dest_dir_str: str) -> bool:
        try:
            if dest_dir_str == "recent://":
                return False
            src = Path(src_path_str)
            dest_dir = Path(dest_dir_str)
            target = dest_dir / src.name
            if target.exists() and os.path.abspath(str(src)) != os.path.abspath(str(target)):
                return True
        except Exception:
            pass
        return False

    @Slot(str, str, str, str, result=bool)
    def executeDropTransfer(self, src_path_str: str, dest_dir_str: str, operation: str, conflict_resolution: str) -> bool:
        try:
            if not dest_dir_str or dest_dir_str in ("recent://", "trash://", "favorites://", "mediahub://") or dest_dir_str.startswith("analyzer://"):
                return False
            src = Path(src_path_str)
            dest_dir = Path(dest_dir_str)
            if not src.exists() or not dest_dir.exists() or not dest_dir.is_dir():
                return False
            if operation == "move" and os.path.abspath(str(src)) in PROTECTED_SYSTEM_PATHS:
                self.toastMessage.emit(f"🛡️ Protected system folder cannot be moved: {src}")
                return False

            target = dest_dir / src.name
            same_file = os.path.abspath(str(src)) == os.path.abspath(str(target))

            if same_file:
                if operation == "move":
                    return True
                elif operation == "copy":
                    target = self._get_unique_path(dest_dir, f"{src.stem} (Copy)", src.suffix)
            elif target.exists():
                if conflict_resolution == "skip":
                    return False
                elif conflict_resolution == "keep_both":
                    target = self._get_unique_path(dest_dir, src.stem, src.suffix)

            def _transfer_worker():
                try:
                    self.signals.archiveProgress.emit(0.35, f"{'Moving' if operation == 'move' else 'Copying'} {src.name}...")
                    if target.exists() and conflict_resolution == "replace" and not same_file:
                        staging = self._get_unique_path(dest_dir, f".find_tmp_{src.stem}", src.suffix)
                        if operation == "move":
                            shutil.move(str(src), str(staging))
                        else:
                            if src.is_dir():
                                shutil.copytree(str(src), str(staging), symlinks=True)
                            else:
                                shutil.copy2(str(src), str(staging))
                        if target.is_dir() and not target.is_symlink():
                            shutil.rmtree(str(target))
                        else:
                            target.unlink()
                        os.replace(str(staging), str(target))
                    else:
                        if operation == "move":
                            shutil.move(str(src), str(target))
                        elif operation == "copy":
                            if src.is_dir():
                                shutil.copytree(str(src), str(target), symlinks=True)
                            else:
                                shutil.copy2(str(src), str(target))
                    self.signals.archiveFinished.emit(True, f"✔ {'Moved' if operation == 'move' else 'Copied'} {src.name}")
                    self.signals.requestRefresh.emit()
                except Exception as e:
                    self.signals.archiveFinished.emit(False, f"⚠️ Transfer failed ({src.name}): {e}")

            if operation == "move":
                self.file_model.remove_paths_in_place([str(src)])
            self._run_bg_task(_transfer_worker)
            return True
        except Exception as e:
            self.toastMessage.emit(f"⚠️ Transfer error: {e}")
            return False

    @Property(bool, notify=compressionProgressChanged)
    def isCompressing(self) -> bool:
        return self._is_compressing

    @Property(float, notify=compressionProgressChanged)
    def compressionProgress(self) -> float:
        return self._compression_progress

    @Property(str, notify=compressionProgressChanged)
    def compressionStatus(self) -> str:
        return self._compression_status

    def _on_archive_progress(self, progress: float, status_text: str):
        self._is_compressing = True
        self._compression_progress = round(min(1.0, max(0.0, float(progress))), 3)
        self._compression_status = status_text
        self.compressionProgressChanged.emit()

    def _on_archive_finished(self, success: bool, message: str):
        self._is_compressing = False
        self._compression_progress = 0.0
        self._compression_status = ""
        self.compressionProgressChanged.emit()
        if message:
            self.toastMessage.emit(message)
        if success:
            self.refresh()

    @Slot(str, result=bool)
    def isArchiveFile(self, file_path_str: str) -> bool:
        if not file_path_str or os.path.isdir(file_path_str):
            return False
        nl = file_path_str.lower()
        return any(nl.endswith(ext) for ext in ARCHIVE_EXTS)

    @Slot(str, result=str)
    def getArchiveBaseName(self, file_path_str: str) -> str:
        if not file_path_str:
            return "Archive"
        name = Path(file_path_str).name
        for compound in (".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz2", ".txz"):
            if name.lower().endswith(compound):
                return name[:-len(compound)] or "Archive"
        return Path(file_path_str).stem or "Archive"

    @Slot(str, str)
    @Slot(str, str, str)
    def compressItem(self, file_path_str: str, archive_format: str, custom_archive_name: str = ""):
        if self._is_compressing:
            self.toastMessage.emit("⏳ Another archive task is already running...")
            return

        targets = (
            list(self._selected_paths)
            if (file_path_str in self._selected_paths and len(self._selected_paths) > 1)
            else ([file_path_str] if file_path_str else list(self._selected_paths))
        )
        valid_targets = [p for p in targets if p and os.path.exists(p)]
        if not valid_targets:
            return

        first_p = Path(valid_targets[0])
        parent_dir = first_p.parent
        fmt_map = {
            "zip": ".zip",
            "tar.gz": ".tar.gz",
            "tar.xz": ".tar.xz",
            "7z": ".7z"
        }
        ext = fmt_map.get(archive_format, ".zip")

        if custom_archive_name.strip():
            base_name = custom_archive_name.strip()
            for known_ext in (".zip", ".tar.gz", ".tar.xz", ".7z"):
                if base_name.lower().endswith(known_ext):
                    base_name = base_name[:-len(known_ext)]
                    break
        elif len(valid_targets) == 1:
            base_name = first_p.stem if first_p.is_file() else first_p.name
        else:
            base_name = parent_dir.name if parent_dir.name else "Archive"

        dest_archive = self._get_unique_path(parent_dir, base_name, ext)

        self._is_compressing = True
        self._compression_progress = 0.01
        self._compression_status = f"Preparing {len(valid_targets)} item(s)..."
        self.compressionProgressChanged.emit()

        task = ArchiveTask(valid_targets, dest_archive, archive_format, self.signals)
        QThreadPool.globalInstance().start(task)

    @Slot(str, str)
    @Slot(str, str, str)
    def extractArchive(self, archive_path_str: str, mode: str = "here", custom_dest_dir: str = ""):
        if self._is_compressing:
            self.toastMessage.emit("⏳ Another archive task is already running...")
            return
        if not archive_path_str or not os.path.isfile(archive_path_str):
            return

        if mode == "choose" and not custom_dest_dir:
            self._pending_extract_archive = os.path.abspath(archive_path_str)
            self.openInternalPicker("folder", "", f"Extract '{Path(archive_path_str).name}' To Folder")
            return

        arc_p = Path(os.path.abspath(archive_path_str))
        if mode == "subfolder":
            sub_name = self.getArchiveBaseName(str(arc_p))
            dest_dir = self._get_unique_path(arc_p.parent, sub_name, "")
        elif custom_dest_dir:
            dest_dir = Path(os.path.abspath(custom_dest_dir))
        else:
            dest_dir = arc_p.parent

        self._is_compressing = True
        self._compression_progress = 0.02
        self._compression_status = f"Extracting {arc_p.name}..."
        self.compressionProgressChanged.emit()

        task = ExtractTask(arc_p, dest_dir, self.signals)
        QThreadPool.globalInstance().start(task)

    @Slot(str)
    def moveToNewFolder(self, file_path_str: str):
        try:
            p = Path(file_path_str)
            if not p.exists():
                return
            new_dir = self._get_unique_path(p.parent, "New Folder")
            new_dir.mkdir(parents=True, exist_ok=True)
            shutil.move(str(p), str(new_dir / p.name))
            self.refresh()
        except Exception:
            pass

    @Slot(str)
    def shareItem(self, file_path_str: str):
        try:
            if shutil.which("kdeconnect-cli"):
                subprocess.Popen(["kdeconnect-handler", file_path_str])
            else:
                self.copyToClipboard(file_path_str)
        except Exception:
            pass

    @Slot(str)
    def openInFindInstance(self, target_path_str: str):
        """Spawns or sends the target directory to a standard Find window instance."""
        target = str(target_path_str or "").strip()
        if not target or target.startswith("airing://"):
            target = str(Path.home())
        elif target == "mediahub://":
            target = "mediahub://"
        elif not os.path.exists(target):
            target = str(Path.home())
        else:
            target = os.path.abspath(target)
            if os.path.isfile(target):
                parent_d = os.path.dirname(target)
                target = parent_d

        main_script = Path(__file__).resolve().parent.parent / "main.py"
        cmd_open = [sys.executable, target] if getattr(sys, "frozen", False) else [sys.executable, str(main_script), target]
        try:
            subprocess.Popen(
                cmd_open,
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            self.toastMessage.emit(f"📂 Opened in Find: {Path(target).name or target}")
        except Exception as e:
            self.toastMessage.emit(f"⚠️ Failed to open in Find: {e}")

    @Slot(str)
    def goToParentFolder(self, file_path_str: str):
        p = Path(file_path_str)
        parent = p.parent
        if parent.exists() and parent.is_dir():
            self.navigateTo(str(parent))
            self.selectMultiplePaths([str(p)])

    @Slot()
    def goUp(self):
        if str(self._current_path).startswith("analyzer://"):
            real_cur = str(self._current_path)[11:] or "/"
            parent = Path(real_cur).parent
            if str(parent) != real_cur:
                self.navigateTo(f"analyzer://{str(parent)}")
            return
        if str(self._current_path) in ("recent://", "trash://", "favorites://", "mediahub://"):
            self.openEntry(str(Path.home()))
            return
        parent = Path(self._current_path).parent
        if parent != Path(self._current_path):
            self.openEntry(str(parent))

    @Slot()
    def goBack(self):
        if self._history_idx > 0:
            self._history_idx -= 1
            self.load_directory(self._history[self._history_idx])
            self._update_history_state()
            self._sync_current_tab_state()

    @Slot()
    def goForward(self):
        if self._history_idx < len(self._history) - 1:
            self._history_idx += 1
            self.load_directory(self._history[self._history_idx])
            self._update_history_state()
            self._sync_current_tab_state()

    @Slot()
    def refresh(self):
        self.load_directory(str(self._current_path))

    @Slot(str)
    def navigateTo(self, path_str: str):
        if not path_str:
            return
        if path_str in ("recent://", "trash://", "favorites://", "mediahub://"):
            target = path_str
        elif path_str.startswith("trash:///") or path_str.startswith("trash:/"):
            target = "trash://"
        elif path_str.startswith("analyzer://"):
            real_sub = os.path.abspath(os.path.expanduser(path_str[11:].strip() or "/"))
            if not os.path.exists(real_sub):
                return
            target = f"analyzer://{real_sub}"
        elif "://" in path_str and not path_str.startswith("file://"):
            self.toastMessage.emit(f"🌐 Opening network/virtual URI via system handler: {path_str}")
            subprocess.Popen(["xdg-open", path_str], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return
        else:
            target = os.path.expanduser(os.path.expandvars(path_str))
            if target.startswith("file://"):
                target = QUrl(path_str).toLocalFile() or target[7:]
            target = os.path.abspath(target)
            if not os.path.exists(target):
                self.toastMessage.emit(f"⚠️ Path does not exist: {target}")
                return

        if self._history and self._history[self._history_idx] == target:
            self.load_directory(target)
            return

        if self._history_idx < len(self._history) - 1:
            self._history = self._history[:self._history_idx + 1]
        self._history.append(target)
        self._history_idx += 1
        self.load_directory(target)
        self._update_history_state()
        self._sync_current_tab_state()
        if self.picker_ctx.isActive and self.picker_ctx.mode == "folder" and target not in ("recent://", "trash://", "favorites://"):
            self.picker_ctx.setSelectedPath(target)

    @Slot(str)
    def setViewMode(self, mode: str):
        self.viewMode = mode

    @Slot(int)
    def setGridColumns(self, cols: int):
        self.gridColumns = cols

    @Slot(str)
    def setGridStyle(self, style: str):
        self.gridStyle = style

    @Slot(str)
    def setSidebarMode(self, mode: str):
        self.sidebarMode = mode

    @Slot(str)
    def setSort(self, sort_key: str):
        if self._sort_by == sort_key:
            self._sort_ascending = not self._sort_ascending
        else:
            self._sort_by = sort_key
            self._sort_ascending = True

        self.config_mgr.set_folder_view(str(self._current_path), self._view_mode, self._sort_by, self._sort_ascending)
        self.sortByChanged.emit()
        self.sortOrderChanged.emit()
        self.refresh()

    @Slot()
    def applyCurrentLayoutToSubfolders(self):
        if str(self._current_path) != "recent://":
            self.config_mgr.apply_view_to_subfolders(str(self._current_path), self._view_mode, self._sort_by, self._sort_ascending)

    @Slot(str, str, bool, str, str, str)
    @Slot(str, str, bool, str, str, str, int)
    def selectItem(self, path: str, name: str, is_dir: bool, size: str, modified: str, file_type: str, modifiers: int = 0):
        row_idx = self.file_model.get_row_for_path(path)
        ctrl_pressed = bool(modifiers & Qt.KeyboardModifier.ControlModifier.value)
        shift_pressed = bool(modifiers & Qt.KeyboardModifier.ShiftModifier.value)

        if shift_pressed and self._last_selected_row >= 0 and row_idx >= 0:
            start_r = min(self._last_selected_row, row_idx)
            end_r = max(self._last_selected_row, row_idx)
            range_paths = []
            for r in range(start_r, end_r + 1):
                ent = self.file_model.get_entry_at(r)
                if ent:
                    range_paths.append(ent["path"])
            if ctrl_pressed:
                merged = list(self._selected_paths)
                for rp in range_paths:
                    if rp not in merged:
                        merged.append(rp)
                self._selected_paths = merged
            else:
                self._selected_paths = range_paths
            self.selectedPathsChanged.emit()
        elif ctrl_pressed:
            updated_list = list(self._selected_paths)
            if path in updated_list:
                updated_list.remove(path)
            else:
                updated_list.append(path)
            self._selected_paths = updated_list
            if row_idx >= 0:
                self._last_selected_row = row_idx
            self.selectedPathsChanged.emit()
            if not self._selected_paths:
                self._selected_item = {}
                self.selectedItemChanged.emit()
                return
            if path not in self._selected_paths:
                last_p = self._selected_paths[-1]
                last_r = self.file_model.get_row_for_path(last_p)
                ent = self.file_model.get_entry_at(last_r)
                if ent:
                    path, name, is_dir, size, modified, file_type = (
                        ent["path"], ent["name"], ent["is_dir"], ent["size"], ent["modified"], ent["type"]
                    )
        else:
            self._selected_paths = [path]
            if row_idx >= 0:
                self._last_selected_row = row_idx
            self.selectedPathsChanged.emit()

        if self.picker_ctx.isActive:
            if self.picker_ctx.mode == "folder":
                if is_dir:
                    self.picker_ctx.setSelectedPaths([path])
            else:
                file_sels = [sp for sp in self._selected_paths if os.path.isfile(sp)]
                self.picker_ctx.setSelectedPaths(file_sels)

        preview_text = ""
        is_image = False
        is_video = False
        p = Path(path)
        thumb = ""
        folder_previews = []

        if not is_dir and p.exists():
            try:
                st = p.stat()
                if not size or size == "-":
                    size = self._format_size(max(0, int(st.st_size)))
                if stat_mod.S_ISREG(st.st_mode):
                    suffix = p.suffix.lower()
                    if suffix in IMAGE_EXTS:
                        is_image = True
                        thumb = self.thumb_mgr.get_existing_thumbnail(path)
                    elif suffix in VIDEO_EXTS:
                        is_video = True
                        thumb = self.thumb_mgr.get_existing_thumbnail(path)
                        if path not in self._media_info_cache:
                            saved_prog = self.config_mgr.get_media_progress(path)
                            task = MediaInfoTask(path, saved_prog.get("ext_sub", ""), self.signals)
                            self.thread_pool.start(task)
                    elif st.st_size <= 64 * 1024:
                        with open(p, "rb") as f:
                            chunk = f.read(1500)
                            if b"\0" not in chunk:
                                preview_text = chunk.decode("utf-8", errors="ignore")
            except Exception:
                pass
        elif is_dir and p.exists():
            folder_previews = self.thumb_mgr.get_cached_folder_preview(str(p))
            if not folder_previews:
                self.thumb_mgr.request_folder_preview(str(p), self._show_hidden)

            cached_sz = self._folder_size_cache.get(str(p))
            if cached_sz is not None:
                size = self._format_size(cached_sz)
            else:
                size = "Calculating..."
                if str(p) not in self._calculating_folders:
                    self._calculating_folders.add(str(p))
                    task = FolderSizeTask(str(p), self.signals)
                    self.thread_pool.start(task)

        # Multi-selection combined count & recursive subfolder size calculation
        if len(self._selected_paths) > 1:
            token = f"sel_{time.time()}_{len(self._selected_paths)}"
            self._selection_calc_token = token
            self._selected_item = {
                "path": path,
                "name": f"{len(self._selected_paths)} Items Selected",
                "is_dir": is_dir,
                "is_multi": True,
                "multi_count": len(self._selected_paths),
                "size": "Calculating total size...",
                "modified": modified,
                "type": "Multiple Selection",
                "preview_text": "",
                "is_image": is_image,
                "is_video": is_video,
                "thumb": thumb,
                "folder_previews": folder_previews,
                "episode_title": "",
                "overview": "",
                "rating": "",
                "poster": "",
                "resolution": "",
                "codec": "",
                "bit_depth": "",
                "color_profile": "",
                "bitrate": "",
                "fps": "",
                "audio_codec": ""
            }
            self.selectedItemChanged.emit()
            ms_task = MultiSelectionSizeTask(self._selected_paths, token, self.signals)
            self.thread_pool.start(ms_task)
            return

        self._selection_calc_token = ""
        jf_cached = self.jf_bridge.get_cached_item(path)
        cached_mi = self._media_info_cache.get(path, {}) if is_video else {}
        placeholder = "…" if (is_video and not cached_mi) else ""

        self._selected_item = {
            "path": path,
            "name": name,
            "is_dir": is_dir,
            "is_multi": False,
            "multi_count": 1,
            "size": size,
            "modified": modified,
            "type": file_type,
            "preview_text": preview_text,
            "is_image": is_image,
            "is_video": is_video,
            "thumb": thumb,
            "folder_previews": folder_previews,
            "episode_title": jf_cached.get("title", ""),
            "overview": jf_cached.get("overview", ""),
            "rating": str(jf_cached.get("rating", "")) if jf_cached.get("rating") else "",
            "poster": jf_cached.get("poster", ""),
            "resolution": cached_mi.get("resolution", placeholder),
            "codec": cached_mi.get("codec", placeholder),
            "bit_depth": cached_mi.get("bit_depth", placeholder),
            "color_profile": cached_mi.get("color_profile", placeholder),
            "bitrate": cached_mi.get("bitrate", placeholder),
            "fps": cached_mi.get("fps", placeholder),
            "audio_codec": cached_mi.get("audio_codec", placeholder),
            "audio_langs": cached_mi.get("audio_langs", []),
            "sub_langs": cached_mi.get("sub_langs", [])
        }
        self.selectedItemChanged.emit()

    def _on_media_info_ready(self, file_path_str, info):
        self._media_info_cache[file_path_str] = dict(info)
        if self._selected_item.get("path") == file_path_str:
            updated = dict(self._selected_item)
            updated.update(info)
            self._selected_item = updated
            self.selectedItemChanged.emit()

    def _on_folder_size_calculated(self, dir_path, total_bytes):
        self._calculating_folders.discard(dir_path)
        clean_bytes = max(0, int(total_bytes))
        self._folder_size_cache[dir_path] = clean_bytes
        formatted = self._format_size(clean_bytes)
        self.file_model.update_entry_size(dir_path, formatted, clean_bytes)
        if self._selected_item.get("path") == dir_path:
            updated = dict(self._selected_item)
            updated["size"] = formatted
            self._selected_item = updated
            self.selectedItemChanged.emit()

    def _on_multi_selection_size_ready(self, token: str, total_bytes: object, file_count: int, dir_count: int):
        if token != self._selection_calc_token or len(self._selected_paths) <= 1:
            return
        updated = dict(self._selected_item)
        updated["size"] = self._format_size(max(0, int(total_bytes)))
        parts = []
        if dir_count > 0:
            parts.append(f"{dir_count} Folder{'s' if dir_count > 1 else ''}")
        if file_count > 0:
            parts.append(f"{file_count} File{'s' if file_count > 1 else ''}")
        updated["type"] = f"{len(self._selected_paths)} Items ({', '.join(parts)})" if parts else f"{len(self._selected_paths)} Items"
        self._selected_item = updated
        self.selectedItemChanged.emit()

    @Slot(int)
    def selectByIndex(self, row: int):
        entry = self.file_model.get_entry_at(row)
        if entry is not None:
            self.selectItem(
                entry["path"],
                entry["name"],
                entry["is_dir"],
                entry["size"],
                entry["modified"],
                entry["type"]
            )

    @Slot(int, int)
    def moveSelectionRelative(self, delta: int, columns: int = 1):
        total = self.file_model.rowCount()
        if total <= 0:
            return
        cur_path = self._selected_item.get("path", "")
        cur_idx = self.file_model.get_row_for_path(cur_path) if cur_path else -1
        if cur_idx < 0:
            target_idx = 0 if delta >= 0 else total - 1
        else:
            target_idx = max(0, min(total - 1, cur_idx + delta))
        self.selectByIndex(target_idx)

    @Slot(result=int)
    def getSelectedRowIndex(self) -> int:
        cur_path = self._selected_item.get("path", "")
        if not cur_path:
            return -1
        return self.file_model.get_row_for_path(cur_path)

    @Slot(list, bool)
    def setRubberBandSelection(self, row_indices: list, append_ctrl: bool = False):
        paths = []
        last_ent = None
        for r in row_indices:
            ent = self.file_model.get_entry_at(int(r))
            if ent and ent.get("path"):
                paths.append(ent["path"])
                last_ent = ent
                self._last_selected_row = int(r)

        if append_ctrl:
            merged = list(self._selected_paths)
            for p in paths:
                if p not in merged:
                    merged.append(p)
            self._selected_paths = merged
        else:
            self._selected_paths = paths

        self.selectedPathsChanged.emit()
        if self.picker_ctx.isActive:
            file_sels = [sp for sp in self._selected_paths if os.path.isfile(sp)]
            self.picker_ctx.setSelectedPaths(file_sels)

        if not self._selected_paths:
            self._selected_item = {}
            self.selectedItemChanged.emit()
        elif len(self._selected_paths) == 1 and last_ent:
            self.selectItem(
                last_ent["path"], last_ent["name"], last_ent["is_dir"],
                last_ent["size"], last_ent["modified"], last_ent["type"], 0
            )
        elif len(self._selected_paths) > 1:
            token = f"rb_{time.time()}_{len(self._selected_paths)}"
            self._selection_calc_token = token
            self._selected_item = {
                "path": self._selected_paths[-1],
                "name": f"{len(self._selected_paths)} Items Selected",
                "is_dir": False,
                "is_multi": True,
                "multi_count": len(self._selected_paths),
                "size": "Calculating total size...",
                "modified": "",
                "type": "Multiple Selection",
                "preview_text": "",
                "is_image": False,
                "is_video": False,
                "thumb": "",
                "folder_previews": [],
                "episode_title": "",
                "overview": "",
                "rating": "",
                "poster": "",
                "resolution": "",
                "codec": "",
                "bit_depth": "",
                "color_profile": "",
                "bitrate": "",
                "fps": "",
                "audio_codec": ""
            }
            self.selectedItemChanged.emit()
            ms_task = MultiSelectionSizeTask(self._selected_paths, token, self.signals)
            self.thread_pool.start(ms_task)

    @Slot()
    def selectAll(self):
        total = self.file_model.rowCount()
        if total <= 0:
            return
        all_paths = []
        for r in range(total):
            ent = self.file_model.get_entry_at(r)
            if ent:
                all_paths.append(ent["path"])
        self._selected_paths = all_paths
        self.selectedPathsChanged.emit()
        if not self._selected_item and total > 0:
            first = self.file_model.get_entry_at(0)
            if first:
                self.selectItem(first["path"], first["name"], first["is_dir"], first["size"], first["modified"], first["type"], Qt.KeyboardModifier.ControlModifier.value)

    @Slot()
    def clearSelection(self):
        self._selected_item = {}
        self._selected_paths = []
        self._last_selected_row = -1
        self.selectedItemChanged.emit()
        self.selectedPathsChanged.emit()

    @Slot()
    def toggleShowHidden(self):
        self.showHidden = not self._show_hidden

    @Slot()
    def confirmPickerSelection(self):
        if self.picker_ctx.mode == "save":
            fname = self.picker_ctx.saveFilename.strip()
            if not fname:
                return
            cur_dir = str(self._current_path)
            if cur_dir in ("recent://", "trash://"):
                cur_dir = str(Path.home())
            chosen = [os.path.join(cur_dir, fname)]
        else:
            chosen = self.picker_ctx.selectedPaths
            if not chosen:
                if self.picker_ctx.mode == "folder":
                    chosen = [str(self._current_path)]
                else:
                    return

        for item_path in chosen:
            print(item_path)
        sys.stdout.flush()

        self.pickerCompleted.emit(chosen)
        if getattr(self, "_launched_as_picker", False):
            QGuiApplication.exit(0)

    @Slot()
    def cancelPicker(self):
        if getattr(self, "_launched_as_picker", False):
            QGuiApplication.exit(1)
            sys.exit(1)
        self.picker_ctx.deactivate()

    def _on_external_picker_finished(self, chosen_paths: list):
        if chosen_paths:
            if self._pending_extract_archive:
                arc_to_extract = self._pending_extract_archive
                self._pending_extract_archive = ""
                self.extractArchive(arc_to_extract, "custom", chosen_paths[0])
                return
            self.pickerCompleted.emit(chosen_paths)

    @Slot(str, str, str)
    @Slot(str, str, str, str)
    def openInternalPicker(self, mode: str, filter_str: str, title: str, save_filename: str = ""):
        """
        If called when launching with --picker CLI flag, activates the picker UI in this window.
        If called from inside a normal Find window (e.g. Settings Browse...), spawns an independent
        standalone Picker window process so the main window is never hijacked!
        """
        if getattr(self, "_launched_as_picker", False):
            self.picker_ctx.activate(mode, filter_str, title, save_filename)
            self.load_directory(str(self._current_path))
            return

        main_script = str(Path(__file__).resolve().parent.parent / "main.py")
        cmd = [sys.executable, "--picker"] if getattr(sys, "frozen", False) else [sys.executable, main_script, "--picker"]
        if mode == "folder":
            cmd.append("--folder")
        elif mode == "multi_file":
            cmd.append("--multiple")
        elif mode == "save":
            cmd.append("--save")
            if save_filename:
                cmd.extend(["--save-name", save_filename])
        if filter_str:
            cmd.extend(["--filter", filter_str])
        if title:
            cmd.extend(["--title", title])
        start_dir = str(self._current_path)
        if start_dir in ("recent://", "trash://", "favorites://"):
            start_dir = str(Path.home())
        cmd.append(start_dir)

        def _run_picker_proc():
            try:
                res = subprocess.run(cmd, capture_output=True, text=True)
                if res.returncode == 0 and res.stdout.strip():
                    lines = [ln.strip() for ln in res.stdout.strip().splitlines() if ln.strip()]
                    if lines:
                        self.signals.externalPickerFinished.emit(lines)
            except Exception:
                pass

        QThreadPool.globalInstance().start(_run_picker_proc)

    def selectMultiplePaths(self, paths_list: list):
        norm_list = [os.path.abspath(p) for p in paths_list if p]
        self._pending_highlight_paths = norm_list
        if norm_list:
            matched = [p for p in norm_list if self.file_model.get_row_for_path(p) >= 0]
            if matched:
                self._pending_highlight_paths = []
                self._selected_paths = matched
                r = self.file_model.get_row_for_path(matched[0])
                ent = self.file_model.get_entry_at(r)
                if ent:
                    self._last_selected_row = r
                    self._selected_item = dict(ent)
                self.selectedItemChanged.emit()
                self.selectedPathsChanged.emit()

    def _get_unique_path(self, parent_dir: Path, base_name: str, ext: str = "") -> Path:
        target = parent_dir / f"{base_name}{ext}"
        counter = 2
        while target.exists():
            target = parent_dir / f"{base_name} ({counter}){ext}"
            counter += 1
        return target

    @Slot(str, str)
    def createItem(self, item_type: str, item_name: str):
        cur_s = str(self._current_path)
        if cur_s in ("recent://", "trash://", "favorites://", "mediahub://") or cur_s.startswith("analyzer://"):
            self.toastMessage.emit("⚠️ Cannot create new items inside a virtual view")
            return

        try:
            cur_dir = Path(self._current_path)
            if item_type == "folder":
                target = self._get_unique_path(cur_dir, "New Folder")
                target.mkdir(parents=True, exist_ok=True)
            elif item_type == "link":
                target = self._get_unique_path(cur_dir, "New Link")
                os.symlink(str(cur_dir), str(target))
            else:
                default_contents = {
                    "py": ("main", ".py", "#!/usr/bin/env python3\n\n"),
                    "rs": ("main", ".rs", "fn main() {\n    println!(\"Hello, world!\");\n}\n"),
                    "json": ("config", ".json", "{\n  \n}\n"),
                    "txt": ("New Text Document", ".txt", ""),
                    "empty": ("new_file", "", ""),
                }
                base, ext, content = default_contents.get(item_type, ("file", "", ""))
                target = self._get_unique_path(cur_dir, base, ext)
                with open(target, "w", encoding="utf-8") as f:
                    f.write(content)
            self.refresh()
        except Exception:
            pass

    @Slot(str)
    def copyToClipboard(self, path_or_text: str):
        """
        Copies plain text path(s) to the system clipboard.
        If multiple items are selected and path_or_text is one of them,
        copies every selected item's path on its own line as pure plaintext!
        """
        clipboard = QGuiApplication.clipboard()
        if path_or_text in self._selected_paths and len(self._selected_paths) > 1:
            plain_lines = "\n".join(str(p) for p in self._selected_paths if p)
            clipboard.setText(plain_lines)
            self.toastMessage.emit(f"📋 Copied {len(self._selected_paths)} paths to clipboard")
        else:
            clipboard.setText(str(path_or_text))
            self.toastMessage.emit("📋 Copied path to clipboard")

    @Slot(str)
    def openInTerminal(self, dir_path_str: str):
        if dir_path_str.startswith("analyzer://"):
            dir_path_str = dir_path_str[11:] or str(Path.home())
        elif dir_path_str in ("recent://", "trash://", "favorites://", "mediahub://"):
            dir_path_str = str(Path.home())
        path = Path(dir_path_str)
        if not path.is_dir():
            path = path.parent

        term_env = os.environ.get("TERMINAL")
        terminals = [[term_env]] if term_env else []
        terminals += [["kitty"], ["alacritty"], ["ghostty"], ["konsole"], ["gnome-terminal"], ["xterm"]]

        for t in terminals:
            if shutil.which(t[0]):
                subprocess.Popen(t, cwd=str(path), start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return

    @Slot(str)
    def moveToTrash(self, file_path_str: str):
        targets = list(self._selected_paths) if (file_path_str in self._selected_paths and len(self._selected_paths) > 1) else [file_path_str]
        valid_targets = []
        for fp in targets:
            if not fp or not os.path.exists(fp):
                continue
            abs_fp = os.path.abspath(fp)
            if abs_fp in PROTECTED_SYSTEM_PATHS:
                self.toastMessage.emit(f"🛡️ Protected system path cannot be trashed: {abs_fp}")
                continue
            valid_targets.append(abs_fp)

        if not valid_targets:
            return

        def _trash_worker():
            moved_count = 0
            from urllib.parse import quote
            for fp in valid_targets:
                try:
                    self.thumb_mgr.remove_thumbnail_for_path(fp)
                    if shutil.which("gio"):
                        res = subprocess.run(["gio", "trash", fp], capture_output=True, timeout=6.0)
                        if res.returncode == 0:
                            moved_count += 1
                            continue
                    if shutil.which("trash-put"):
                        res = subprocess.run(["trash-put", fp], capture_output=True, timeout=6.0)
                        if res.returncode == 0:
                            moved_count += 1
                            continue

                    xdg_data = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))
                    t_root = Path(xdg_data) / "Trash"
                    t_files = t_root / "files"
                    t_info = t_root / "info"
                    t_files.mkdir(parents=True, exist_ok=True)
                    t_info.mkdir(parents=True, exist_ok=True)
                    src = Path(fp)
                    dest = self._get_unique_path(t_files, src.stem, src.suffix)
                    info_file = t_info / f"{dest.name}.trashinfo"
                    del_date = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
                    info_content = (
                        "[Trash Info]\n"
                        f"Path={quote(fp, safe='/')}\n"
                        f"DeletionDate={del_date}\n"
                    )
                    info_file.write_text(info_content, encoding="utf-8")
                    shutil.move(str(src), str(dest))
                    moved_count += 1
                except Exception as e:
                    self.toastMessage.emit(f"⚠️ Failed to trash '{Path(fp).name}': {e}")

            if moved_count > 0:
                self.config_mgr.clean_cache()
                self.cacheSizeChanged.emit()
                self.toastMessage.emit(f"🗑️ Moved {moved_count} item{'s' if moved_count > 1 else ''} to Trash")
                self.signals.requestRefresh.emit()

        self.file_model.remove_paths_in_place(valid_targets)
        self.media_hub_model.remove_paths_in_place(valid_targets)
        if any(p in self._selected_paths or p == self._selected_item.get("path") for p in valid_targets):
            self.clearSelection()
        self._run_bg_task(_trash_worker)

    def _resolve_trashinfo_for_file(self, trashed_file_path: str):
        p = Path(trashed_file_path)
        trash_root = p.parent.parent
        info_file = trash_root / "info" / f"{p.name}.trashinfo"
        orig_path = ""
        if info_file.exists():
            try:
                with open(info_file, "r", encoding="utf-8", errors="ignore") as f:
                    for ln in f:
                        if ln.strip().startswith("Path="):
                            raw_p = unquote(ln.strip().split("=", 1)[1].strip())
                            if not os.path.isabs(raw_p):
                                raw_p = os.path.join(str(trash_root.parent), raw_p)
                            orig_path = os.path.abspath(raw_p)
                            break
            except Exception:
                pass
        return orig_path, info_file

    @Slot(str)
    def restoreFromTrash(self, file_path_str: str = ""):
        targets = (
            list(self._selected_paths)
            if (file_path_str in self._selected_paths and len(self._selected_paths) > 1)
            else ([file_path_str] if file_path_str else list(self._selected_paths))
        )

        def _restore_worker():
            restored_count = 0
            for fp in targets:
                if not fp or not os.path.exists(fp):
                    continue
                try:
                    orig_path, info_file = self._resolve_trashinfo_for_file(fp)
                    if not orig_path:
                        orig_path = str(Path.home() / Path(fp).name)
                    dest_p = Path(orig_path)
                    dest_p.parent.mkdir(parents=True, exist_ok=True)
                    if dest_p.exists():
                        dest_p = self._get_unique_path(dest_p.parent, f"{dest_p.stem} (Restored)", dest_p.suffix)
                    shutil.move(str(fp), str(dest_p))
                    if info_file.exists():
                        try:
                            info_file.unlink()
                        except OSError:
                            pass
                    restored_count += 1
                except Exception as e:
                    self.toastMessage.emit(f"⚠️ Restore error: {e}")
            if restored_count > 0:
                self.toastMessage.emit(f"↩ Restored {restored_count} item{'s' if restored_count > 1 else ''} to original location")
                self.signals.requestRefresh.emit()
            else:
                self.toastMessage.emit("⚠️ Could not restore selected item(s)")

        self.file_model.remove_paths_in_place([fp for fp in targets if fp])
        self.clearSelection()
        self._run_bg_task(_restore_worker)

    @Slot(str)
    def deletePermanently(self, file_path_str: str = ""):
        targets = (
            list(self._selected_paths)
            if (file_path_str in self._selected_paths and len(self._selected_paths) > 1)
            else ([file_path_str] if file_path_str else list(self._selected_paths))
        )

        def _del_worker():
            deleted_count = 0
            for fp in targets:
                if not fp or not os.path.exists(fp):
                    continue
                abs_fp = os.path.abspath(fp)
                if abs_fp in PROTECTED_SYSTEM_PATHS:
                    self.toastMessage.emit(f"🛡️ Protected system path cannot be deleted: {abs_fp}")
                    continue
                try:
                    self.thumb_mgr.remove_thumbnail_for_path(abs_fp)
                    _, info_file = self._resolve_trashinfo_for_file(abs_fp)
                    p = Path(abs_fp)
                    if p.is_dir() and not p.is_symlink():
                        shutil.rmtree(str(p))
                    else:
                        p.unlink()
                    if info_file.exists():
                        try:
                            info_file.unlink()
                        except OSError:
                            pass
                    deleted_count += 1
                except Exception as e:
                    self.toastMessage.emit(f"⚠️ Delete failed ({Path(abs_fp).name}): {e}")
            if deleted_count > 0:
                self.toastMessage.emit(f"🔥 Permanently deleted {deleted_count} item{'s' if deleted_count > 1 else ''}")
                self.signals.requestRefresh.emit()

        self.file_model.remove_paths_in_place([os.path.abspath(fp) for fp in targets if fp])
        self.media_hub_model.remove_paths_in_place([os.path.abspath(fp) for fp in targets if fp])
        self.clearSelection()
        self._run_bg_task(_del_worker)

    @Slot()
    def emptyTrash(self):
        if str(self._current_path) == "trash://":
            self.file_model.set_entries([], context_key="trash://", force_reset=True)
            self._trash_item_count = 0
            self._trash_total_size_str = "0 B"
            self.trashInfoChanged.emit()
            self.clearSelection()

        def _empty_worker():
            deleted_count = 0
            for t_dir in self._get_all_trash_dirs():
                p_files = Path(t_dir)
                p_info = p_files.parent / "info"
                if p_files.is_dir():
                    for child in list(p_files.iterdir()):
                        try:
                            if child.is_dir() and not child.is_symlink():
                                shutil.rmtree(str(child))
                            else:
                                child.unlink()
                            deleted_count += 1
                        except Exception:
                            pass
                if p_info.is_dir():
                    for inf in list(p_info.iterdir()):
                        try:
                            inf.unlink()
                        except Exception:
                            pass
            self.toastMessage.emit(f"🧹 Emptied Trash ({deleted_count} items permanently removed)")
            self.signals.requestRefresh.emit()

        self._run_bg_task(_empty_worker)

    @Slot(int)
    def setMaxCacheMb(self, mb: int):
        self.config_mgr.set("max_cache_mb", mb)
        self.maxCacheMbChanged.emit()
        self.config_mgr.clean_cache()
        self.cacheSizeChanged.emit()

    @Slot()
    def clearCache(self):
        self.config_mgr.clean_cache(force_all=True)
        self.thumb_mgr.folder_cache.clear()
        self.thumb_mgr.requested.clear()
        self.thumb_mgr.requested_folders.clear()
        self.cacheSizeChanged.emit()

    @Property(str, notify=searchScopeChanged)
    def searchScope(self) -> str:
        return self._search_scope

    @Property(str, notify=searchFiltersChanged)
    def searchMatchMode(self) -> str:
        return self._search_match_mode

    @Property(str, notify=searchFiltersChanged)
    def searchTargetType(self) -> str:
        return self._search_target_type

    @Property(str, notify=searchFiltersChanged)
    def searchExtFilter(self) -> str:
        return self._search_ext_filter

    @Property(int, notify=searchFiltersChanged)
    def activeSearchFilterCount(self) -> int:
        cnt = 0
        if self._search_scope != "recursive":
            cnt += 1
        if self._search_match_mode != "contains":
            cnt += 1
        if self._search_target_type != "all":
            cnt += 1
        if self._search_ext_filter.strip() != "":
            cnt += 1
        return cnt

    @Slot(str)
    def setSearchScope(self, scope: str):
        if scope in ("current_only", "recursive", "here", "everywhere") and self._search_scope != scope:
            self._search_scope = "recursive" if scope == "here" else scope
            self.searchScopeChanged.emit()
            self.searchFiltersChanged.emit()
            if self._last_search_query:
                self.searchFast(self._last_search_query)

    @Slot(str)
    def setSearchMatchMode(self, mode: str):
        if mode in ("contains", "starts_with", "ends_with", "exact", "regex") and self._search_match_mode != mode:
            self._search_match_mode = mode
            self.searchFiltersChanged.emit()
            if self._last_search_query:
                self.searchFast(self._last_search_query)

    @Slot(str)
    def setSearchTargetType(self, t_type: str):
        if t_type in ("all", "folders", "files") and self._search_target_type != t_type:
            self._search_target_type = t_type
            self.searchFiltersChanged.emit()
            if self._last_search_query:
                self.searchFast(self._last_search_query)

    @Slot(str)
    def setSearchExtFilter(self, ext_str: str):
        clean = ext_str.strip()
        if self._search_ext_filter != clean:
            self._search_ext_filter = clean
            self.searchFiltersChanged.emit()
            if self._last_search_query:
                self.searchFast(self._last_search_query)

    @Slot()
    def resetSearchFilters(self):
        self._search_scope = "recursive"
        self._search_match_mode = "contains"
        self._search_target_type = "all"
        self._search_ext_filter = ""
        self.searchScopeChanged.emit()
        self.searchFiltersChanged.emit()
        if self._last_search_query:
            self.searchFast(self._last_search_query)

    @Slot(str)
    def searchFast(self, query: str):
        self._last_search_query = query
        self.search_mgr.query(
            query,
            scope=self._search_scope,
            current_dir=str(self._current_path),
            match_mode=self._search_match_mode,
            target_type=self._search_target_type,
            ext_filter=self._search_ext_filter,
            icon_resolver=self._determine_icon_and_type,
            thumb_resolver=self.thumb_mgr.get_existing_thumbnail,
            size_formatter=self._format_size
        )

    @Slot(result=dict)
    def getDefaultTypeIcons(self):
        return self.config_mgr.get("default_type_icons", {})

    @Slot(str, str)
    def setDefaultTypeIcon(self, type_key: str, icon_val: str):
        icons = dict(self.config_mgr.get("default_type_icons", {}))
        icons[type_key] = icon_val
        self.config_mgr.set("default_type_icons", icons)
        self.refresh()

    @Slot(str)
    def hideSidebarItem(self, path_str: str):
        hidden = list(self.config_mgr.get("hidden_sidebar_paths", []))
        if path_str not in hidden:
            hidden.append(path_str)
            self.config_mgr.set("hidden_sidebar_paths", hidden)
            self.sidebarUpdated.emit()

    @Slot(str)
    def restoreSidebarItem(self, path_str: str):
        hidden = list(self.config_mgr.get("hidden_sidebar_paths", []))
        if path_str in hidden:
            hidden.remove(path_str)
            self.config_mgr.set("hidden_sidebar_paths", hidden)
            self.sidebarUpdated.emit()

    @Slot(result=list)
    def getHiddenSidebarItems(self):
        return self.config_mgr.get("hidden_sidebar_paths", [])

    @Slot(result=list)
    def getQuickAccessLocations(self):
        hidden = set(self.config_mgr.get("hidden_sidebar_paths", []))
        configured = self.config_mgr.get("custom_quick_access", [])
        return [item for item in configured if item["path"] not in hidden and Path(item["path"]).exists()]

    @Slot(result=list)
    def getAllCustomQuickAccess(self):
        return self.config_mgr.get("custom_quick_access", [])

    @Slot(list)
    def saveCustomQuickAccess(self, items: list):
        self.config_mgr.set("custom_quick_access", items)
        self.sidebarUpdated.emit()

    @Slot(int, int)
    def moveQuickAccessItem(self, from_idx: int, to_idx: int):
        items = list(self.config_mgr.get("custom_quick_access", []))
        if not (0 <= from_idx < len(items)) or not (0 <= to_idx < len(items)) or from_idx == to_idx:
            return
        entry = items.pop(from_idx)
        items.insert(to_idx, entry)
        self.config_mgr.set("custom_quick_access", items)
        self.sidebarUpdated.emit()

    # ==========================================================================
    # 1. Favorites Manager (Files & Folders + Custom Ordering)
    # ==========================================================================

    @Slot(result=list)
    def getFavorites(self) -> list:
        raw = self.config_mgr.get("favorites", [])
        valid = []
        for item in raw:
            if isinstance(item, dict) and item.get("path") and os.path.exists(item["path"]):
                p = Path(item["path"])
                is_dir = p.is_dir()
                icon = item.get("icon") or ("⭐" if is_dir else "📄")
                valid.append({
                    "name": item.get("name", p.name or item["path"]),
                    "path": str(p),
                    "is_dir": is_dir,
                    "icon": icon
                })
        return valid

    @Slot(str, result=bool)
    def isPathFavorited(self, path_str: str) -> bool:
        if not path_str:
            return False
        norm = os.path.abspath(path_str)
        return any(os.path.abspath(x.get("path", "")) == norm for x in self.config_mgr.get("favorites", []))

    @Slot(str)
    def addToFavorites(self, path_str: str):
        targets = list(self._selected_paths) if (path_str in self._selected_paths and len(self._selected_paths) > 1) else [path_str]
        favs = list(self.config_mgr.get("favorites", []))
        existing_paths = {os.path.abspath(x.get("path", "")) for x in favs if isinstance(x, dict)}
        changed = False
        for tp in targets:
            if not tp or not os.path.exists(tp):
                continue
            norm = os.path.abspath(tp)
            if norm in existing_paths:
                continue
            p_obj = Path(norm)
            is_dir = p_obj.is_dir()
            icon, _ = self._determine_icon_and_type(p_obj, is_dir)
            favs.append({
                "name": p_obj.name or norm,
                "path": norm,
                "is_dir": is_dir,
                "icon": icon
            })
            existing_paths.add(norm)
            changed = True
        if changed:
            self.config_mgr.set("favorites", favs)
            self.favoritesUpdated.emit()
            self.sidebarUpdated.emit()

    @Slot(str)
    def removeFromFavorites(self, path_str: str):
        if not path_str:
            return
        norm = os.path.abspath(path_str)
        favs = [x for x in self.config_mgr.get("favorites", []) if os.path.abspath(x.get("path", "")) != norm]
        self.config_mgr.set("favorites", favs)
        self.favoritesUpdated.emit()
        self.sidebarUpdated.emit()

    @Slot(int, int)
    def moveFavoriteItem(self, from_idx: int, to_idx: int):
        favs = list(self.config_mgr.get("favorites", []))
        if not (0 <= from_idx < len(favs)) or not (0 <= to_idx < len(favs)) or from_idx == to_idx:
            return
        item = favs.pop(from_idx)
        favs.insert(to_idx, item)
        self.config_mgr.set("favorites", favs)
        self.favoritesUpdated.emit()
        self.sidebarUpdated.emit()
        if str(self._current_path) == "favorites://":
            self._load_favorites_directory()

    @Slot(list)
    def saveFavoritesList(self, items: list):
        self.config_mgr.set("favorites", items)
        self.favoritesUpdated.emit()
        self.sidebarUpdated.emit()

    # ==========================================================================
    # 2. Direct Anime / Series Folder Resume Engine
    # ==========================================================================

    def _find_resume_episode_in_folder(self, folder_path_str: str) -> str:
        """
        Finds the exact episode to resume inside an anime/series folder (or its Season subfolders).
        - If an episode is partially watched (position > 5s and not watched), resumes it immediately.
        - Otherwise, picks the first unwatched episode right after the highest watched episode.
        - If none are watched yet, picks Episode 1.
        """
        if not folder_path_str or not os.path.isdir(folder_path_str):
            return ""

        video_entries = []
        queue = [(os.path.abspath(folder_path_str), 0)]
        visited = 0
        while queue and visited < 15:
            curr_d, depth = queue.pop(0)
            visited += 1
            try:
                with os.scandir(curr_d) as it:
                    sub_dirs = []
                    for entry in it:
                        if entry.name.startswith("."):
                            continue
                        if entry.is_dir(follow_symlinks=True) and depth < 2:
                            sub_dirs.append((entry.path, depth + 1))
                        elif entry.is_file(follow_symlinks=True):
                            ext = Path(entry.name).suffix.lower()
                            if ext in VIDEO_EXTS:
                                _, ep_num = self._parse_episode_info(entry.name)
                                video_entries.append((entry.path, entry.name, ep_num))
                    if not video_entries and sub_dirs:
                        sub_dirs.sort(key=lambda x: x[0].lower())
                        queue.extend(sub_dirs)
            except OSError:
                pass
            if video_entries:
                break

        if not video_entries:
            return ""

        def _nat_key(text: str):
            return [int(c) if c.isdigit() else c for c in re.split(r'(\d+)', text.lower())]

        video_entries.sort(key=lambda item: (
            0 if item[2] is not None else 1,
            float(item[2]) if item[2] is not None else float("inf"),
            _nat_key(item[1])
        ))

        in_progress_candidates = []
        last_watched_idx = -1

        for idx, (fpath, fname, _) in enumerate(video_entries):
            p_info = self.config_mgr.get_media_progress(fpath)
            watched = bool(p_info.get("watched", False))
            pos = float(p_info.get("position", 0.0) or 0.0)
            prog = float(p_info.get("progress", 0.0) or 0.0)
            if watched:
                last_watched_idx = idx
            elif pos > 5.0 or prog > 0.01:
                in_progress_candidates.append((idx, pos, fpath))

        # Priority 1: Most recently/furthest in-progress unwatched episode
        if in_progress_candidates:
            in_progress_candidates.sort(key=lambda x: x[0], reverse=True)
            return in_progress_candidates[0][2]

        # Priority 2: Next unwatched episode immediately following the last watched episode
        if last_watched_idx >= 0:
            next_idx = last_watched_idx + 1
            if next_idx < len(video_entries):
                return video_entries[next_idx][0]
            return ""

        # Priority 3: First episode in folder
        return video_entries[0][0]

    @Slot(str, result=bool)
    def canResumeFolder(self, folder_path_str: str) -> bool:
        if not folder_path_str or folder_path_str in ("recent://", "trash://") or not os.path.isdir(folder_path_str):
            return False
        in_lib, is_movie = self._check_path_in_media_library(folder_path_str)
        if in_lib and not is_movie:
            return bool(self._find_resume_episode_in_folder(folder_path_str))
        # Also allow resume on any folder that directly contains video episodes
        try:
            with os.scandir(folder_path_str) as it:
                for entry in it:
                    if entry.is_file() and Path(entry.name).suffix.lower() in VIDEO_EXTS:
                        return True
        except OSError:
            pass
        return False

    @Slot(str, result=dict)
    def getResumeFolderInfo(self, folder_path_str: str) -> dict:
        ep_path = self._find_resume_episode_in_folder(folder_path_str)
        if not ep_path:
            return {"has_resume": False, "episode_name": "", "episode_path": "", "ep_num": "", "time_str": ""}
        name = Path(ep_path).name
        badge, ep_val = self._parse_episode_info(name)
        if ep_val is not None:
            ep_clean = str(int(ep_val)) if float(ep_val).is_integer() else str(ep_val)
        elif badge:
            ep_clean = badge.lstrip("0") or "1"
        else:
            ep_clean = "1"

        p_info = self.config_mgr.get_media_progress(ep_path)
        pos = float(p_info.get("position", 0.0) or 0.0)
        mins, secs = divmod(int(pos), 60)
        time_str = f"{mins:02d}:{secs:02d}" if pos > 5.0 else ""
        return {
            "has_resume": True,
            "episode_name": name,
            "episode_path": ep_path,
            "ep_num": ep_clean,
            "badge": f"EP {ep_clean}",
            "time_str": time_str
        }

    @Slot(str)
    def resumeMediaFolder(self, folder_path_str: str):
        target_dir = folder_path_str if folder_path_str else str(self._current_path)
        ep_path = self._find_resume_episode_in_folder(target_dir)
        if ep_path and os.path.exists(ep_path):
            self.openEntry(ep_path)

    # ==========================================================================
    # 3. Automated .desktop Application Creator & History Registry
    # ==========================================================================

    @Slot(str, result=bool)
    def isExecutableFile(self, file_path_str: str) -> bool:
        """
        Strictly checks if a file is a genuine executable binary, AppImage, or executable script.
        Never returns True for ordinary media/documents on NTFS/exFAT mounts!
        """
        if not file_path_str or not os.path.isfile(file_path_str):
            return False
        p = Path(file_path_str)
        ext = p.suffix.lower()

        # Never treat known non-executable media, images, archives, fonts, or docs as executables
        non_exec_exts = (
            IMAGE_EXTS | VIDEO_EXTS | SUBTITLE_EXTS | FONT_EXTS |
            {".mp3", ".flac", ".wav", ".ogg", ".m4a", ".aac", ".zip", ".tar", ".gz", ".xz", ".7z", ".rar",
             ".pdf", ".txt", ".md", ".json", ".toml", ".yaml", ".yml", ".ini", ".cfg", ".conf", ".html", ".css", ".qml"}
        )
        if ext in non_exec_exts:
            return False

        if ext in {".appimage", ".run", ".bin", ".sh"}:
            return True

        try:
            with open(file_path_str, "rb") as f:
                header = f.read(4)
                # 1. Native Linux ELF Binary (\x7fELF)
                if header == b"\x7fELF":
                    return True
                # 2. Script with explicit #! Shebang header AND +x bit
                if header.startswith(b"#!") and os.access(file_path_str, os.X_OK):
                    return True
        except OSError:
            pass
        return False

    @Slot(result=list)
    def getSavedDesktopApps(self) -> list:
        return list(self.config_mgr.get("saved_desktop_apps", []))

    @Slot(str, result=dict)
    def getDesktopPresetForExec(self, file_path_str: str) -> dict:
        if not file_path_str:
            return {}
        norm = os.path.abspath(file_path_str)
        stem = Path(norm).stem
        for item in self.config_mgr.get("saved_desktop_apps", []):
            if item.get("exec_target") == norm or item.get("name", "").lower() == stem.lower():
                return dict(item)
        clean_title = re.sub(r'[-_\.]+', ' ', stem).strip().title()
        return {
            "name": clean_title or stem,
            "exec_cmd": f"\"{norm}\"",
            "exec_target": norm,
            "icon": "application-x-executable",
            "categories": "Utility;Application;",
            "terminal": False,
            "comment": f"Created by Find File Manager for {Path(norm).name}"
        }

    @Slot(str, str, str, str, bool, str, result=bool)
    def createAndSaveDesktopApp(
        self,
        source_file_path: str,
        app_name: str,
        exec_cmd: str,
        icon_path: str,
        terminal: bool = False,
        categories: str = "Utility;Application;"
    ) -> bool:
        if not app_name.strip() or not exec_cmd.strip():
            return False
        try:
            if source_file_path and os.path.isfile(source_file_path):
                try:
                    st = os.stat(source_file_path)
                    os.chmod(source_file_path, st.st_mode | stat_mod.S_IXUSR | stat_mod.S_IXGRP | stat_mod.S_IXOTH)
                except OSError:
                    pass

            xdg_data = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))
            apps_dir = Path(xdg_data) / "applications"
            apps_dir.mkdir(parents=True, exist_ok=True)

            # Also keep a backup archive of generated .desktop files inside ~/.config/find/desktop_files/
            backup_dir = self.config_mgr.config_dir / "desktop_files"
            backup_dir.mkdir(parents=True, exist_ok=True)

            slug = re.sub(r'[^a-z0-9]+', '-', app_name.strip().lower()).strip('-') or "custom-app"
            desktop_filename = f"find-app-{slug}.desktop"
            desktop_path = apps_dir / desktop_filename
            backup_path = backup_dir / desktop_filename

            icon_val = icon_path.strip() if icon_path.strip() else "application-x-executable"
            cats_val = categories.strip() if categories.strip() else "Utility;Application;"
            if not cats_val.endswith(";"):
                cats_val += ";"

            def _s(v: str) -> str:
                return str(v or "").replace("\r", " ").replace("\n", " ").strip()

            clean_app_name = _s(app_name)
            clean_exec_cmd = _s(exec_cmd)
            icon_val = _s(icon_val)
            cats_val = _s(cats_val)

            desktop_content = (
                "[Desktop Entry]\n"
                "Version=1.0\n"
                "Type=Application\n"
                f"Name={clean_app_name}\n"
                f"Comment=Launched via Find Desktop Automation\n"
                f"Exec={clean_exec_cmd}\n"
                f"Icon={icon_val}\n"
                f"Terminal={'true' if terminal else 'false'}\n"
                "StartupNotify=true\n"
                f"Categories={cats_val}\n"
            )

            desktop_path.write_text(desktop_content, encoding="utf-8")
            backup_path.write_text(desktop_content, encoding="utf-8")
            try:
                os.chmod(desktop_path, 0o755)
            except OSError:
                pass

            if shutil.which("update-desktop-database"):
                subprocess.Popen(
                    ["update-desktop-database", str(apps_dir)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )

            saved_list = list(self.config_mgr.get("saved_desktop_apps", []))
            record = {
                "name": app_name.strip(),
                "exec_cmd": exec_cmd.strip(),
                "exec_target": os.path.abspath(source_file_path) if source_file_path else "",
                "icon": icon_val,
                "terminal": bool(terminal),
                "categories": cats_val,
                "desktop_file": str(desktop_path),
                "backup_file": str(backup_path),
                "updated_at": datetime.now().strftime("%Y-%m-%d %H:%M")
            }
            replaced = False
            for idx, existing in enumerate(saved_list):
                if existing.get("desktop_file") == str(desktop_path) or existing.get("name", "").lower() == app_name.strip().lower():
                    saved_list[idx] = record
                    replaced = True
                    break
            if not replaced:
                saved_list.insert(0, record)

            self.config_mgr.set("saved_desktop_apps", saved_list)
            self.desktopAppsUpdated.emit()
            self.toastMessage.emit(f"✔ Added '{app_name.strip()}' to Applications (.desktop)")
            return True
        except Exception:
            return False

    @Slot(str)
    def removeSavedDesktopApp(self, desktop_file_path: str):
        saved_list = [x for x in self.config_mgr.get("saved_desktop_apps", []) if x.get("desktop_file") != desktop_file_path]
        self.config_mgr.set("saved_desktop_apps", saved_list)
        if desktop_file_path and os.path.exists(desktop_file_path):
            try:
                os.unlink(desktop_file_path)
            except OSError:
                pass
        self.desktopAppsUpdated.emit()

    # ==========================================================================
    # 4. Font Installer / Downloader to Default or Custom Fonts Path
    # ==========================================================================

    @Property(str, notify=fontsDirChanged)
    def fontsInstallDir(self) -> str:
        return str(self.config_mgr.get("fonts_install_dir", str(Path.home() / ".local" / "share" / "fonts")))

    @Slot(str)
    def setFontsInstallDir(self, path_str: str):
        if not path_str or not path_str.strip():
            return
        norm = os.path.abspath(os.path.expanduser(path_str.strip()))
        self.config_mgr.set("fonts_install_dir", norm)
        self.fontsDirChanged.emit()

    @Slot(str, result=bool)
    def canInstallFontsFrom(self, target_path_str: str) -> bool:
        if not target_path_str or not os.path.exists(target_path_str):
            return False
        p = Path(target_path_str)
        if p.is_file():
            return p.suffix.lower() in FONT_EXTS
        if p.is_dir():
            try:
                with os.scandir(target_path_str) as it:
                    for entry in it:
                        if entry.is_file() and Path(entry.name).suffix.lower() in FONT_EXTS:
                            return True
            except OSError:
                pass
        return False

    @Slot(str, str, result=int)
    def installFontsToSystem(self, target_path_str: str, custom_dest_dir: str = "") -> int:
        dest_dir = Path(os.path.expanduser(custom_dest_dir.strip())) if custom_dest_dir.strip() else Path(self.fontsInstallDir)
        dest_dir.mkdir(parents=True, exist_ok=True)

        targets = list(self._selected_paths) if (target_path_str in self._selected_paths and len(self._selected_paths) > 1) else [target_path_str]
        font_files = []
        for tp in targets:
            if not tp or not os.path.exists(tp):
                continue
            p = Path(tp)
            if p.is_file() and p.suffix.lower() in FONT_EXTS:
                font_files.append(p)
            elif p.is_dir():
                for root_d, _, files in os.walk(str(p)):
                    for fn in files:
                        if Path(fn).suffix.lower() in FONT_EXTS:
                            font_files.append(Path(root_d) / fn)

        installed_count = 0
        for fp in font_files:
            try:
                target_dest = dest_dir / fp.name
                if os.path.abspath(str(fp)) != os.path.abspath(str(target_dest)):
                    shutil.copy2(str(fp), str(target_dest))
                installed_count += 1
            except Exception:
                pass

        if installed_count > 0 and shutil.which("fc-cache"):
            subprocess.Popen(
                ["fc-cache", "-f", str(dest_dir)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            self.toastMessage.emit(f"🔤 Installed {installed_count} font(s) to {dest_dir}")
        return installed_count

    # ==========================================================================
    # 5. Default System File Manager Registration
    # ==========================================================================

    # ==========================================================================
    # 5. Session Persistence, Startup Location & Recursive Icon Gallery
    # ==========================================================================

    @Property(bool, notify=sessionConfigChanged)
    def restoreLastSession(self) -> bool:
        return bool(self.config_mgr.get("restore_last_session", True))

    @Slot(bool)
    def setRestoreLastSession(self, enabled: bool):
        self.config_mgr.set("restore_last_session", bool(enabled))
        if enabled:
            self._save_session_state()
        self.sessionConfigChanged.emit()

    @Property(str, notify=sessionConfigChanged)
    def startupPath(self) -> str:
        return str(self.config_mgr.get("startup_path", str(Path.home())))

    @Slot(str)
    def setStartupPath(self, path_str: str):
        if not path_str or not path_str.strip():
            return
        val = path_str.strip()
        if val not in ("favorites://", "recent://", "trash://", "mediahub://"):
            val = os.path.abspath(os.path.expanduser(val))
        self.config_mgr.set("startup_path", val)
        self.sessionConfigChanged.emit()

    @Property(list, notify=iconGalleryChanged)
    def iconGalleryItems(self) -> list:
        return self._icon_gallery_items

    def _on_icon_gallery_ready(self, items: list):
        self._icon_gallery_items = items
        self.iconGalleryChanged.emit()

    @Slot(result=list)
    def getIconSearchRoots(self) -> list:
        custom_dir = self.config_mgr.get("custom_icons_dir", "")
        candidates = []
        if custom_dir and os.path.isdir(custom_dir):
            candidates.append(custom_dir)
        candidates.extend([
            str(Path.home() / ".local" / "share" / "icons"),
            str(Path.home() / ".icons"),
            "/usr/share/pixmaps",
            "/usr/share/icons/hicolor",
            "/usr/share/icons",
        ])
        valid = []
        for c in candidates:
            if os.path.isdir(c) and c not in valid:
                valid.append(c)
        return valid

    @Slot(str, str)
    def scanIconsRecursively(self, root_dir: str = "", search_filter: str = ""):
        if root_dir and os.path.isdir(root_dir):
            self.config_mgr.set("custom_icons_dir", os.path.abspath(root_dir))
            roots = [os.path.abspath(root_dir)]
        else:
            roots = self.getIconSearchRoots()
        task = IconGalleryScannerTask(roots, search_filter, self.signals)
        self.thread_pool.start(task)

    @Property(bool, notify=defaultFmStateChanged)
    def isDefaultFileManager(self) -> bool:
        return is_default_file_manager()

    @Slot(result=bool)
    def setAsDefaultFileManager(self) -> bool:
        main_script = str(Path(__file__).resolve().parent.parent / "main.py")
        ok = install_desktop_and_set_default(main_script)
        self.defaultFmStateChanged.emit()
        if ok:
            self.toastMessage.emit("✔ Find is now registered as the Default File Manager")
        return ok

    @Slot(str)
    def unmountDrive(self, mount_or_dev: str):
        if not mount_or_dev or mount_or_dev == "/":
            return

        def _unmount_worker():
            try:
                if shutil.which("udisksctl"):
                    res = subprocess.run(["udisksctl", "unmount", "-b", mount_or_dev], capture_output=True, text=True, timeout=5.0)
                    if res.returncode != 0:
                        res = subprocess.run(["gio", "mount", "-u", mount_or_dev], capture_output=True, text=True, timeout=5.0)
                elif shutil.which("gio"):
                    res = subprocess.run(["gio", "mount", "-u", mount_or_dev], capture_output=True, text=True, timeout=5.0)
                else:
                    res = subprocess.run(["umount", mount_or_dev], capture_output=True, text=True, timeout=5.0)

                if res.returncode == 0:
                    self.toastMessage.emit(f"⏏ Safely unmounted {Path(mount_or_dev).name}")
                    self._last_drives_ts = 0.0
                    self.sidebarUpdated.emit()
                else:
                    err = (res.stderr or res.stdout or "Unmount failed").strip()
                    self.toastMessage.emit(f"⚠️ Unmount error: {err}")
            except Exception as e:
                self.toastMessage.emit(f"⚠️ Unmount failed: {e}")

        QThreadPool.globalInstance().start(_unmount_worker)

    @Slot(result=list)
    def getDrives(self):
        now = time.time()
        if self._cached_drives and (now - self._last_drives_ts) < 5.0:
            hidden = set(self.config_mgr.get("hidden_sidebar_paths", []))
            return [d for d in self._cached_drives if d["path"] not in hidden]

        hidden = set(self.config_mgr.get("hidden_sidebar_paths", []))
        drives = []
        seen_mounts = set()
        ignored_fs = {
            "tmpfs", "devtmpfs", "squashfs", "overlay", "proc", "sysfs", "efivarfs",
            "securityfs", "cgroup", "cgroup2", "pstore", "bpf", "autofs", "ramfs",
            "debugfs", "tracefs", "configfs", "fusectl", "mqueue", "hugetlbfs", "nsfs"
        }

        try:
            with open("/proc/mounts", "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 3:
                        device, raw_mount, fstype = parts[0], parts[1], parts[2]
                        raw_bytes = re.sub(
                            rb'\\([0-7]{3})',
                            lambda m: bytes([int(m.group(1), 8)]),
                            raw_mount.encode("utf-8", errors="surrogateescape")
                        )
                        mount = raw_bytes.decode("utf-8", errors="replace")

                        if fstype in ignored_fs:
                            continue
                        is_valid_dev = (
                            device.startswith("/dev/")
                            or fstype in ("cifs", "smb3", "nfs", "nfs4", "sshfs", "fuse.sshfs", "fuse.rclone", "jmtpfs", "simple-mtpfs")
                            or mount.startswith(("/run/media/", "/media/", "/mnt/"))
                        )
                        if not is_valid_dev or mount in seen_mounts:
                            continue

                        is_target = (
                            mount == "/" or
                            mount.startswith("/run/media") or
                            mount.startswith("/media") or
                            mount.startswith("/mnt") or
                            "/gvfs/" in mount
                        )

                        if is_target:
                            seen_mounts.add(mount)
                            name = "Root System" if mount == "/" else Path(mount).name
                            usage_text = ""
                            usage_ratio = 0.0
                            try:
                                usage = shutil.disk_usage(mount)
                                if usage.total > 0:
                                    usage_ratio = round(min(1.0, max(0.0, usage.used / usage.total)), 3)
                                    used_s = self._format_size(usage.used).replace(" ", "")
                                    tot_s = self._format_size(usage.total).replace(" ", "")
                                    usage_text = f"{used_s}/{tot_s}"
                            except Exception:
                                pass
                            drives.append({
                                "name": name,
                                "path": mount,
                                "device": device,
                                "total": usage_text,
                                "usage_text": usage_text,
                                "usage_ratio": usage_ratio,
                                "icon": "🌐" if fstype in ("cifs", "smb3", "nfs", "nfs4", "sshfs", "fuse.sshfs") else ("💾" if "nvme" in device else "💽")
                            })
        except Exception:
            pass

        self._cached_drives = drives
        self._last_drives_ts = now
        return [d for d in drives if d["path"] not in hidden]
