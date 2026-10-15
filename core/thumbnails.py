import os
import hashlib
import json
import tempfile
import subprocess
import shutil
from pathlib import Path
from PySide6.QtCore import QObject, Signal, QRunnable, QThreadPool
from PIL import Image

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".ico"}
VIDEO_EXTS = {".mp4", ".mkv", ".webm", ".avi", ".mov", ".flv", ".m4v"}
TEXT_EXTS = {
    ".txt", ".md", ".py", ".rs", ".json", ".toml", ".yaml", ".yml",
    ".ini", ".conf", ".cfg", ".sh", ".c", ".cpp", ".h", ".hpp",
    ".js", ".ts", ".qml", ".html", ".css", ".xml", ".csv", ".log",
    ".srt", ".ass", ".sub"
}

EPHEMERAL_DIR = Path(tempfile.gettempdir()) / "find_ephemeral_previews"
EPHEMERAL_DIR.mkdir(parents=True, exist_ok=True)


def _record_manifest_entry(cache_dir: Path, thumb_filename: str, src_path: str):
    manifest_path = cache_dir.parent / "thumb_manifest.json"
    try:
        data = {}
        if manifest_path.exists():
            with open(manifest_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        data[thumb_filename] = {"src": src_path}
        tmp = manifest_path.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, manifest_path)
    except Exception:
        pass


def generate_single_thumbnail_sync(file_path: str, cache_dir: Path, save_to_cache: bool = True) -> str:
    try:
        p = Path(file_path)
        if not p.exists() or not p.is_file():
            return ""
        ext = p.suffix.lower()
        if ext not in IMAGE_EXTS and ext not in VIDEO_EXTS:
            return ""

        # If save_to_cache is False (Folder Preview), do NOT store in persistent cache!
        if not save_to_cache and ext in IMAGE_EXTS:
            return str(p)

        mtime = p.stat().st_mtime
        key = f"{file_path}_{mtime}".encode("utf-8")
        hash_base = hashlib.md5(key).hexdigest()

        target_dir = cache_dir if save_to_cache else EPHEMERAL_DIR
        for cand_ext in (".png", ".jpg"):
            cand = target_dir / f"{hash_base}{cand_ext}"
            if cand.exists() and cand.stat().st_size > 0:
                try:
                    os.utime(cand, None)
                except OSError:
                    pass
                return str(cand)

        out_ext = ".png" if ext in {".png", ".ico"} else ".jpg"
        thumb_path = target_dir / f"{hash_base}{out_ext}"

        if ext in IMAGE_EXTS:
            with Image.open(p) as img:
                img.thumbnail((360, 360))
                if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
                    img.save(str(thumb_path), "PNG", optimize=True)
                else:
                    img.convert("RGB").save(str(thumb_path), "JPEG", quality=86)
                if save_to_cache:
                    _record_manifest_entry(cache_dir, thumb_path.name, file_path)
                return str(thumb_path)

        if ext in VIDEO_EXTS and shutil.which("ffmpeg"):
            cmd_cover = [
                "ffmpeg", "-v", "quiet", "-y", "-i", str(p),
                "-map", "0:v:1", "-vframes", "1",
                "-vf", "scale='min(320,iw)':-1", str(thumb_path)
            ]
            res = subprocess.run(cmd_cover, timeout=1.5)
            if res.returncode == 0 and thumb_path.exists() and thumb_path.stat().st_size > 0:
                if save_to_cache:
                    _record_manifest_entry(cache_dir, thumb_path.name, file_path)
                return str(thumb_path)

            cmd_fast = [
                "ffmpeg", "-v", "quiet", "-y", "-ss", "1.0", "-i", str(p),
                "-vframes", "1", "-vf", "scale='min(320,iw)':-1", str(thumb_path)
            ]
            res2 = subprocess.run(cmd_fast, timeout=2.0)
            if res2.returncode == 0 and thumb_path.exists() and thumb_path.stat().st_size > 0:
                if save_to_cache:
                    _record_manifest_entry(cache_dir, thumb_path.name, file_path)
                return str(thumb_path)

            cmd_zero = [
                "ffmpeg", "-v", "quiet", "-y", "-i", str(p),
                "-vframes", "1", "-vf", "scale='min(320,iw)':-1", str(thumb_path)
            ]
            res3 = subprocess.run(cmd_zero, timeout=2.0)
            if res3.returncode == 0 and thumb_path.exists() and thumb_path.stat().st_size > 0:
                if save_to_cache:
                    _record_manifest_entry(cache_dir, thumb_path.name, file_path)
                return str(thumb_path)
    except Exception:
        pass
    return ""


class ThumbnailTask(QRunnable):
    def __init__(self, file_path: str, cache_dir: Path, callback_signal):
        super().__init__()
        self.file_path = file_path
        self.cache_dir = cache_dir
        self.callback_signal = callback_signal

    def run(self):
        res = generate_single_thumbnail_sync(self.file_path, self.cache_dir, save_to_cache=True)
        if res:
            self.callback_signal.emit(self.file_path, res)


