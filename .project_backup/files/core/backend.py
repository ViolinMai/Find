import os
import sys
import re
import time
import socket
import hashlib
import tempfile
import stat as stat_mod
import json
import subprocess
import shutil
from datetime import datetime
from pathlib import Path
from PySide6.QtCore import QObject, Slot, Property, Signal, QRunnable, QThreadPool, QFileSystemWatcher, QUrl, Qt
from PySide6.QtGui import QGuiApplication, QDrag, QPixmap, QPainter, QColor, QFont
from PySide6.QtCore import QMimeData
from core.models import FileListModel
from core.config import ConfigManager
from core.thumbnails import ThumbnailManager, IMAGE_EXTS, VIDEO_EXTS

SUBTITLE_EXTS = {".srt", ".ass", ".ssa", ".sub", ".vtt", ".idx", ".sup", ".smi"}
FONT_EXTS = {".ttf", ".otf", ".woff", ".woff2", ".ttc"}
from core.search import SearchManager
from core.picker_context import PickerContext


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
        for fpath, mtime in self.items_to_probe:
            try:
                is_hdr = detect_video_hdr_sync(fpath)
                self.config_mgr.set_cached_hdr(fpath, mtime, is_hdr)
                self.signals.hdrStatusDetected.emit(fpath, is_hdr)
            except Exception:
                pass


class AsyncWorkerSignals(QObject):
    directoryLoaded = Signal(str, list)
    # Use object instead of 32-bit C++ int so folders > 2GB never overflow into negative bytes!
    folderSizeReady = Signal(str, object)
    mediaInfoReady = Signal(str, dict)
    mpvProgressUpdated = Signal(str, float, float, bool)
    mpvExternalSubDetected = Signal(str, str)
    mpvHdrSessionEnded = Signal(int)
    hdrStatusDetected = Signal(str, bool)


class MpvSessionMonitorTask(QRunnable):
    """
    Connects to mpv's JSON IPC socket while playing a video from a Media Library
    and streams live playback progress, episode changes, and drag-and-dropped subtitles back to Find.
    Also automatically turns off HDR via toggle-hdr.sh --off when an HDR mpv session exits.
    """
    def __init__(self, file_path_str: str, ipc_sock_path: str, proc, hdr_mode: bool, initial_start_pos: float, get_progress_func, signals):
        super().__init__()
        self.file_path_str = file_path_str
        self.ipc_sock_path = ipc_sock_path
        self.proc = proc
        self.hdr_mode = hdr_mode
        self.initial_start_pos = float(initial_start_pos or 0.0)
        self.get_progress_func = get_progress_func
        self.signals = signals

    def _send_ipc_command(self, sock, cmd_list: list, req_id: int = 99):
        try:
            payload = json.dumps({"command": cmd_list, "request_id": req_id}) + "\n"
            sock.sendall(payload.encode("utf-8"))
        except Exception:
            pass

    def _query_ipc_property(self, sock, prop_name: str, req_id: int):
        cmd = json.dumps({"command": ["get_property", prop_name], "request_id": req_id}) + "\n"
        sock.sendall(cmd.encode("utf-8"))
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
        for line in buf.decode("utf-8", errors="ignore").splitlines():
            try:
                msg = json.loads(line)
                if msg.get("request_id") == req_id and msg.get("error") == "success":
                    return msg.get("data")
            except Exception:
                pass
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
                        cur_mpv_path = self._query_ipc_property(s, "path", 4)
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

                            # Load saved subtitle or saved position for the newly switched episode (or start at 0.0)
                            saved_next = self.get_progress_func(active_file) if callable(self.get_progress_func) else {}
                            next_sub = saved_next.get("ext_sub", "")
                            if next_sub and os.path.exists(next_sub):
                                self._send_ipc_command(s, ["sub-add", next_sub, "select"], 10)
                                last_recorded_sub = next_sub
                            if not saved_next.get("watched", False) and saved_next.get("position", 0.0) > 5.0:
                                self._send_ipc_command(s, ["set_property", "time-pos", float(saved_next["position"])], 11)
                            else:
                                self._send_ipc_command(s, ["set_property", "time-pos", 0.0], 11)
                            time.sleep(0.35)
                            continue

                        dur_val = self._query_ipc_property(s, "duration", 2)
                        pos_val = self._query_ipc_property(s, "time-pos", 1)
                        eof_val = self._query_ipc_property(s, "eof-reached", 3)

                        if isinstance(dur_val, (int, float)) and dur_val > 0:
                            duration = float(dur_val)
                            # Perform initial resume seek ONLY for the first launched file via IPC (never global --start!)
                            if not initial_seek_done:
                                initial_seek_done = True
                                if self.initial_start_pos > 5.0 and self.initial_start_pos < duration * 0.95:
                                    self._send_ipc_command(s, ["set_property", "time-pos", self.initial_start_pos], 12)
                                    pos_val = self.initial_start_pos

                        if isinstance(pos_val, (int, float)) and pos_val >= 0:
                            # Guard against stale time-pos right after switching files in MPV
                            if file_switch_ts > 0 and (time.time() - file_switch_ts) < 2.0:
                                if prev_file_final_pos > 30.0 and abs(float(pos_val) - prev_file_final_pos) < 5.0:
                                    continue
                            last_pos = float(pos_val)

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
                except Exception:
                    pass
            time.sleep(0.8)

        # Clean up socket file
        try:
            if os.path.exists(self.ipc_sock_path):
                os.unlink(self.ipc_sock_path)
        except OSError:
            pass

        # Final check on exit for whichever episode was playing last
        wl_pos = self._read_mpv_watch_later_pos(active_file)
        if wl_pos >= 0 and (file_switch_ts == 0.0 or abs(wl_pos - prev_file_final_pos) > 5.0):
            last_pos = wl_pos
        if duration > 0 and last_pos > 0:
            is_done = eof_reached or (last_pos / duration >= 0.90)
            self.signals.mpvProgressUpdated.emit(active_file, last_pos, duration, is_done)

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
                            "is_hdr": is_hdr
                        })
        except Exception:
            pass

        self.signals.directoryLoaded.emit(self.target_path_str, entries)


