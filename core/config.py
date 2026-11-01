import json
import os
import time
import shutil
import threading
if os.name == "nt":
    import msvcrt
else:
    import fcntl
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
        "scroll_speed_multiplier": 1.25,
        "keep_alive_in_background": True,
        "accent_color": "#0078d4",
        "recent_accent_colors": ["#0078d4", "#8b5cf6", "#10b981", "#f59e0b", "#ec4899"],
        "transparent_blur": False,
        "show_hidden": False,
        "swap_mouse_buttons": False,
        "auto_play_hdr": True,
        "mpv_auto_fullscreen": True,
        "recent_watched_folders": [],
        "daemon_autostart": True,
        "restore_last_session": True,
        "startup_path": str(Path.home()),
        "last_session": {
            "tabs": [],
            "active_index": 0
        },
        "custom_icons_dir": "",
        "jellyfin_enabled": True,
        "jellyfin_url": "http://localhost:8096",
        "jellyfin_token": "",
        "jellyfin_user_id": "",
        "jellyfin_stream_mode": False,
        "show_series_posters": True,
        "anonymous_mode": False,
        "mal_username": "",
        "mal_client_id": "",
        "mal_access_token": "",
        "airing_links": {},
        "airing_local_eps": {},
        "airing_ignored_ids": [],
        "notification_settings": {
            "master_enabled": True,
            "os_notifications_enabled": True,
            "in_app_toasts_enabled": True,
            "toast_file_ops": True,
            "toast_archive_ops": True,
            "toast_jellyfin_sync": True,
            "toast_clipboard": True,
            "urgency": "normal",
            "display_timeout_ms": 6000,
            "airing_on_release": True,
            "airing_pre_reminder_enabled": False,
            "airing_pre_reminder_minutes": 30,
            "airing_unwatched_reminder_enabled": True,
            "airing_unwatched_reminder_hours": 12,
            "airing_content_show_poster": True,
            "airing_content_show_ep": True,
            "airing_content_show_progress": True,
            "airing_content_show_behind": True,
            "airing_title_template": "🎬 {title} — Episode {ep}",
            "airing_body_template": "{event_label}\nLocal Progress: {watched} eps ({status})",
            "disabled_anime_ids": []
        },
        "media_hub_rows": [
            {"id": "continue_watching", "title": "Continue Watching", "visible": True},
            {"id": "recently_added", "title": "New Episodes", "visible": True},
            {"id": "next_up", "title": "Next Up", "visible": True},
            {"id": "airing", "title": "Airing Weekly Tracker", "visible": True}
        ],
        "media_hub_hidden": {},
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
            "osc=no\n"
            "osd-bar=no\n"
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
        "folder_visit_counts": {},
        "favorites": [],
        "saved_desktop_apps": [],
        "custom_automations": [],
        "custom_open_rules": {
            "groups": {},
            "extensions": {}
        },
        "custom_extension_icons": {},
        "use_app_icon_fallback": True,
        "fonts_install_dir": str(Path.home() / ".local" / "share" / "fonts"),
        "custom_quick_access": [
            {"name": "Media Hub", "path": "mediahub://", "icon": "🎬", "visible": True},
            {"name": "Favorites", "path": "favorites://", "icon": "⭐", "visible": True},
            {"name": "Recently Added", "path": "recent://", "icon": "🕒", "visible": True},
            {"name": "Home", "path": str(Path.home()), "icon": "🏠", "visible": True},
            {"name": "Desktop", "path": str(Path.home() / "Desktop"), "icon": "🖥️", "visible": True},
            {"name": "Documents", "path": str(Path.home() / "Documents"), "icon": "📄", "visible": True},
            {"name": "Downloads", "path": str(Path.home() / "Downloads"), "icon": "📥", "visible": True},
            {"name": "Pictures", "path": str(Path.home() / "Pictures"), "icon": "🖼️", "visible": True},
            {"name": "Videos", "path": str(Path.home() / "Videos"), "icon": "🎬", "visible": True},
            {"name": "Music", "path": str(Path.home() / "Music"), "icon": "🎵", "visible": True},
            {"name": "Trash", "path": "trash://", "icon": "🗑️", "visible": True},
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

        self._lock = threading.RLock()
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self._config = self._load()

    def _atomic_write_json(self, target_file: Path, data_snapshot: dict, indent=2, secure_perms: bool = False):
        lock_path = target_file.with_suffix(target_file.suffix + ".lock")
        tmp_path = target_file.with_suffix(f".tmp.{os.getpid()}.{threading.get_ident()}")
        try:
            with open(lock_path, "w", encoding="utf-8") as lf:
                # القفل
                if os.name == "nt":
                    lf.seek(0)
                    msvcrt.locking(lf.fileno(), msvcrt.LK_LOCK, 1)
                else:
                    fcntl.flock(lf, fcntl.LOCK_EX)
                try:
                    with open(tmp_path, "w", encoding="utf-8") as f:
                        json.dump(data_snapshot, f, indent=indent)
                        f.flush()
                        os.fsync(f.fileno())
                    if secure_perms:
                        try:
                            os.chmod(tmp_path, 0o600)
                        except OSError:
                            pass
                    os.replace(tmp_path, target_file)
                finally:
                    if os.name == "nt":
                        try:
                            lf.seek(0)
                            msvcrt.locking(lf.fileno(), msvcrt.LK_UNLCK, 1)
                        except OSError:
                            pass
                    else:
                        fcntl.flock(lf, fcntl.LOCK_UN)
        except Exception:
            if tmp_path.exists():
                try:
                    tmp_path.unlink()
                except OSError:
                    pass

    def _load(self):
        if self.config_file.exists():
            try:
                with open(self.config_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        return {**self.DEFAULT_CONFIG, **data}
            except Exception:
                # Preserve corrupted config file as backup instead of silently overwriting it!
                try:
                    bak = self.config_file.with_suffix(f".corrupt.{int(time.time())}.bak")
                    shutil.copy2(self.config_file, bak)
                except Exception:
                    pass
        return dict(self.DEFAULT_CONFIG)

    def save(self):
        with self._lock:
            snapshot = dict(self._config)
        self._atomic_write_json(self.config_file, snapshot, indent=2, secure_perms=True)

    def get(self, key, default=None):
        with self._lock:
            return self._config.get(key, default)

    def set(self, key, value):
        lock_path = self.config_file.with_suffix(self.config_file.suffix + ".lock")
        with self._lock:
            try:
                with open(lock_path, "w", encoding="utf-8") as lf:
                    if os.name != "nt":
                        fcntl.flock(lf, fcntl.LOCK_EX)
                    try:
                        if self.config_file.exists():
                            try:
                                with open(self.config_file, "r", encoding="utf-8") as f:
                                    disk_data = json.load(f)
                                    if isinstance(disk_data, dict):
                                        self._config.update(disk_data)
                            except Exception:
                                pass
                        self._config[key] = value
                        snapshot = dict(self._config)
                        tmp_path = self.config_file.with_suffix(f".tmp.{os.getpid()}.{threading.get_ident()}")
                        with open(tmp_path, "w", encoding="utf-8") as wf:
                            json.dump(snapshot, wf, indent=2)
                            wf.flush()
                            os.fsync(wf.fileno())
                        try:
                            os.chmod(tmp_path, 0o600)
                        except OSError:
                            pass
                        os.replace(tmp_path, self.config_file)
                    finally:
                        if os.name != "nt":
                            fcntl.flock(lf, fcntl.LOCK_UN)
            except Exception:
                pass

    def _load_progress(self):
        if self.progress_file.exists():
            try:
                with open(self.progress_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        return data
            except Exception:
                pass
        return {}

    def save_progress(self):
        with self._lock:
            if self.progress_file.exists():
                try:
                    with open(self.progress_file, "r", encoding="utf-8") as f:
                        disk_prog = json.load(f)
                        if isinstance(disk_prog, dict):
                            for k, v in disk_prog.items():
                                if k not in self._progress or (
                                    isinstance(v, dict) and isinstance(self._progress.get(k), dict) and
                                    float(v.get("updated_at", 0.0)) > float(self._progress[k].get("updated_at", 0.0))
                                ):
                                    self._progress[k] = v
                except Exception:
                    pass
            snapshot = dict(self._progress)
        self._atomic_write_json(self.progress_file, snapshot, indent=2)

    def _load_hdr_cache(self):
        if hasattr(self, "hdr_cache_file") and self.hdr_cache_file.exists():
            try:
                with open(self.hdr_cache_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        return data
            except Exception:
                pass
        return {}

    def save_hdr_cache(self):
        with self._lock:
            snapshot = dict(self._hdr_cache)
        self._atomic_write_json(self.hdr_cache_file, snapshot, indent=None)

    def get_cached_hdr(self, file_path: str, mtime: float):
        with self._lock:
            entry = self._hdr_cache.get(file_path)
            if isinstance(entry, dict) and entry.get("mtime") == mtime:
                return entry.get("is_hdr")
        return None

    def set_cached_hdr(self, file_path: str, mtime: float, is_hdr: bool, flush: bool = True):
        with self._lock:
            self._hdr_cache[file_path] = {"mtime": mtime, "is_hdr": bool(is_hdr)}
        if flush:
            self.save_hdr_cache()

    def reload_progress_from_disk(self):
        self._progress = self._load_progress()

    def get_media_progress(self, file_path: str) -> dict:
        default_entry = {"position": 0.0, "duration": 0.0, "progress": 0.0, "watched": False, "ext_sub": "", "updated_at": 0.0}
        saved = self._progress.get(file_path)
        if isinstance(saved, dict):
            return {**default_entry, **saved}
        return default_entry

    def set_media_progress(self, file_path: str, position: float, duration: float, watched: bool = None, ext_sub: str = None, updated_at: float = None):
        import time as _time
        prev = self.get_media_progress(file_path)
        prog = 0.0
        if duration > 0:
            prog = min(1.0, max(0.0, position / duration))
        if watched is None:
            watched = prog >= 0.90
        elif watched and prog < 0.90:
            prog = 1.0
        sub_to_save = ext_sub if ext_sub is not None else prev.get("ext_sub", "")
        ts_val = float(updated_at) if updated_at is not None else _time.time()
        self._progress[file_path] = {
            "position": round(float(position), 2),
            "duration": round(float(duration), 2),
            "progress": round(float(prog), 4),
            "watched": bool(watched),
            "ext_sub": str(sub_to_save or ""),
            "updated_at": round(ts_val, 2)
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

    def record_folder_visit(self, path_str: str):
        if not path_str or path_str in ("recent://", "trash://", "favorites://", "mediahub://") or path_str.startswith("analyzer://"):
            return
        norm = os.path.abspath(path_str)
        with self._lock:
            counts = dict(self._config.get("folder_visit_counts", {}) or {})
            counts[norm] = int(counts.get(norm, 0) or 0) + 1
            if len(counts) > 1500:
                top_items = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:1000]
                counts = dict(top_items)
            self._config["folder_visit_counts"] = counts

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

        # Step 2: Smart LFU + Recency Cache Eviction — Retain thumbnails belonging to frequently visited folders
        # and evict thumbnails from the least-visited folders first when cache exceeds max_cache_mb
        max_bytes = int(self.get("max_cache_mb", 500) * 1024 * 1024)
        current_size = self.get_cache_size_bytes()
        visit_counts = dict(self.get("folder_visit_counts", {}) or {})

        if current_size > max_bytes and thumbs_dir.exists():
            files = []
            for p in thumbs_dir.rglob("*"):
                if p.is_file():
                    try:
                        st = p.stat()
                        last_used = max(st.st_atime, st.st_mtime)
                        meta = manifest.get(p.name, {})
                        src_path = str(meta.get("src") or "")
                        parent_dir = os.path.dirname(src_path) if src_path else ""
                        folder_visits = int(visit_counts.get(parent_dir, 0) or 0)
                        files.append((p, folder_visits, last_used, st.st_size))
                    except OSError:
                        pass
            # Sort ascending by (folder_visits, last_used) so least-visited folders are evicted first!
            files.sort(key=lambda x: (x[1], x[2]))

            target_bytes = int(max_bytes * 0.98)
            for p, _, _, sz in files:
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