class FolderPreviewTask(QRunnable):
    """
    Fast Breadth-First search across the folder and its subfolders.
    Immediately stops scanning as soon as up to 4 media (video/image) files are found
    so CPU is never stressed, and does NOT write anything to the persistent disk cache.
    """
    def __init__(self, folder_path: str, cache_dir: Path, show_hidden: bool, callback_signal):
        super().__init__()
        self.folder_path = folder_path
        self.cache_dir = cache_dir
        self.show_hidden = show_hidden
        self.callback_signal = callback_signal

    def run(self):
        media_hits = []
        text_hits = []

        try:
            root_p = Path(self.folder_path)
            if not root_p.exists() or not root_p.is_dir():
                return

            queue = [(str(root_p), 0)]
            visited_dirs = 0
            max_dirs_to_visit = 25
            max_depth = 3

            while queue and len(media_hits) < 4 and visited_dirs < max_dirs_to_visit:
                curr_dir, depth = queue.pop(0)
                visited_dirs += 1
                sub_dirs = []

                try:
                    with os.scandir(curr_dir) as it:
                        for entry in it:
                            if not self.show_hidden and entry.name.startswith("."):
                                continue
                            try:
                                if entry.is_dir(follow_symlinks=False):
                                    if depth < max_depth:
                                        sub_dirs.append((entry.path, depth + 1))
                                elif entry.is_file(follow_symlinks=True):
                                    ext = Path(entry.name).suffix.lower()
                                    if ext in VIDEO_EXTS:
                                        media_hits.append(("video", entry.path, entry.name))
                                        if len(media_hits) >= 4:
                                            break
                                    elif ext in IMAGE_EXTS:
                                        media_hits.append(("image", entry.path, entry.name))
                                        if len(media_hits) >= 4:
                                            break
                                    elif ext in TEXT_EXTS and len(text_hits) < 2:
                                        text_hits.append(("text", entry.path, entry.name))
                            except OSError:
                                pass
                except OSError:
                    pass

                if len(media_hits) >= 4:
                    break
                queue.extend(sub_dirs)

            videos = [x for x in media_hits if x[0] == "video"]
            images = [x for x in media_hits if x[0] == "image"]
            combined = (videos + images + text_hits)[:4]

            previews = []
            for kind, fpath, fname in combined:
                if kind == "image":
                    previews.append({
                        "kind": "image",
                        "thumb": fpath,
                        "snippet": "",
                        "name": fname
                    })
                elif kind == "video":
                    thumb = generate_single_thumbnail_sync(fpath, self.cache_dir, save_to_cache=False)
                    previews.append({
                        "kind": "video",
                        "thumb": thumb,
                        "snippet": "",
                        "name": fname
                    })
                elif kind == "text":
                    snippet = ""
                    try:
                        with open(fpath, "rb") as tf:
                            raw = tf.read(260)
                            if b"\0" not in raw:
                                lines = [ln.strip() for ln in raw.decode("utf-8", errors="ignore").splitlines() if ln.strip()]
                                snippet = "\n".join(lines[:4])[:100]
                    except Exception:
                        pass
                    previews.append({
                        "kind": "text",
                        "thumb": "",
                        "snippet": snippet if snippet else fname,
                        "name": fname
                    })

            if previews:
                self.callback_signal.emit(self.folder_path, previews)
        except Exception:
            pass


class ThumbnailManager(QObject):
    thumbnailReady = Signal(str, str)
    folderPreviewReady = Signal(str, list)

    def __init__(self, cache_dir: Path, parent=None):
        super().__init__(parent)
        self.cache_dir = cache_dir / "thumbs"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.thread_pool = QThreadPool.globalInstance()
        self.requested = set()
        self.requested_folders = set()
        self.folder_cache = {}

    def remove_thumbnail_for_path(self, file_path: str):
        try:
            manifest_path = self.cache_dir.parent / "thumb_manifest.json"
            if manifest_path.exists():
                with open(manifest_path, "r", encoding="utf-8") as f:
                    manifest = json.load(f)
                to_delete = [
                    k for k, v in manifest.items()
                    if v.get("src") == file_path or v.get("src", "").startswith(file_path + "/")
                ]
                for k in to_delete:
                    tp = self.cache_dir / k
                    if tp.exists():
                        try:
                            tp.unlink()
                        except OSError:
                            pass
                    manifest.pop(k, None)
                if to_delete:
                    with open(manifest_path, "w", encoding="utf-8") as f:
                        json.dump(manifest, f)
        except Exception:
            pass

    def get_existing_thumbnail(self, file_path: str):
        try:
            p = Path(file_path)
            if not p.exists():
                return ""
            mtime = p.stat().st_mtime
            key = f"{file_path}_{mtime}".encode("utf-8")
            hash_base = hashlib.md5(key).hexdigest()
            for ext in (".png", ".jpg"):
                thumb_path = self.cache_dir / f"{hash_base}{ext}"
                if thumb_path.exists() and thumb_path.stat().st_size > 0:
                    try:
                        os.utime(thumb_path, None)
                    except OSError:
                        pass
                    return str(thumb_path)
        except Exception:
            pass
        return ""

    def get_cached_folder_preview(self, folder_path: str):
        return self.folder_cache.get(folder_path, [])

    def request_thumbnail(self, file_path: str):
        if not file_path or file_path in self.requested:
            return

        ext = Path(file_path).suffix.lower()
        if ext not in IMAGE_EXTS and ext not in VIDEO_EXTS:
            return

        existing = self.get_existing_thumbnail(file_path)
        if existing:
            self.thumbnailReady.emit(file_path, existing)
            return

        self.requested.add(file_path)
        task = ThumbnailTask(file_path, self.cache_dir, self.thumbnailReady)
        self.thread_pool.start(task)

    def request_folder_preview(self, folder_path: str, show_hidden: bool = False):
        if not folder_path:
            return
        if folder_path in self.folder_cache:
            self.folderPreviewReady.emit(folder_path, self.folder_cache[folder_path])
            return
        if folder_path in self.requested_folders:
            return

        self.requested_folders.add(folder_path)
        task = FolderPreviewTask(folder_path, self.cache_dir, show_hidden, self._on_folder_task_done)
        self.thread_pool.start(task)

    def _on_folder_task_done(self, folder_path: str, previews: list):
        self.folder_cache[folder_path] = previews
        self.folderPreviewReady.emit(folder_path, previews)
