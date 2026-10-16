import json
import os
from pathlib import Path


class ConfigManager:
    DEFAULT_CONFIG = {
        "view_mode": "details",
        "grid_columns": 0,
        "grid_style": "floating",
        "sidebar_mode": "auto",
        "sort_by": "name",
        "sort_ascending": True,
        "max_cache_mb": 500,
        "scale_factor": 1.35,
        "transparent_blur": False,
        "show_hidden": False,
        "swap_mouse_buttons": False,
        "auto_play_hdr": True,
        "media_libraries": [],
        "movie_folders": [],
        "mpv_both_config": (
            "vo=gpu-next\n"
            "gpu-api=vulkan\n"
            "hwdec=auto-safe\n"
            "gpu-shader-cache-dir={shader_cache}\n"
            "volume-max=150\n"
            "profile=gpu-hq\n"
            "scale=ewa_lanczossharp\n"
            "cscale=ewa_lanczossharp\n"
            "sharpen=0.0\n"
            "cache=yes\n"
            "osc=yes\n"
            "input-default-bindings=yes\n"
            "input-vo-keyboard=yes\n"
            "keep-open=yes\n"
            "save-position-on-quit=yes\n"
            "osd-on-seek=no\n"
            "slang=ar,ara,arabic\n"
            "alang=ja,jpn,jp,en,eng\n"
            "sub-auto=fuzzy\n"
            "sub-fonts-dir={fonts_dir}\n"
            "sub-font=Calibri\n"
            "sub-bold=yes\n"
            "sub-font-size=48\n"
            "sub-color=#FFFFFF\n"
            "sub-border-size=1.0\n"
            "sub-border-color=#000000\n"
            "sub-shadow-offset=1\n"
            "sub-shadow-color=#000000\n"
            "sub-margin-y=40\n"
            "stop-screensaver=no\n"
            "msg-level=all=error,osd/libass=v"
        ),
        "mpv_sdr_config": (
            "# SDR-only overrides (Any key placed here overrides 'Both')\n"
            "target-colorspace-hint=no"
        ),
        "mpv_hdr_config": (
            'profile-cond=p["video-params/gamma"] == "pq" or p["video-params/gamma"] == "hlg"\n'
            "gpu-api=vulkan\n"
            "hwdec=auto-safe\n"
            "hr-seek=no\n"
            "dither-depth=10\n"
            "dither=fruit\n"
            "temporal-dither=no\n"
            "target-colorspace-hint=yes\n"
            "target-colorspace-hint-mode=target\n"
            "target-peak=1000\n"
            "target-contrast=inf\n"
            "tone-mapping=clip\n"
            "hdr-compute-peak=no\n"
            "gamut-mapping-mode=clip\n"
            "inverse-tone-mapping=no\n"
            "allow-delayed-peak-detect=no\n"
            "\n"
            "#sub\n"
            "sub-color=0.68/0.68/0.68/1.0"
        ),
        "hidden_sidebar_paths": [],
        "folder_views": {},
        "custom_quick_access": [
            {"name": "Home", "path": str(Path.home()), "icon": "🏠"},
            {"name": "Desktop", "path": str(Path.home() / "Desktop"), "icon": "🖥️"},
            {"name": "Documents", "path": str(Path.home() / "Documents"), "icon": "📄"},
            {"name": "Downloads", "path": str(Path.home() / "Downloads"), "icon": "📥"},
            {"name": "Pictures", "path": str(Path.home() / "Pictures"), "icon": "🖼️"},
            {"name": "Videos", "path": str(Path.home() / "Videos"), "icon": "🎬"},
            {"name": "Music", "path": str(Path.home() / "Music"), "icon": "🎵"},
        ],
        "default_type_icons": {
            "folder": "📁",
            "file": "📄",
            "py": "🐍",
            "rs": "🦀",
            "json": "📋",
            "image": "🖼️",
            "video": "🎬",
            "audio": "🎵",
            "archive": "📦"
        }
    }

    def __init__(self):
        xdg_config = os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))
        xdg_cache = os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))

        self.config_dir = Path(xdg_config) / "find"
        self.config_file = self.config_dir / "config.json"
        self.progress_file = self.config_dir / "media_progress.json"
        self.hdr_cache_file = self.config_dir / "hdr_cache.json"
        self.cache_dir = Path(xdg_cache) / "find"
        self._progress = self._load_progress()
        self._hdr_cache = self._load_hdr_cache()

        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.cache_dir.mkdir(parents=True, exist_ok=True)

        self._config = self._load()
        cur_hdr = self._config.get("mpv_hdr_config", "")
        if "sub-color=0.68/0.68/0.68/1.0" not in cur_hdr:
            self._config["mpv_hdr_config"] = self.DEFAULT_CONFIG["mpv_hdr_config"]
            self.save()
        cur_both = self._config.get("mpv_both_config", "")
        if "slang=ar,ara,arabic" not in cur_both:
            self._config["mpv_both_config"] = self.DEFAULT_CONFIG["mpv_both_config"]
            self.save()

    def _load(self):
        if self.config_file.exists():
            try:
                with open(self.config_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    return {**self.DEFAULT_CONFIG, **data}
            except Exception:
                pass
        return dict(self.DEFAULT_CONFIG)

    def save(self):
        tmp_file = self.config_file.with_suffix(".tmp")
        try:
            with open(tmp_file, "w", encoding="utf-8") as f:
                json.dump(self._config, f, indent=2)
            os.replace(tmp_file, self.config_file)
        except Exception:
            if tmp_file.exists():
                try:
                    tmp_file.unlink()
                except OSError:
                    pass

    def get(self, key, default=None):
        return self._config.get(key, default)

    def set(self, key, value):
        self._config[key] = value
        self.save()

    def _load_progress(self):
        if self.progress_file.exists():
            try:
                with open(self.progress_file, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def save_progress(self):
        tmp = self.progress_file.with_suffix(".tmp")
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self._progress, f, indent=2)
            os.replace(tmp, self.progress_file)
        except Exception:
            pass

    def _load_hdr_cache(self):
        if hasattr(self, "hdr_cache_file") and self.hdr_cache_file.exists():
            try:
                with open(self.hdr_cache_file, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def save_hdr_cache(self):
        tmp = self.hdr_cache_file.with_suffix(".tmp")
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self._hdr_cache, f)
            os.replace(tmp, self.hdr_cache_file)
        except Exception:
            pass

    def get_cached_hdr(self, file_path: str, mtime: float):
        entry = self._hdr_cache.get(file_path)
        if isinstance(entry, dict) and entry.get("mtime") == mtime:
            return entry.get("is_hdr")
        return None

    def set_cached_hdr(self, file_path: str, mtime: float, is_hdr: bool):
        self._hdr_cache[file_path] = {"mtime": mtime, "is_hdr": bool(is_hdr)}
        self.save_hdr_cache()

    def get_media_progress(self, file_path: str) -> dict:
        default_entry = {"position": 0.0, "duration": 0.0, "progress": 0.0, "watched": False, "ext_sub": ""}
        saved = self._progress.get(file_path)
        if isinstance(saved, dict):
            return {**default_entry, **saved}
        return default_entry

    def set_media_progress(self, file_path: str, position: float, duration: float, watched: bool = None, ext_sub: str = None):
        prev = self.get_media_progress(file_path)
        prog = 0.0
        if duration > 0:
            prog = min(1.0, max(0.0, position / duration))
        if watched is None:
            watched = prog >= 0.90
        elif watched and prog < 0.90:
            prog = 1.0
        sub_to_save = ext_sub if ext_sub is not None else prev.get("ext_sub", "")
        self._progress[file_path] = {
            "position": round(float(position), 2),
            "duration": round(float(duration), 2),
            "progress": round(float(prog), 4),
            "watched": bool(watched),
            "ext_sub": str(sub_to_save or "")
        }
        self.save_progress()
        return self._progress[file_path]

    def set_media_external_sub(self, file_path: str, ext_sub_path: str):
        if not file_path:
            return
        prev = self.get_media_progress(file_path)
        if prev.get("ext_sub", "") != ext_sub_path:
            prev["ext_sub"] = str(ext_sub_path)
            self._progress[file_path] = prev
            self.save_progress()

    def get_folder_view(self, path_str: str):
        views = self._config.get("folder_views", {})
        return views.get(path_str, None)

    def set_folder_view(self, path_str: str, view_mode: str, sort_by: str, sort_ascending: bool):
        views = dict(self._config.get("folder_views", {}))
        views[path_str] = {
            "view_mode": view_mode,
            "sort_by": sort_by,
            "sort_ascending": sort_ascending
        }
        self.set("folder_views", views)

    def apply_view_to_subfolders(self, root_path_str: str, view_mode: str, sort_by: str, sort_ascending: bool):
        views = dict(self._config.get("folder_views", {}))
        clean_root = root_path_str.rstrip(os.sep) + os.sep
        views = {k: v for k, v in views.items() if not (k == root_path_str or k.startswith(clean_root))}
        views[root_path_str] = {
            "view_mode": view_mode,
            "sort_by": sort_by,
            "sort_ascending": sort_ascending,
            "cascade": True
        }
        self.set("folder_views", views)

    def get_cache_size_bytes(self):
        total = 0
        try:
            for p in self.cache_dir.rglob("*"):
                if p.is_file():
                    total += p.stat().st_size
        except Exception:
            pass
        return total

    def clean_cache(self, force_all=False):
        thumbs_dir = self.cache_dir / "thumbs"
        manifest_path = self.cache_dir / "thumb_manifest.json"

        if force_all:
            for p in self.cache_dir.rglob("*"):
                try:
                    if p.is_file() and p.name != "index_cache.json":
                        p.unlink()
                except Exception:
                    pass
            return

        manifest = {}
        if manifest_path.exists():
            try:
                with open(manifest_path, "r", encoding="utf-8") as f:
                    manifest = json.load(f)
            except Exception:
                manifest = {}

        # Step 1: Immediately purge thumbnails whose original source file was deleted
        dirty_manifest = False
        if thumbs_dir.exists():
            for thumb_file in list(thumbs_dir.iterdir()):
                if not thumb_file.is_file():
                    continue
                meta = manifest.get(thumb_file.name)
                if meta:
                    src_path = meta.get("src", "")
                    if not src_path or not os.path.exists(src_path):
                        try:
                            thumb_file.unlink()
                        except OSError:
                            pass
                        manifest.pop(thumb_file.name, None)
                        dirty_manifest = True

        # Step 2: Utilize 100% of allocated max_cache_mb, evicting oldest-accessed items above 98%
        max_bytes = int(self.get("max_cache_mb", 500) * 1024 * 1024)
        current_size = self.get_cache_size_bytes()

        if current_size > max_bytes and thumbs_dir.exists():
            files = []
            for p in thumbs_dir.rglob("*"):
                if p.is_file():
                    try:
                        st = p.stat()
                        last_used = max(st.st_atime, st.st_mtime)
                        files.append((p, last_used, st.st_size))
                    except OSError:
                        pass
            files.sort(key=lambda x: x[1])

            target_bytes = int(max_bytes * 0.98)
            for p, _, sz in files:
                try:
                    p.unlink()
                    manifest.pop(p.name, None)
                    dirty_manifest = True
                    current_size -= sz
                    if current_size <= target_bytes:
                        break
                except Exception:
                    pass

        if dirty_manifest:
            try:
                with open(manifest_path, "w", encoding="utf-8") as f:
                    json.dump(manifest, f)
            except Exception:
                pass
