import os
import sys
import json
import subprocess
import shutil
from datetime import datetime
from pathlib import Path
from PySide6.QtCore import QObject, Slot, Property, Signal, QRunnable, QThreadPool
from PySide6.QtGui import QGuiApplication
from core.models import FileListModel
from core.config import ConfigManager
from core.thumbnails import ThumbnailManager, IMAGE_EXTS, VIDEO_EXTS
from core.search import SearchManager
from core.picker_context import PickerContext


class FolderSizeTask(QRunnable):
    def __init__(self, dir_path: str, finish_callback):
        super().__init__()
        self.dir_path = dir_path
        self.finish_callback = finish_callback

    def run(self):
        total = 0
        try:
            for root, _, files in os.walk(self.dir_path):
                for f in files:
                    try:
                        total += os.path.getsize(os.path.join(root, f))
                    except OSError:
                        pass
        except Exception:
            pass
        self.finish_callback(self.dir_path, total)


class FileManagerBackend(QObject):
    currentPathChanged = Signal()
    breadcrumbsChanged = Signal()
    canGoBackChanged = Signal()
    canGoForwardChanged = Signal()
    viewModeChanged = Signal()
    gridColumnsChanged = Signal()
    sortByChanged = Signal()
    sortOrderChanged = Signal()
    selectedItemChanged = Signal()
    cacheSizeChanged = Signal()
    maxCacheMbChanged = Signal()
    sidebarUpdated = Signal()
    searchResultsChanged = Signal()
    folderSizeReady = Signal(str, str)
    pickerCompleted = Signal(list)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.config_mgr = ConfigManager()
        self.picker_ctx = PickerContext(self)

        self._current_path = Path.home()
        self._history = [self._current_path]
        self._history_idx = 0

        self._view_mode = self.config_mgr.get("view_mode", "details")
        self._grid_columns = self.config_mgr.get("grid_columns", 0)
        self._sort_by = self.config_mgr.get("sort_by", "name")
        self._sort_ascending = self.config_mgr.get("sort_ascending", True)
        self._selected_item = {}
        self._search_results = []

        self.file_model = FileListModel(self)
        self.thread_pool = QThreadPool.globalInstance()

        self.thumb_mgr = ThumbnailManager(self.config_mgr.cache_dir, self)
        self.thumb_mgr.thumbnailReady.connect(self._on_thumbnail_ready)

        self.search_mgr = SearchManager(self.config_mgr.cache_dir, self)
        self.search_mgr.searchResultsReady.connect(self._on_search_results_ready)

        self.load_directory(self._current_path)
        self.config_mgr.clean_cache()
        self.search_mgr.build_incremental_index([str(Path.home())])

    @Property(QObject, constant=True)
    def picker(self):
        return self.picker_ctx

    @Property(str, notify=currentPathChanged)
    def currentPath(self):
        return str(self._current_path)

    @Property(list, notify=breadcrumbsChanged)
    def breadcrumbs(self):
        parts = []
        p = self._current_path.resolve()
        parents = list(reversed(p.parents))
        full = parents + [p]

        for item in full:
            name = item.name if item.name else "/"
            if item == Path.home():
                name = "Home"
            parts.append({"name": name, "path": str(item)})
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

    def _on_thumbnail_ready(self, file_path, thumb_path):
        self.file_model.update_thumbnail(file_path, thumb_path)
        if self._selected_item.get("path") == file_path:
            self._selected_item["thumb"] = thumb_path
            self.selectedItemChanged.emit()

    def _on_search_results_ready(self, results):
        self._search_results = results
        self.searchResultsChanged.emit()

    def _update_history_state(self):
        self.canGoBackChanged.emit()
        self.canGoForwardChanged.emit()

    def _determine_icon_and_type(self, path_obj: Path, is_dir: bool):
        defaults = self.config_mgr.get("default_type_icons", {})
        if is_dir:
            return defaults.get("folder", "📁"), "Folder"
        if path_obj.is_symlink():
            return "🔗", "Symbolic Link"

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

    def load_directory(self, target_path: Path):
        try:
            target_path = target_path.resolve()
            if not target_path.exists() or not target_path.is_dir():
                return

            fv = self.config_mgr.get_folder_view(str(target_path))
            if not fv:
                views = self.config_mgr.get("folder_views", {})
                for ancestor in target_path.parents:
                    anc_str = str(ancestor)
                    if anc_str in views and views[anc_str].get("cascade"):
                        fv = views[anc_str]
                        break

            if fv:
                self._view_mode = fv.get("view_mode", self._view_mode)
                self._sort_by = fv.get("sort_by", self._sort_by)
                self._sort_ascending = fv.get("sort_ascending", self._sort_ascending)
                self.viewModeChanged.emit()
                self.sortByChanged.emit()
                self.sortOrderChanged.emit()

            entries = []
            with os.scandir(str(target_path)) as it:
                for entry in it:
                    if entry.name.startswith("."):
                        continue

                    try:
                        is_dir = entry.is_dir(follow_symlinks=True)
                    except OSError:
                        is_dir = False

                    # Filter evaluation if Picker is active
                    if self.picker_ctx.isActive:
                        if self.picker_ctx.mode == "folder" and not is_dir:
                            continue  # If seeking folders, hide loose files completely
                        if not self.picker_ctx.matches_filter(entry.name, is_dir):
                            continue

                    raw_size = 0
                    raw_mod = 0
                    raw_created = 0
                    size_str = ""
                    mod_str = ""
                    created_str = ""

                    try:
                        stat = entry.stat(follow_symlinks=True)
                        raw_mod = stat.st_mtime
                        mod_str = datetime.fromtimestamp(raw_mod).strftime("%Y-%m-%d %H:%M")
                        raw_created = getattr(stat, "st_birthtime", stat.st_ctime)
                        created_str = datetime.fromtimestamp(raw_created).strftime("%Y-%m-%d %H:%M")

                        if not is_dir:
                            raw_size = stat.st_size
                            size_str = self._format_size(raw_size)
                    except OSError:
                        size_str = "-"
                        mod_str = "-"
                        created_str = "-"

                    icon, file_type = self._determine_icon_and_type(Path(entry.path), is_dir)
                    existing_thumb = self.thumb_mgr.get_existing_thumbnail(entry.path) if not is_dir else ""

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
                        "thumb": existing_thumb
                    })

            self._sort_entries(entries)
            self._current_path = target_path
            self._selected_item = {}
            self.selectedItemChanged.emit()
            self.file_model.set_entries(entries)
            self.currentPathChanged.emit()
            self.breadcrumbsChanged.emit()
        except PermissionError:
            pass
        except Exception:
            pass

    def _sort_entries(self, entries):
        reverse = not self._sort_ascending
        if self._sort_by == "name":
            entries.sort(key=lambda x: (not x["is_dir"], x["name"].lower()), reverse=reverse)
        elif self._sort_by == "size":
            entries.sort(key=lambda x: (not x["is_dir"], x["raw_size"]), reverse=reverse)
        elif self._sort_by == "modified":
            entries.sort(key=lambda x: (not x["is_dir"], x["raw_mod"]), reverse=reverse)
        elif self._sort_by == "created":
            entries.sort(key=lambda x: (not x["is_dir"], x["raw_created"]), reverse=reverse)

    def _format_size(self, size):
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size < 1024.0:
                return f"{size:.1f} {unit}"
            size /= 1024.0
        return f"{size:.1f} TB"

    def _extract_media_info(self, file_path: Path):
        media_info = {
            "resolution": "",
            "codec": "",
            "bit_depth": "",
            "color_profile": "",
            "bitrate": "",
            "fps": "",
            "audio_codec": ""
        }
        if not shutil.which("ffprobe"):
            return media_info

        try:
            cmd = [
                "ffprobe", "-v", "quiet", "-print_format", "json",
                "-show_streams", "-show_format", str(file_path)
            ]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=1.5)
            if res.returncode == 0:
                data = json.loads(res.stdout)
                streams = data.get("streams", [])
                video_stream = next((s for s in streams if s.get("codec_type") == "video"), None)
                audio_stream = next((s for s in streams if s.get("codec_type") == "audio"), None)
                fmt = data.get("format", {})

                if video_stream:
                    w = video_stream.get("width")
                    h = video_stream.get("height")
                    if w and h:
                        media_info["resolution"] = f"{w}x{h}"
                    media_info["codec"] = video_stream.get("codec_name", "").upper()

                    pix_fmt = video_stream.get("pix_fmt", "")
                    bits = video_stream.get("bits_per_raw_sample")
                    if bits:
                        media_info["bit_depth"] = f"{bits}-bit"
                    elif "10le" in pix_fmt or "p10" in pix_fmt or "10be" in pix_fmt:
                        media_info["bit_depth"] = "10-bit"
                    elif "12le" in pix_fmt or "p12" in pix_fmt:
                        media_info["bit_depth"] = "12-bit"
                    elif pix_fmt:
                        media_info["bit_depth"] = "8-bit"

                    primaries = video_stream.get("color_primaries") or video_stream.get("color_space")
                    transfer = video_stream.get("color_transfer")
                    if primaries or transfer:
                        parts = [p for p in [primaries, transfer] if p]
                        media_info["color_profile"] = " / ".join(parts)

                    r_frame_rate = video_stream.get("r_frame_rate", "")
                    if "/" in r_frame_rate:
                        num, den = map(float, r_frame_rate.split("/"))
                        if den > 0:
                            media_info["fps"] = f"{round(num / den, 2)} fps"

                bit_rate_raw = fmt.get("bit_rate") or (video_stream.get("bit_rate") if video_stream else None)
                if bit_rate_raw:
                    try:
                        br_kbps = int(bit_rate_raw) / 1000
                        if br_kbps >= 1000:
                            media_info["bitrate"] = f"{round(br_kbps / 1000, 2)} Mbps"
                        else:
                            media_info["bitrate"] = f"{int(br_kbps)} kbps"
                    except Exception:
                        pass

                if audio_stream:
                    media_info["audio_codec"] = audio_stream.get("codec_name", "").upper()
        except Exception:
            pass

        return media_info

    @Slot(str)
    def requestItemThumbnail(self, file_path_str: str):
        self.thumb_mgr.request_thumbnail(file_path_str)

    @Slot(str)
    def openEntry(self, file_path_str: str):
        path = Path(file_path_str)
        if path.is_dir():
            if self._history_idx < len(self._history) - 1:
                self._history = self._history[:self._history_idx + 1]
            self._history.append(path)
            self._history_idx += 1
            self.load_directory(path)
            self._update_history_state()
            if self.picker_ctx.isActive and self.picker_ctx.mode == "folder":
                self.picker_ctx.setSelectedPath(str(path))
        else:
            if self.picker_ctx.isActive:
                self.picker_ctx.setSelectedPath(str(path))
                self.confirmPickerSelection()
            else:
                subprocess.Popen(["xdg-open", str(path)])

    @Slot()
    def goUp(self):
        parent = self._current_path.parent
        if parent != self._current_path:
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
        self.load_directory(self._current_path)

    @Slot(str)
    def navigateTo(self, path_str: str):
        self.openEntry(path_str)

    @Slot(str)
    def setViewMode(self, mode: str):
        self.viewMode = mode

    @Slot(int)
    def setGridColumns(self, cols: int):
        self.gridColumns = cols

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
        self.config_mgr.apply_view_to_subfolders(str(self._current_path), self._view_mode, self._sort_by, self._sort_ascending)

    @Slot(str, str, bool, str, str, str)
    def selectItem(self, path: str, name: str, is_dir: bool, size: str, modified: str, file_type: str):
        if self.picker_ctx.isActive:
            self.picker_ctx.toggleSelect(path, is_dir)

        preview_text = ""
        is_image = False
        is_video = False
        p = Path(path)
        media_info = {}
        thumb = ""

        if not is_dir and p.exists():
            suffix = p.suffix.lower()
            if suffix in IMAGE_EXTS:
                is_image = True
                media_info = self._extract_media_info(p)
                thumb = self.thumb_mgr.get_existing_thumbnail(path)
            elif suffix in VIDEO_EXTS:
                is_video = True
                media_info = self._extract_media_info(p)
                thumb = self.thumb_mgr.get_existing_thumbnail(path)
            elif p.stat().st_size <= 64 * 1024:
                try:
                    with open(p, "r", encoding="utf-8", errors="ignore") as f:
                        preview_text = f.read(1500)
                except Exception:
                    preview_text = ""
        elif is_dir and p.exists():
            size = "Calculating..."
            task = FolderSizeTask(str(p), self._on_folder_size_calculated)
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
            "resolution": media_info.get("resolution", ""),
            "codec": media_info.get("codec", ""),
            "bit_depth": media_info.get("bit_depth", ""),
            "color_profile": media_info.get("color_profile", ""),
            "bitrate": media_info.get("bitrate", ""),
            "fps": media_info.get("fps", ""),
            "audio_codec": media_info.get("audio_codec", "")
        }
        self.selectedItemChanged.emit()

    def _on_folder_size_calculated(self, dir_path, total_bytes):
        if self._selected_item.get("path") == dir_path:
            self._selected_item["size"] = self._format_size(total_bytes)
            self.selectedItemChanged.emit()

    @Slot()
    def clearSelection(self):
        self._selected_item = {}
        self.selectedItemChanged.emit()

    # --- Picker Confirmation & Process Integration ---
    @Slot()
    def confirmPickerSelection(self):
        chosen = self.picker_ctx.selectedPaths
        if not chosen:
            if self.picker_ctx.mode == "folder":
                chosen = [str(self._current_path)]
            else:
                return

        # Output to stdout for external Linux/Wayland scripts
        for item_path in chosen:
            print(item_path)
        sys.stdout.flush()

        self.pickerCompleted.emit(chosen)

        # If launched directly as a standalone CLI picker, exit with success
        if getattr(self, "_launched_as_picker", False):
            QGuiApplication.quit()

    @Slot()
    def cancelPicker(self):
        self.picker_ctx.deactivate()
        self.load_directory(self._current_path)
        if getattr(self, "_launched_as_picker", False):
            sys.exit(1)

    @Slot(str, str, str)
    def openInternalPicker(self, mode: str, filter_str: str, title: str):
        self.picker_ctx.activate(mode, filter_str, title)
        self.load_directory(self._current_path)

    @Slot(str, str)
    def createItem(self, item_type: str, item_name: str):
        try:
            target = self._current_path / item_name.strip()
            if item_type == "folder":
                target.mkdir(parents=True, exist_ok=True)
            elif item_type == "link":
                if not target.exists():
                    os.symlink(str(self._current_path), str(target))
            else:
                default_contents = {
                    "py": "#!/usr/bin/env python3\n\n",
                    "rs": "fn main() {\n    println!(\"Hello, world!\");\n}\n",
                    "json": "{\n  \n}\n",
                    "txt": "",
                    "empty": "",
                }
                content = default_contents.get(item_type, "")
                if not target.exists():
                    with open(target, "w", encoding="utf-8") as f:
                        f.write(content)
            self.refresh()
        except Exception:
            pass

    @Slot(str)
    def copyToClipboard(self, text: str):
        clipboard = QGuiApplication.clipboard()
        clipboard.setText(text)

    @Slot(str)
    def openInTerminal(self, dir_path_str: str):
        path = Path(dir_path_str)
        if not path.is_dir():
            path = path.parent
        terminals = [
            ["kitty", "--directory", str(path)],
            ["alacritty", "--working-directory", str(path)],
            ["ghostty", f"--working-directory={str(path)}"],
            ["konsole", "--workdir", str(path)],
            ["gnome-terminal", "--working-directory", str(path)],
            ["xterm", "-e", f"cd '{str(path)}' && $SHELL"]
        ]
        for term_cmd in terminals:
            if shutil.which(term_cmd[0]):
                subprocess.Popen(term_cmd)
                return

    @Slot(str)
    def moveToTrash(self, file_path_str: str):
        try:
            if shutil.which("gio"):
                subprocess.Popen(["gio", "trash", file_path_str]).wait()
            elif shutil.which("trash-put"):
                subprocess.Popen(["trash-put", file_path_str]).wait()
            else:
                p = Path(file_path_str)
                if p.is_dir():
                    shutil.rmtree(p)
                else:
                    p.unlink()
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
                        if fstype in ignored_fs or not device.startswith("/dev/"):
                            continue
                        if mount in seen_mounts or mount in hidden:
                            continue

                        is_target = (
                            mount == "/" or
                            mount.startswith("/run/media") or
                            mount.startswith("/media") or
                            mount.startswith("/mnt") or
                            "nvme" in device or
                            "sd" in device
                        )

                        if is_target and os.path.exists(mount):
                            seen_mounts.add(mount)
                            try:
                                usage = shutil.disk_usage(mount)
                                total_str = self._format_size(usage.total)
                            except OSError:
                                total_str = ""

                            name = "Root System" if mount == "/" else Path(mount).name
                            drives.append({
                                "name": name,
                                "path": mount,
                                "device": device,
                                "total": total_str,
                                "icon": "💾" if "nvme" in device else "💽"
                            })
        except Exception:
            pass

        return drives
