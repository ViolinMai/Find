import os
import sys
import re
import stat as stat_mod
import json
import subprocess
import shutil
from datetime import datetime
from pathlib import Path
from PySide6.QtCore import QObject, Slot, Property, Signal, QRunnable, QThreadPool, QFileSystemWatcher, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtCore import QMimeData
from core.models import FileListModel
from core.config import ConfigManager
from core.thumbnails import ThumbnailManager, IMAGE_EXTS, VIDEO_EXTS
from core.search import SearchManager
from core.picker_context import PickerContext


class AsyncWorkerSignals(QObject):
    directoryLoaded = Signal(str, list)
    # Use object instead of 32-bit C++ int so folders > 2GB never overflow into negative bytes!
    folderSizeReady = Signal(str, object)
    mediaInfoReady = Signal(str, dict)


class DirectoryLoaderTask(QRunnable):
    def __init__(self, target_path_str: str, show_hidden: bool, picker_ctx, format_size_func, determine_icon_func, thumb_mgr, folder_size_cache, signals):
        super().__init__()
        self.target_path_str = target_path_str
        self.show_hidden = show_hidden
        self.picker_ctx = picker_ctx
        self.format_size_func = format_size_func
        self.determine_icon_func = determine_icon_func
        self.thumb_mgr = thumb_mgr
        self.folder_size_cache = folder_size_cache
        self.signals = signals

    def run(self):
        entries = []
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
    showHiddenChanged = Signal()
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

        self._view_mode = self.config_mgr.get("view_mode", "details")
        self._grid_columns = self.config_mgr.get("grid_columns", 0)
        self._grid_style = self.config_mgr.get("grid_style", "floating")
        self._sidebar_mode = self.config_mgr.get("sidebar_mode", "auto")
        self._sort_by = self.config_mgr.get("sort_by", "name")
        self._sort_ascending = self.config_mgr.get("sort_ascending", True)
        self._transparent_blur = self.config_mgr.get("transparent_blur", True)
        self._show_hidden = bool(self.config_mgr.get("show_hidden", False))
        self._selected_item = {}
        self._search_results = []
        self._clipboard_cut = False
        self._clipboard_path = ""
        self._folder_size_cache = {}
        self._calculating_folders = set()

        self.file_model = FileListModel(self)
        self.thread_pool = QThreadPool()
        self.thread_pool.setMaxThreadCount(4)

        self.signals = AsyncWorkerSignals()
        self.signals.directoryLoaded.connect(self._on_directory_loaded)
        self.signals.folderSizeReady.connect(self._on_folder_size_calculated)
        self.signals.mediaInfoReady.connect(self._on_media_info_ready)

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
            self.picker_ctx,
            self._format_size,
            self._determine_icon_and_type,
            self.thumb_mgr,
            self._folder_size_cache,
            self.signals
        )
        self.thread_pool.start(task)

    def _on_directory_loaded(self, path_loaded, entries):
        if str(self._current_path) in ("recent://", "trash://") or path_loaded != str(self._current_path):
            return

        self._sort_entries(entries)
        self._selected_item = {}
        self.selectedItemChanged.emit()
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

    def _sort_entries(self, entries):
        rev = not self._sort_ascending

        def natural_keys(text):
            return [int(c) if c.isdigit() else c for c in re.split(r'(\d+)', text.lower())]

        if self._sort_by == "name":
            key_func = lambda x: natural_keys(x["name"])
        elif self._sort_by == "size":
            key_func = lambda x: x["raw_size"]
        elif self._sort_by == "modified":
            key_func = lambda x: x["raw_mod"]
        elif self._sort_by == "created":
            key_func = lambda x: x["raw_created"]
        else:
            key_func = lambda x: natural_keys(x["name"])

        dirs = sorted([e for e in entries if e["is_dir"]], key=key_func, reverse=rev)
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
                subprocess.Popen(["xdg-open", str(path)], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    @Slot(str, str)
    def openWithApp(self, file_path_str: str, app_cmd: str):
        try:
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
        try:
            p = Path(file_path_str)
            if not p.exists():
                return
            target = self._get_unique_path(p.parent, f"{p.stem} (Copy)", p.suffix)
            if p.is_dir():
                shutil.copytree(p, target)
            else:
                shutil.copy2(p, target)
            self.refresh()
        except Exception:
            pass

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
        self._clipboard_path = file_path_str
        self._clipboard_cut = bool(is_cut)
        clipboard = QGuiApplication.clipboard()
        p = Path(file_path_str)
        if p.exists():
            mime = QMimeData()
            urls = [QUrl.fromLocalFile(str(p.resolve()))]
            mime.setUrls(urls)
            mime.setText(str(p.resolve()))
            op_word = "cut" if is_cut else "copy"
            mime.setData("x-special/gnome-copied-files", f"{op_word}\n{urls[0].toString()}".encode("utf-8"))
            clipboard.setMimeData(mime)

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
        self._clipboard_cut = False

    @Slot(str)
    def pasteToFolder(self, dest_folder_str: str):
        try:
            if not dest_folder_str or dest_folder_str in ("recent://", "trash://"):
                return
            clip_path = self.getClipboardPath()
            if not clip_path or not os.path.exists(clip_path):
                return
            op = "move" if self._clipboard_cut else "copy"
            ok = self.executeDropTransfer(clip_path, dest_folder_str, op, "keep_both")
            if ok and self._clipboard_cut:
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

    @Slot()
    def goForward(self):
        if self._history_idx < len(self._history) - 1:
            self._history_idx += 1
            self.load_directory(self._history[self._history_idx])
            self._update_history_state()

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
    def selectItem(self, path: str, name: str, is_dir: bool, size: str, modified: str, file_type: str):
        if self.picker_ctx.isActive:
            self.picker_ctx.toggleSelect(path, is_dir)

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

    @Slot()
    def clearSelection(self):
        self._selected_item = {}
        self.selectedItemChanged.emit()

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
        try:
            if not file_path_str or not os.path.exists(file_path_str):
                return
            self.thumb_mgr.remove_thumbnail_for_path(file_path_str)
            self.config_mgr.clean_cache()
            self.cacheSizeChanged.emit()

            if shutil.which("gio"):
                res = subprocess.run(["gio", "trash", file_path_str], capture_output=True)
                if res.returncode == 0:
                    self.refresh()
                    return
            if shutil.which("trash-put"):
                res = subprocess.run(["trash-put", file_path_str], capture_output=True)
                if res.returncode == 0:
                    self.refresh()
                    return

            xdg_data = os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share"))
            t_files = Path(xdg_data) / "Trash" / "files"
            t_files.mkdir(parents=True, exist_ok=True)
            src = Path(file_path_str)
            dest = self._get_unique_path(t_files, src.stem, src.suffix)
            shutil.move(str(src), str(dest))
            self.refresh()
        except Exception:
            pass

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