class MediaInfoTask(QRunnable):
    def __init__(self, file_path_str: str, signals):
        super().__init__()
        self.file_path_str = file_path_str
        self.signals = signals

    def run(self):
        info = {
            "resolution": "",
            "codec": "",
            "bit_depth": "",
            "color_profile": "",
            "bitrate": "",
            "fps": "",
            "audio_codec": ""
        }
        if shutil.which("ffprobe"):
            try:
                cmd = [
                    "ffprobe", "-v", "quiet", "-print_format", "json",
                    "-show_streams", "-show_format", self.file_path_str
                ]
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=1.5)
                if res.returncode == 0:
                    data = json.loads(res.stdout)
                    streams = data.get("streams", [])
                    v_stream = next((s for s in streams if s.get("codec_type") == "video"), None)
                    a_stream = next((s for s in streams if s.get("codec_type") == "audio"), None)
                    fmt = data.get("format", {})

                    if v_stream:
                        w, h = v_stream.get("width"), v_stream.get("height")
                        if w and h:
                            info["resolution"] = f"{w}x{h}"
                        info["codec"] = v_stream.get("codec_name", "").upper()

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

                    if a_stream:
                        info["audio_codec"] = a_stream.get("codec_name", "").upper()
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
    mediaLibraryStateChanged = Signal()
    showSubtitlesChanged = Signal()
    tabsChanged = Signal()
    cacheSizeChanged = Signal()
    maxCacheMbChanged = Signal()
    transparentBlurChanged = Signal()
    sidebarUpdated = Signal()
    searchResultsChanged = Signal()
    folderSizeReady = Signal(str, str)
    pickerCompleted = Signal(list)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.config_mgr = ConfigManager()
        self.picker_ctx = PickerContext(self)

        self._current_path = os.path.abspath(str(Path.home()))
        self._history = [self._current_path]
        self._history_idx = 0
        self._tabs = [{
            "path": self._current_path,
            "title": "Home",
            "history": [self._current_path],
            "history_idx": 0
        }]
        self._active_tab_index = 0

        self._view_mode = self.config_mgr.get("view_mode", "details")
        self._grid_columns = self.config_mgr.get("grid_columns", 0)
        self._grid_style = self.config_mgr.get("grid_style", "floating")
        self._sidebar_mode = self.config_mgr.get("sidebar_mode", "auto")
        self._sort_by = self.config_mgr.get("sort_by", "name")
        self._sort_ascending = self.config_mgr.get("sort_ascending", True)
        self._transparent_blur = self.config_mgr.get("transparent_blur", True)
        self._show_hidden = bool(self.config_mgr.get("show_hidden", False))
        self._swap_mouse_buttons = bool(self.config_mgr.get("swap_mouse_buttons", False))
        self._auto_play_hdr = bool(self.config_mgr.get("auto_play_hdr", True))
        self._show_subtitles_in_media = False
        self._active_hdr_pids = set()
        self._selected_item = {}
        self._selected_paths = []
        self._last_selected_row = -1
        self._search_results = []
        self._clipboard_cut = False
        self._clipboard_path = ""
        self._clipboard_paths = []
        self._folder_size_cache = {}
        self._calculating_folders = set()

        self.file_model = FileListModel(self)
        self.thread_pool = QThreadPool()
        self.thread_pool.setMaxThreadCount(4)

        self.signals = AsyncWorkerSignals()
        self.signals.directoryLoaded.connect(self._on_directory_loaded)
        self.signals.folderSizeReady.connect(self._on_folder_size_calculated)
        self.signals.mediaInfoReady.connect(self._on_media_info_ready)
        self.signals.mpvProgressUpdated.connect(self._on_mpv_progress_updated)
        self.signals.mpvExternalSubDetected.connect(self._on_mpv_external_sub_detected)
        self.signals.mpvHdrSessionEnded.connect(self._on_mpv_hdr_session_ended)
        self.signals.hdrStatusDetected.connect(self._on_hdr_status_detected)

        self.watcher = QFileSystemWatcher(self)
        self.watcher.directoryChanged.connect(self._on_dir_changed_externally)

        self.thumb_mgr = ThumbnailManager(self.config_mgr.cache_dir, self)
        self.thumb_mgr.thumbnailReady.connect(self._on_thumbnail_ready)
        self.thumb_mgr.folderPreviewReady.connect(self._on_folder_preview_ready)

        self.search_mgr = SearchManager(self.config_mgr.cache_dir, self)
        self.search_mgr.searchResultsReady.connect(self._on_search_results_ready)

        self.load_directory(self._current_path)
        self.config_mgr.clean_cache()

        QThreadPool.globalInstance().start(lambda: self.search_mgr.build_incremental_index(self._get_indexable_roots()))

    @Property(QObject, constant=True)
    def picker(self):
        return self.picker_ctx

    @Property(str, notify=currentPathChanged)
    def currentPath(self):
        return str(self._current_path)

    @Property(str, constant=True)
    def trashPath(self):
        return "trash://"

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

    def _on_hdr_status_detected(self, file_path_str: str, is_hdr: bool):
        self.file_model.update_hdr_status(file_path_str, is_hdr)
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
        if not path_str or path_str in ("recent://", "trash://"):
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
                self.refresh()
                return
        libs.append({
            "name": Path(norm_p).name or norm_p,
            "path": norm_p,
            "mode": mode if mode in ("series", "movies") else "series"
        })
        self.config_mgr.set("media_libraries", libs)
        self.mediaLibraryStateChanged.emit()
        self.refresh()

    @Slot(str)
    def removeMediaLibrary(self, folder_path: str):
        norm_p = os.path.abspath(os.path.expanduser(folder_path)) if folder_path else ""
        libs = [x for x in self.getMediaLibraries() if x["path"] != norm_p and x["path"] != folder_path]
        self.config_mgr.set("media_libraries", libs)
        self.mediaLibraryStateChanged.emit()
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
        cur = self.config_mgr.get_media_progress(file_path_str)
        dur = cur.get("duration", 100.0) or 100.0
        pos = dur if watched else 0.0
        updated = self.config_mgr.set_media_progress(file_path_str, pos, dur, watched=watched)
        self.file_model.update_media_progress(file_path_str, updated["progress"], updated["watched"])

    def _on_mpv_progress_updated(self, file_path_str: str, pos: float, duration: float, is_done: bool):
        updated = self.config_mgr.set_media_progress(file_path_str, pos, duration, watched=is_done)
        self.file_model.update_media_progress(file_path_str, updated["progress"], updated["watched"])

    def _on_mpv_external_sub_detected(self, file_path_str: str, sub_path_str: str):
        self.config_mgr.set_media_external_sub(file_path_str, sub_path_str)

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
            elif ln == "osc=no":
                ln = "osc=yes"

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

        mpv_conf_dir = Path.home() / ".config" / "mpv"
        mpv_conf_dir.mkdir(parents=True, exist_ok=True)
        mpv_conf_file = mpv_conf_dir / "mpv.conf"

        try:
            with open(mpv_conf_file, "w", encoding="utf-8") as f:
                f.write("\n".join(final_lines) + "\n")
        except Exception:
            pass
        return str(mpv_conf_file)

    def _launch_in_mpv_with_tracking(self, file_path_str: str, hdr_mode: bool = False):
        if hdr_mode:
            _run_toggle_hdr_script("--on")

        sock_path = os.path.join(tempfile.gettempdir(), f"find_mpv_{os.getpid()}_{int(time.time() * 1000)}.sock")
        self._write_system_mpv_conf(hdr_mode=hdr_mode)
        saved = self.config_mgr.get_media_progress(file_path_str)

        if saved.get("watched", False):
            try:
                md5_hex = hashlib.md5(os.path.abspath(file_path_str).encode("utf-8")).hexdigest().upper()
                for wl_f in (
                    Path.home() / ".local" / "state" / "mpv" / "watch_later" / md5_hex,
                    Path.home() / ".config" / "mpv" / "watch_later" / md5_hex,
                ):
                    if wl_f.exists():
                        wl_f.unlink()
            except Exception:
                pass

        initial_pos = 0.0
        if not saved.get("watched", False) and saved.get("position", 0.0) > 5.0:
            initial_pos = float(saved["position"])

        cmd = [
            "mpv",
            f"--input-ipc-server={sock_path}",
            "--no-resume-playback"
        ]
        ext_sub = saved.get("ext_sub", "")
        if ext_sub and os.path.exists(ext_sub):
            cmd.append(f"--sub-file={ext_sub}")

        cmd.append(file_path_str)

        proc = subprocess.Popen(
            cmd,
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        if hdr_mode:
            self._active_hdr_pids.add(int(proc.pid))

        monitor = MpvSessionMonitorTask(
            file_path_str,
            sock_path,
            proc,
            hdr_mode,
            initial_pos,
            self.config_mgr.get_media_progress,
            self.signals
        )
        QThreadPool.globalInstance().start(monitor)

    def _tab_title_for_path(self, path_str: str) -> str:
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

    def _sync_current_tab_state(self):
        if 0 <= self._active_tab_index < len(self._tabs):
            tab = self._tabs[self._active_tab_index]
            tab["path"] = str(self._current_path)
            tab["title"] = self._tab_title_for_path(str(self._current_path))
            tab["history"] = list(self._history)
            tab["history_idx"] = self._history_idx
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
        if target not in ("recent://", "trash://"):
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
        if self._view_mode != mode:
            self._view_mode = mode
            if str(self._current_path) != "recent://":
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

    def _on_dir_changed_externally(self, path):
        if path == str(self._current_path):
            self.refresh()

    def _on_thumbnail_ready(self, file_path, thumb_path):
        self.file_model.update_thumbnail(file_path, thumb_path)
        if self._selected_item.get("path") == file_path:
            self._selected_item["thumb"] = thumb_path
            self.selectedItemChanged.emit()

    def _on_folder_preview_ready(self, folder_path, previews):
        self.file_model.update_folder_previews(folder_path, previews)
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

    def _load_trash_directory(self):
        self._current_path = "trash://"
        self.currentPathChanged.emit()
        self.breadcrumbsChanged.emit()

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
        self._selected_item = {}
        self.selectedItemChanged.emit()
        self.file_model.set_entries(entries)

    def load_directory(self, target_path_str: str):
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

        fv = self.config_mgr.get_folder_view(target_resolved)
        if not fv:
            views = self.config_mgr.get("folder_views", {})
            for ancestor in target_path.parents:
                anc_str = str(ancestor)
                if anc_str in views and views[anc_str].get("cascade"):
                    fv = views[anc_str]
                    break

        in_lib, is_movie = self._check_path_in_media_library(target_resolved)
        self.mediaLibraryStateChanged.emit()

        if fv:
            new_vm = fv.get("view_mode", self._view_mode)
            new_sb = fv.get("sort_by", self._sort_by)
            new_sa = fv.get("sort_ascending", self._sort_ascending)
        else:
            new_vm = self.config_mgr.get("view_mode", "details")
            new_sb = self.config_mgr.get("sort_by", "name")
            new_sa = self.config_mgr.get("sort_ascending", True)

        if self._view_mode != new_vm:
            self._view_mode = new_vm
            self.viewModeChanged.emit()
        if self._sort_by != new_sb:
            self._sort_by = new_sb
            self.sortByChanged.emit()
        if self._sort_ascending != new_sa:
            self._sort_ascending = new_sa
            self.sortOrderChanged.emit()

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
        self.thread_pool.start(task)

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
        if str(self._current_path) in ("recent://", "trash://") or path_loaded != str(self._current_path):
            return

        in_lib, is_movie = self._check_path_in_media_library(path_loaded)
        is_episode_folder = (in_lib and not is_movie and self._is_predominantly_video_folder(entries))

        # Only force ascending episode order when the current folder itself is >= 90% videos,
        # unless the user explicitly saved a custom sort for this exact episode folder!
        if is_episode_folder:
            exact_fv = self.config_mgr.get_folder_view(path_loaded)
            if not exact_fv:
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

            if unprobed_hdr:
                hdr_task = HdrBatchDetectorTask(unprobed_hdr, self.config_mgr, self.signals)
                self.thread_pool.start(hdr_task)
        else:
            self._sort_entries(entries)

        self._selected_item = {}
        self._selected_paths = []
        self._last_selected_row = -1
        self.selectedItemChanged.emit()
        self.selectedPathsChanged.emit()
        self.file_model.set_entries(entries)

    def _load_recent_directory(self):
        self._current_path = "recent://"
        self.currentPathChanged.emit()
        self.breadcrumbsChanged.emit()

        hidden_mounts = set(self.config_mgr.get("hidden_sidebar_paths", []))
        allowed_roots = [r for r in self._get_indexable_roots() if r not in hidden_mounts]

        recent_items = []
        seen_files = set()
        count = 0

        for dir_path, meta in list(self.search_mgr.index_data.items()):
            if any(dir_path == hm or dir_path.startswith(hm.rstrip("/") + "/") for hm in hidden_mounts):
                continue
            if not any(dir_path == ar or dir_path.startswith(ar.rstrip("/") + "/") for ar in allowed_roots):
                continue
            for f in meta.get("files", []):
                if not self._show_hidden and f.startswith("."):
                    continue
                full_p = os.path.join(dir_path, f)
                if full_p in seen_files:
                    continue
                try:
                    st = os.stat(full_p)
                    seen_files.add(full_p)
                    mtime = st.st_mtime
                    ctime = getattr(st, "st_birthtime", st.st_ctime)
                    raw_sz = max(0, int(st.st_size))
                    icon, file_type = self._determine_icon_and_type(Path(full_p), False)
                    recent_items.append({
                        "name": f,
                        "path": full_p,
                        "is_dir": False,
                        "size": self._format_size(raw_sz),
                        "modified": datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M"),
                        "created": datetime.fromtimestamp(ctime).strftime("%Y-%m-%d %H:%M"),
                        "icon": icon,
                        "type": file_type,
                        "raw_size": raw_sz,
                        "raw_mod": mtime,
                        "raw_created": ctime,
                        "thumb": self.thumb_mgr.get_existing_thumbnail(full_p),
                        "folder_previews": []
                    })
                    count += 1
                    if count >= 450:
                        break
                except OSError:
                    pass
            if count >= 450:
                break

        for root_mp in allowed_roots:
            if root_mp == str(Path.home()):
                continue
            queue = [(root_mp, 0)]
            visited = 0
            while queue and visited < 20:
                curr, depth = queue.pop(0)
                visited += 1
                try:
                    with os.scandir(curr) as it:
                        for entry in it:
                            if not self._show_hidden and entry.name.startswith("."):
                                continue
                            if entry.name.startswith(".Trash"):
                                continue
                            try:
                                if entry.is_dir(follow_symlinks=False) and depth < 2:
                                    queue.append((entry.path, depth + 1))
                                elif entry.is_file(follow_symlinks=False) and entry.path not in seen_files:
                                    st = entry.stat(follow_symlinks=False)
                                    seen_files.add(entry.path)
                                    mtime = st.st_mtime
                                    ctime = getattr(st, "st_birthtime", st.st_ctime)
                                    raw_sz = max(0, int(st.st_size))
                                    icon, file_type = self._determine_icon_and_type(Path(entry.path), False)
                                    recent_items.append({
                                        "name": entry.name,
                                        "path": entry.path,
                                        "is_dir": False,
                                        "size": self._format_size(raw_sz),
                                        "modified": datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M"),
                                        "created": datetime.fromtimestamp(ctime).strftime("%Y-%m-%d %H:%M"),
                                        "icon": icon,
                                        "type": file_type,
                                        "raw_size": raw_sz,
                                        "raw_mod": mtime,
                                        "raw_created": ctime,
                                        "thumb": self.thumb_mgr.get_existing_thumbnail(entry.path),
                                        "folder_previews": []
                                    })
                            except OSError:
                                pass
                except OSError:
                    pass

        recent_items.sort(key=lambda x: max(x["raw_mod"], x["raw_created"]), reverse=True)
        final_entries = recent_items[:120]

        self._selected_item = {}
        self.selectedItemChanged.emit()
        self.file_model.set_entries(final_entries)

    def _sort_entries(self, entries, is_series_lib: bool = False):
        rev = not self._sort_ascending

        def natural_keys(text):
            return [int(c) if c.isdigit() else c for c in re.split(r'(\d+)', text.lower())]

        if is_series_lib and self._sort_by == "name":
            key_func = lambda x: (
                0 if x.get("_ep_sort") is not None else 1,
                float(x["_ep_sort"]) if x.get("_ep_sort") is not None else float("inf"),
                natural_keys(x["name"])
            )
        elif self._sort_by == "name":
            key_func = lambda x: natural_keys(x["name"])
        elif self._sort_by == "size":
            key_func = lambda x: x["raw_size"]
        elif self._sort_by == "modified":
            key_func = lambda x: x["raw_mod"]
        elif self._sort_by == "created":
            key_func = lambda x: x["raw_created"]
        else:
            key_func = lambda x: natural_keys(x["name"])

        dir_key = lambda x: natural_keys(x["name"]) if self._sort_by == "name" else key_func(x)
        dirs = sorted([e for e in entries if e["is_dir"]], key=dir_key, reverse=rev)
        files = sorted([e for e in entries if not e["is_dir"]], key=key_func, reverse=rev)
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

    @Slot(str)
    def openEntry(self, file_path_str: str):
        if file_path_str in ("recent://", "trash://"):
            self.navigateTo(file_path_str)
            return

        path = Path(file_path_str)
        if path.is_dir():
            self.navigateTo(str(path))
        else:
            if self.picker_ctx.isActive:
                self.picker_ctx.setSelectedPath(str(path))
                self.confirmPickerSelection()
            else:
                if path.suffix.lower() in VIDEO_EXTS and shutil.which("mpv"):
                    use_hdr = False
                    in_lib, _ = self._check_path_in_media_library(str(path))
                    if in_lib and self._auto_play_hdr:
                        try:
                            mtime = path.stat().st_mtime
                            cached_hdr = self.config_mgr.get_cached_hdr(str(path), mtime)
                            if cached_hdr is None:
                                cached_hdr = detect_video_hdr_sync(str(path))
                                self.config_mgr.set_cached_hdr(str(path), mtime, cached_hdr)
                                self.file_model.update_hdr_status(str(path), cached_hdr)
                            use_hdr = bool(cached_hdr)
                        except Exception:
                            use_hdr = False
                    self._launch_in_mpv_with_tracking(str(path), hdr_mode=use_hdr)
                else:
                    subprocess.Popen(["xdg-open", str(path)], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

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

    @Slot(str, result=list)
    def getAvailableApps(self, file_path_str: str):
        apps = []
        candidates = [
            ("Kate", "kate"),
            ("KWrite", "kwrite"),
            ("Vim", "vim"),
            ("Nano", "nano"),
            ("VS Code", "code"),
            ("GIMP", "gimp"),
            ("VLC", "vlc"),
            ("mpv", "mpv")
        ]
        for name, cmd in candidates:
            if shutil.which(cmd):
                apps.append({"name": name, "cmd": cmd})
        return apps

    @Slot(str)
    def duplicateItem(self, file_path_str: str):
        targets = self._selected_paths if (file_path_str in self._selected_paths and len(self._selected_paths) > 1) else [file_path_str]
        for fp in targets:
            try:
                p = Path(fp)
                if not p.exists():
                    continue
                target = self._get_unique_path(p.parent, f"{p.stem} (Copy)", p.suffix)
                if p.is_dir():
                    shutil.copytree(p, target)
                else:
                    shutil.copy2(p, target)
            except Exception:
                pass
        self.refresh()

    @Slot(str, str)
    def renameItem(self, file_path_str: str, new_name: str):
        try:
            p = Path(file_path_str)
            if not p.exists() or not new_name.strip():
                return
            target = p.parent / new_name.strip()
            if not target.exists():
                p.rename(target)
                self.refresh()
        except Exception:
            pass

    @Slot(str, bool)
    def stageClipboard(self, file_path_str: str, is_cut: bool):
        if not file_path_str:
            return
        targets = list(self._selected_paths) if (file_path_str in self._selected_paths and len(self._selected_paths) > 1) else [file_path_str]
        valid_paths = [str(Path(fp).resolve()) for fp in targets if os.path.exists(fp)]
        if not valid_paths:
            return
        self._clipboard_path = valid_paths[0]
        self._clipboard_paths = valid_paths
        self._clipboard_cut = bool(is_cut)
        clipboard = QGuiApplication.clipboard()
        mime = QMimeData()
        urls = [QUrl.fromLocalFile(vp) for vp in valid_paths]
        mime.setUrls(urls)
        mime.setText("\n".join(valid_paths))
        op_word = "cut" if is_cut else "copy"
        gnome_payload = op_word + "\n" + "\n".join(u.toString() for u in urls)
        mime.setData("x-special/gnome-copied-files", gnome_payload.encode("utf-8"))
        clipboard.setMimeData(mime)

    @Slot(result=list)
    def getClipboardPaths(self) -> list:
        if self._clipboard_paths:
            existing = [p for p in self._clipboard_paths if os.path.exists(p)]
            if existing:
                return existing
        single = self.getClipboardPath()
        return [single] if single else []

    @Slot(result=str)
    def getClipboardPath(self):
        if self._clipboard_path and os.path.exists(self._clipboard_path):
            return self._clipboard_path
        try:
            clipboard = QGuiApplication.clipboard()
            mime = clipboard.mimeData()
            if mime is not None:
                if mime.hasUrls():
                    for u in mime.urls():
                        local = u.toLocalFile()
                        if local and os.path.exists(local):
                            return local
                txt = mime.text().strip() if mime.hasText() else ""
                if txt.startswith("file://"):
                    local = QUrl(txt).toLocalFile()
                    if local and os.path.exists(local):
                        return local
                elif txt and os.path.exists(txt):
                    return txt
        except Exception:
            pass
        return ""

    @Slot(result=bool)
    def isClipboardCut(self):
        return self._clipboard_cut

    @Slot()
    def clearClipboardStage(self):
        self._clipboard_path = ""
        self._clipboard_paths = []
        self._clipboard_cut = False

    @Slot(str)
    def pasteToFolder(self, dest_folder_str: str):
        try:
            if not dest_folder_str or dest_folder_str in ("recent://", "trash://"):
                return
            clip_paths = self.getClipboardPaths()
            if not clip_paths:
                return
            op = "move" if self._clipboard_cut else "copy"
            any_ok = False
            for cp in clip_paths:
                if os.path.exists(cp):
                    if self.executeDropTransfer(cp, dest_folder_str, op, "keep_both"):
                        any_ok = True
            if any_ok and self._clipboard_cut:
                self.clearClipboardStage()
        except Exception:
            pass

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
            if dest_dir_str == "recent://":
                return False
            src = Path(src_path_str)
            dest_dir = Path(dest_dir_str)
            if not src.exists() or not dest_dir.exists() or not dest_dir.is_dir():
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
                elif conflict_resolution == "replace":
                    if target.is_dir() and not target.is_symlink():
                        shutil.rmtree(target)
                    else:
                        target.unlink()

            if operation == "move":
                shutil.move(str(src), str(target))
            elif operation == "copy":
                if src.is_dir():
                    shutil.copytree(str(src), str(target))
                else:
                    shutil.copy2(str(src), str(target))

            self.refresh()
            return True
        except Exception:
            return False

    @Slot(str, str)
    def compressItem(self, file_path_str: str, archive_format: str):
        try:
            p = Path(file_path_str)
            if not p.exists():
                return
            if archive_format == "zip":
                shutil.make_archive(str(p.parent / p.stem), 'zip', str(p.parent), p.name)
            elif archive_format == "tar.gz":
                shutil.make_archive(str(p.parent / p.stem), 'gztar', str(p.parent), p.name)
            self.refresh()
        except Exception:
            pass

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
    def goToParentFolder(self, file_path_str: str):
        p = Path(file_path_str)
        parent = p.parent
        if parent.exists() and parent.is_dir():
            self.openEntry(str(parent))
            self.selectItem(str(p), p.name, p.is_dir(), "", "", "")

    @Slot()
    def goUp(self):
        if str(self._current_path) in ("recent://", "trash://"):
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
        if path_str in ("recent://", "trash://"):
            target = path_str
        else:
            target = os.path.expanduser(os.path.expandvars(path_str))
            if target.startswith("file://"):
                target = QUrl(path_str).toLocalFile() or target[7:]
            target = os.path.abspath(target)
            if not os.path.exists(target):
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
        if self.picker_ctx.isActive and self.picker_ctx.mode == "folder" and target not in ("recent://", "trash://"):
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

        if str(self._current_path) != "recent://":
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
        if self.picker_ctx.isActive:
            self.picker_ctx.toggleSelect(path, is_dir)

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
                        task = MediaInfoTask(path, self.signals)
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

        self._selected_item = {
            "path": path,
            "name": name,
            "is_dir": is_dir,
            "size": size,
            "modified": modified,
            "type": file_type,
            "preview_text": preview_text,
            "is_image": is_image,
            "is_video": is_video,
            "thumb": thumb,
            "folder_previews": folder_previews,
            "resolution": "",
            "codec": "",
            "bit_depth": "",
            "color_profile": "",
            "bitrate": "",
            "fps": "",
            "audio_codec": ""
        }
        self.selectedItemChanged.emit()

    def _on_media_info_ready(self, file_path_str, info):
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
        self.picker_ctx.deactivate()
        self.load_directory(str(self._current_path))
        if getattr(self, "_launched_as_picker", False):
            QGuiApplication.exit(1)

    @Slot(str, str, str)
    def openInternalPicker(self, mode: str, filter_str: str, title: str):
        self.picker_ctx.activate(mode, filter_str, title)
        self.load_directory(str(self._current_path))

    def _get_unique_path(self, parent_dir: Path, base_name: str, ext: str = "") -> Path:
        target = parent_dir / f"{base_name}{ext}"
        counter = 2
        while target.exists():
            target = parent_dir / f"{base_name} ({counter}){ext}"
            counter += 1
        return target

    @Slot(str, str)
    def createItem(self, item_type: str, item_name: str):
        if str(self._current_path) == "recent://":
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
        clipboard = QGuiApplication.clipboard()
        p = Path(path_or_text)
        if p.exists():
            mime = QMimeData()
            urls = [QUrl.fromLocalFile(str(p.resolve()))]
            mime.setUrls(urls)
            mime.setText(str(p))
            mime.setData("x-special/gnome-copied-files", f"copy\n{urls[0].toString()}".encode("utf-8"))
            clipboard.setMimeData(mime)
        else:
            clipboard.setText(path_or_text)

    @Slot(str)
    def openInTerminal(self, dir_path_str: str):
        if dir_path_str == "recent://":
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
        moved_any = False
        for fp in targets:
            try:
                if not fp or not os.path.exists(fp):
                    continue
                self.thumb_mgr.remove_thumbnail_for_path(fp)
                if shutil.which("gio"):
                    res = subprocess.run(["gio", "trash", fp], capture_output=True)
                    if res.returncode == 0:
                        moved_any = True
                        continue
                if shutil.which("trash-put"):
                    res = subprocess.run(["trash-put", fp], capture_output=True)
                    if res.returncode == 0:
                        moved_any = True
                        continue

                xdg_data = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))
                t_files = Path(xdg_data) / "Trash" / "files"
                t_files.mkdir(parents=True, exist_ok=True)
                src = Path(fp)
                dest = self._get_unique_path(t_files, src.stem, src.suffix)
                shutil.move(str(src), str(dest))
                moved_any = True
            except Exception:
                pass
        if moved_any:
            self.config_mgr.clean_cache()
            self.cacheSizeChanged.emit()
            self.refresh()

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

    @Slot(str)
    def searchFast(self, query: str):
        self.search_mgr.query(query)

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

    @Slot(result=list)
    def getDrives(self):
        hidden = set(self.config_mgr.get("hidden_sidebar_paths", []))
        drives = []
        seen_mounts = set()
        ignored_fs = {
            "tmpfs", "devtmpfs", "squashfs", "overlay", "proc", "sysfs", "efivarfs",
            "securityfs", "cgroup", "cgroup2", "pstore", "bpf", "autofs", "ramfs"
        }

        try:
            with open("/proc/mounts", "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 3:
                        device, mount, fstype = parts[0], parts[1], parts[2]
                        mount = mount.encode().decode('unicode-escape')
                        if fstype in ignored_fs or not device.startswith("/dev/"):
                            continue
                        if mount in seen_mounts or mount in hidden:
                            continue

                        is_target = (
                            mount == "/" or
                            mount.startswith("/run/media") or
                            mount.startswith("/media") or
                            mount.startswith("/mnt")
                        )

                        if is_target and os.path.exists(mount):
                            seen_mounts.add(mount)
                            name = "Root System" if mount == "/" else Path(mount).name
                            drives.append({
                                "name": name,
                                "path": mount,
                                "device": device,
                                "total": "",
                                "icon": "💾" if "nvme" in device else "💽"
                            })
        except Exception:
            pass

        return drives
