import os
import json
from pathlib import Path
from PySide6.QtCore import QObject, Signal, Slot, QRunnable, QThreadPool


class IndexTask(QRunnable):
    def __init__(self, root_paths, index_file: Path, finish_callback):
        super().__init__()
        self.root_paths = root_paths
        self.index_file = index_file
        self.finish_callback = finish_callback

    def run(self):
        existing_index = {}
        if self.index_file.exists():
            try:
                with open(self.index_file, "r", encoding="utf-8") as f:
                    existing_index = json.load(f)
            except Exception:
                existing_index = {}

        updated = dict(existing_index)
        for base_p in self.root_paths:
            base_dir = Path(base_p)
            if not base_dir.exists():
                continue
            for root, dirs, files in os.walk(str(base_dir)):
                # Skip hidden directories
                dirs[:] = [d for d in dirs if not d.startswith(".")]
                try:
                    r_stat = os.stat(root)
                    cached_time = existing_index.get(root, {}).get("mtime", 0)
                    if r_stat.st_mtime != cached_time:
                        items = []
                        for f in files:
                            if not f.startswith("."):
                                items.append(f)
                        updated[root] = {"mtime": r_stat.st_mtime, "files": items}
                except (PermissionError, OSError):
                    pass

        try:
            with open(self.index_file, "w", encoding="utf-8") as f:
                json.dump(updated, f)
        except Exception:
            pass

        self.finish_callback(updated)


class SearchManager(QObject):
    searchResultsReady = Signal(list)
    indexingCompleted = Signal()

    def __init__(self, cache_dir: Path, parent=None):
        super().__init__(parent)
        self.index_file = cache_dir / "index_cache.json"
        self.cache_dir = cache_dir
        self.index_data = {}
        self.thread_pool = QThreadPool.globalInstance()
        self.load_index()

    def load_index(self):
        if self.index_file.exists():
            try:
                with open(self.index_file, "r", encoding="utf-8") as f:
                    self.index_data = json.load(f)
            except Exception:
                self.index_data = {}

    def build_incremental_index(self, root_paths):
        task = IndexTask(root_paths, self.index_file, self._on_index_done)
        self.thread_pool.start(task)

    def _on_index_done(self, updated):
        self.index_data = updated
        self.indexingCompleted.emit()

    def query(self, search_text: str):
        if not search_text:
            self.searchResultsReady.emit([])
            return

        q = search_text.lower()
        results = []
        count = 0
        for dir_path, meta in self.index_data.items():
            for f in meta.get("files", []):
                if q in f.lower():
                    results.append({
                        "name": f,
                        "path": os.path.join(dir_path, f),
                        "is_dir": False
                    })
                    count += 1
                    if count >= 100:  # Cap at 100 results for speed
                        break
            if count >= 100:
                break
        self.searchResultsReady.emit(results)
