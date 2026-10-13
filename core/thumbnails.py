import os
import random
import hashlib
import subprocess
import shutil
from pathlib import Path
from PySide6.QtCore import QObject, Signal, Slot, QRunnable, QThreadPool
from PIL import Image

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".ico"}
VIDEO_EXTS = {".mp4", ".mkv", ".webm", ".avi", ".mov", ".flv", ".m4v"}


class ThumbnailTask(QRunnable):
    def __init__(self, file_path: str, thumb_path: Path, ext: str, callback_signal):
        super().__init__()
        self.file_path = file_path
        self.thumb_path = thumb_path
        self.ext = ext
        self.callback_signal = callback_signal

    def run(self):
        try:
            p = Path(self.file_path)
            if not p.exists():
                return

            # 1. Processing Image Thumbnail with Full Alpha Support
            if self.ext in IMAGE_EXTS:
                try:
                    with Image.open(p) as img:
                        img.thumbnail((320, 320))
                        if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
                            img.save(str(self.thumb_path), "PNG", optimize=True)
                        else:
                            img.convert("RGB").save(str(self.thumb_path), "JPEG", quality=85)
                        self.callback_signal.emit(self.file_path, str(self.thumb_path))
                        return
                except Exception:
                    pass

            # 2. Processing Video Thumbnail with Random Frame from First Quarter
            if self.ext in VIDEO_EXTS and shutil.which("ffmpeg"):
                # Embedded Cover First
                cmd_cover = [
                    "ffmpeg", "-v", "quiet", "-y", "-i", str(p),
                    "-map", "0:v:1", "-vframes", "1",
                    "-vf", "scale='min(320,iw)':-1", str(self.thumb_path)
                ]
                res = subprocess.run(cmd_cover, timeout=2)
                if res.returncode == 0 and self.thumb_path.exists() and self.thumb_path.stat().st_size > 0:
                    self.callback_signal.emit(self.file_path, str(self.thumb_path))
                    return

                # Measure video duration
                duration = 20.0
                if shutil.which("ffprobe"):
                    try:
                        probe_cmd = [
                            "ffprobe", "-v", "error", "-show_entries", "format=duration",
                            "-of", "default=noprint_wrappers=1:nokey=1", str(p)
                        ]
                        out = subprocess.check_output(probe_cmd, timeout=1.5).decode().strip()
                        duration = float(out)
                    except Exception:
                        duration = 20.0

                # Pick random timestamp from the first quarter
                first_quarter = max(2.0, duration * 0.25)
                seek_time = random.uniform(1.0, first_quarter)

                cmd_frame = [
                    "ffmpeg", "-v", "quiet", "-y", "-ss", f"{seek_time:.2f}", "-i", str(p),
                    "-vframes", "1", "-vf", "scale='min(320,iw)':-1", str(self.thumb_path)
                ]
                res2 = subprocess.run(cmd_frame, timeout=3)
                if res2.returncode == 0 and self.thumb_path.exists():
                    self.callback_signal.emit(self.file_path, str(self.thumb_path))
                    return
        except Exception:
            pass


class ThumbnailManager(QObject):
    thumbnailReady = Signal(str, str)

    def __init__(self, cache_dir: Path, parent=None):
        super().__init__(parent)
        self.cache_dir = cache_dir / "thumbs"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.thread_pool = QThreadPool.globalInstance()
        self.requested = set()

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
                    return str(thumb_path)
        except Exception:
            pass
        return ""

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
        try:
            mtime = Path(file_path).stat().st_mtime
            key = f"{file_path}_{mtime}".encode("utf-8")
            hash_base = hashlib.md5(key).hexdigest()
            out_ext = ".png" if ext in {".png", ".ico"} else ".jpg"
            thumb_path = self.cache_dir / f"{hash_base}{out_ext}"
            task = ThumbnailTask(file_path, thumb_path, ext, self.thumbnailReady)
            self.thread_pool.start(task)
        except Exception:
            pass
