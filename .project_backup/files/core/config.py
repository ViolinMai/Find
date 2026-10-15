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
        self.cache_dir = Path(xdg_cache) / "find"

        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.cache_dir.mkdir(parents=True, exist_ok=True)

        self._config = self._load()

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
