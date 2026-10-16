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
                dirs[:] = [d for d in dirs if not d.startswith(".")]
                try:
                    r_stat = os.stat(root)
                    cached_time = existing_index.get(root, {}).get("mtime", 0)
                    if r_stat.st_mtime != cached_time:
                        f_items = [f for f in files if not f.startswith(".")]
                        d_items = [d for d in dirs if not d.startswith(".")]
                        updated[root] = {"mtime": r_stat.st_mtime, "files": f_items, "dirs": d_items}
                except (PermissionError, OSError):
                    pass

        try:
            tmp_index = self.index_file.with_suffix(".tmp")
            with open(tmp_index, "w", encoding="utf-8") as f:
                json.dump(updated, f)
            os.replace(tmp_index, self.index_file)
        except Exception:
            pass

        try:
            if callable(self.finish_callback):
                self.finish_callback(updated)
        except RuntimeError:
            pass


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
        try:
            self.index_data = updated
            self.indexingCompleted.emit()
        except RuntimeError:
            pass

    def query(self, search_text: str, scope: str = "everywhere", current_dir: str = "", icon_resolver=None, thumb_resolver=None, size_formatter=None):
        if not search_text or not search_text.strip():
            self.searchResultsReady.emit([])
            return

        q = search_text.strip().lower()
        results = []
        seen_paths = set()
        max_results = 150

        def _make_entry(full_p: str, name: str, is_dir: bool):
            icon_val = "📁" if is_dir else "📄"
            type_val = "Folder" if is_dir else "File"
            if callable(icon_resolver):
                try:
                    icon_val, type_val = icon_resolver(Path(full_p), is_dir)
                except Exception:
                    pass
            thumb_val = ""
            if not is_dir and callable(thumb_resolver):
                try:
                    thumb_val = thumb_resolver(full_p)
                except Exception:
                    pass
            size_str = ""
            mod_str = ""
            try:
                st = os.stat(full_p)
                if not is_dir and callable(size_formatter):
                    size_str = size_formatter(max(0, int(st.st_size)))
            except OSError:
                pass
            return {
                "name": name,
                "path": full_p,
                "is_dir": is_dir,
                "icon": icon_val,
                "type": type_val,
                "thumb": thumb_val,
                "size": size_str,
                "modified": mod_str
            }

        # Scope 1: Search "here" (Live walk starting from current_dir)
        if scope == "here" and current_dir and current_dir not in ("recent://", "trash://", "favorites://") and os.path.isdir(current_dir):
            for root, dirs, files in os.walk(current_dir):
                dirs[:] = [d for d in dirs if not d.startswith(".")]
                for d in dirs:
                    if q in d.lower():
                        fp = os.path.join(root, d)
                        if fp not in seen_paths:
                            seen_paths.add(fp)
                            results.append(_make_entry(fp, d, True))
                            if len(results) >= max_results:
                                self.searchResultsReady.emit(results)
                                return
                for f in files:
                    if f.startswith("."):
                        continue
                    if q in f.lower():
                        fp = os.path.join(root, f)
                        if fp not in seen_paths:
                            seen_paths.add(fp)
                            results.append(_make_entry(fp, f, False))
                            if len(results) >= max_results:
                                self.searchResultsReady.emit(results)
                                return
            self.searchResultsReady.emit(results)
            return

        # Scope 2: Search "everywhere" across index_data (Folders first, then Files)
        for dir_path, meta in list(self.index_data.items()):
            dir_name = os.path.basename(dir_path)
            if dir_name and q in dir_name.lower() and dir_path not in seen_paths and os.path.exists(dir_path):
                seen_paths.add(dir_path)
                results.append(_make_entry(dir_path, dir_name, True))
                if len(results) >= max_results:
                    break

            for d in meta.get("dirs", []):
                if q in d.lower():
                    fp = os.path.join(dir_path, d)
                    if fp not in seen_paths and os.path.exists(fp):
                        seen_paths.add(fp)
                        results.append(_make_entry(fp, d, True))
                        if len(results) >= max_results:
                            break
            if len(results) >= max_results:
                break

            for f in meta.get("files", []):
                if q in f.lower():
                    fp = os.path.join(dir_path, f)
                    if fp not in seen_paths and os.path.exists(fp):
                        seen_paths.add(fp)
                        results.append(_make_entry(fp, f, False))
                        if len(results) >= max_results:
                            break
            if len(results) >= max_results:
                break

        self.searchResultsReady.emit(results)
