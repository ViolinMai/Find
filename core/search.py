import os
import re
import json
import threading
from pathlib import Path
from PySide6.QtCore import QObject, Signal, Slot, QRunnable, QThreadPool, QTimer


SKIP_INDEX_DIRS = {
    ".cache", ".local", ".config", ".git", "node_modules", "__pycache__",
    "target", "build", "dist", "venv", ".venv", ".cargo", ".rustup",
    ".mozilla", ".thunderbird", ".steam", "Steam", "steamapps", ".wine",
    "proc", "sys", "dev", "run", "tmp", "var", "usr", "lib", "lib64",
    "etc", "boot", "srv", "opt", "timeshift", "lost+found",
    "$RECYCLE.BIN", "System Volume Information"
}


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
                dirs[:] = [d for d in dirs if not d.startswith(".") and d not in SKIP_INDEX_DIRS and not d.startswith(".Trash")]
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
            tmp_index = self.index_file.with_suffix(f".tmp.{os.getpid()}")
            with open(tmp_index, "w", encoding="utf-8") as f:
                json.dump(updated, f)
            os.replace(tmp_index, self.index_file)
        except Exception:
            if tmp_index.exists():
                try:
                    tmp_index.unlink()
                except OSError:
                    pass

        try:
            if callable(self.finish_callback):
                self.finish_callback(updated)
        except RuntimeError:
            pass


class SearchQueryTask(QRunnable):
    def __init__(
        self,
        token: int,
        get_active_token_fn,
        index_snapshot: dict,
        search_text: str,
        scope: str,
        current_dir: str,
        match_mode: str,
        target_type: str,
        ext_filter: str,
        icon_resolver,
        thumb_resolver,
        size_formatter,
        ready_signal
    ):
        super().__init__()
        self.token = token
        self.get_active_token_fn = get_active_token_fn
        self.index_snapshot = index_snapshot
        self.search_text = search_text
        self.scope = scope
        self.current_dir = current_dir
        self.match_mode = match_mode
        self.target_type = target_type
        self.ext_filter = ext_filter
        self.icon_resolver = icon_resolver
        self.thumb_resolver = thumb_resolver
        self.size_formatter = size_formatter
        self.ready_signal = ready_signal

    def _is_cancelled(self) -> bool:
        return self.get_active_token_fn() != self.token

    def run(self):
        if self._is_cancelled():
            return
        raw_q = self.search_text.strip()
        if not raw_q:
            self.ready_signal.emit([])
            return

        q = raw_q.lower()
        results = []
        seen_paths = set()
        max_results = 200

        allowed_exts = set()
        if self.ext_filter and self.ext_filter.strip():
            for part in re.split(r'[,\s;]+', self.ext_filter.strip().lower()):
                clean_ext = part.strip().lstrip("*")
                if clean_ext:
                    if not clean_ext.startswith("."):
                        clean_ext = "." + clean_ext
                    allowed_exts.add(clean_ext)

        regex_obj = None
        if self.match_mode == "regex":
            try:
                regex_obj = re.compile(raw_q, re.IGNORECASE)
            except Exception:
                if not self._is_cancelled():
                    self.ready_signal.emit([])
                return

        def _matches_item(name: str, is_dir: bool) -> bool:
            if self.target_type == "folders" and not is_dir:
                return False
            if self.target_type == "files" and is_dir:
                return False
            if allowed_exts:
                if is_dir:
                    return False
                if Path(name).suffix.lower() not in allowed_exts:
                    return False

            n_low = name.lower()
            stem_low = Path(name).stem.lower() if not is_dir else n_low
            if self.match_mode == "exact":
                return n_low == q or stem_low == q
            elif self.match_mode == "starts_with":
                return n_low.startswith(q) or stem_low.startswith(q)
            elif self.match_mode == "ends_with":
                return n_low.endswith(q) or stem_low.endswith(q)
            elif self.match_mode == "regex" and regex_obj is not None:
                return bool(regex_obj.search(name))
            return q in n_low

        def _make_entry(full_p: str, name: str, is_dir: bool):
            icon_val = "📁" if is_dir else "📄"
            type_val = "Folder" if is_dir else "File"
            if callable(self.icon_resolver):
                try:
                    icon_val, type_val = self.icon_resolver(Path(full_p), is_dir)
                except Exception:
                    pass
            thumb_val = ""
            if not is_dir and callable(self.thumb_resolver):
                try:
                    thumb_val = self.thumb_resolver(full_p)
                except Exception:
                    pass
            size_str = ""
            try:
                if not is_dir and callable(self.size_formatter):
                    st = os.stat(full_p)
                    size_str = self.size_formatter(max(0, int(st.st_size)))
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
                "modified": ""
            }

        is_special_dir = (
            not self.current_dir
            or self.current_dir in ("recent://", "trash://", "favorites://", "mediahub://")
            or self.current_dir.startswith("analyzer://")
        )
        clean_curr = self.current_dir[11:] if (self.current_dir and self.current_dir.startswith("analyzer://")) else self.current_dir

        if self.scope == "current_only" and clean_curr and os.path.isdir(clean_curr):
            try:
                with os.scandir(clean_curr) as it:
                    for entry in it:
                        if self._is_cancelled():
                            return
                        if entry.name.startswith("."):
                            continue
                        is_d = entry.is_dir(follow_symlinks=False)
                        if _matches_item(entry.name, is_d):
                            seen_paths.add(entry.path)
                            results.append(_make_entry(entry.path, entry.name, is_d))
                            if len(results) >= max_results:
                                break
            except OSError:
                pass
            if not self._is_cancelled():
                self.ready_signal.emit(results)
            return

        if self.scope in ("here", "recursive") and clean_curr and not is_special_dir and os.path.isdir(clean_curr):
            for root, dirs, files in os.walk(clean_curr):
                if self._is_cancelled():
                    return
                dirs[:] = [d for d in dirs if not d.startswith(".") and d not in SKIP_INDEX_DIRS]
                for d in dirs:
                    if _matches_item(d, True):
                        fp = os.path.join(root, d)
                        if fp not in seen_paths:
                            seen_paths.add(fp)
                            results.append(_make_entry(fp, d, True))
                            if len(results) >= max_results:
                                if not self._is_cancelled():
                                    self.ready_signal.emit(results)
                                return
                for f in files:
                    if f.startswith("."):
                        continue
                    if _matches_item(f, False):
                        fp = os.path.join(root, f)
                        if fp not in seen_paths:
                            seen_paths.add(fp)
                            results.append(_make_entry(fp, f, False))
                            if len(results) >= max_results:
                                if not self._is_cancelled():
                                    self.ready_signal.emit(results)
                                return
            if not self._is_cancelled():
                self.ready_signal.emit(results)
            return

        for dir_path, meta in list(self.index_snapshot.items()):
            if self._is_cancelled():
                return
            dir_name = os.path.basename(dir_path)
            if dir_name and _matches_item(dir_name, True) and dir_path not in seen_paths:
                seen_paths.add(dir_path)
                results.append(_make_entry(dir_path, dir_name, True))
                if len(results) >= max_results:
                    break

            for d in meta.get("dirs", []):
                if _matches_item(d, True):
                    fp = os.path.join(dir_path, d)
                    if fp not in seen_paths:
                        seen_paths.add(fp)
                        results.append(_make_entry(fp, d, True))
                        if len(results) >= max_results:
                            break
            if len(results) >= max_results:
                break

            for f in meta.get("files", []):
                if _matches_item(f, False):
                    fp = os.path.join(dir_path, f)
                    if fp not in seen_paths:
                        seen_paths.add(fp)
                        results.append(_make_entry(fp, f, False))
                        if len(results) >= max_results:
                            break
            if len(results) >= max_results:
                break

        if not self._is_cancelled():
            self.ready_signal.emit(results)


class SearchManager(QObject):
    searchResultsReady = Signal(list)
    indexingCompleted = Signal()

    def __init__(self, cache_dir: Path, parent=None, load_on_init: bool = True):
        super().__init__(parent)
        self.index_file = cache_dir / "index_cache.json"
        self.cache_dir = cache_dir
        self.index_data = {}
        self._active_token = 0
        self._pending_args = None
        self.thread_pool = QThreadPool.globalInstance()

        self._debounce_timer = QTimer(self)
        self._debounce_timer.setSingleShot(True)
        self._debounce_timer.setInterval(160)
        self._debounce_timer.timeout.connect(self._execute_debounced_query)

        if load_on_init:
            self.thread_pool.start(self.load_index)

    def load_index(self):
        if self.index_file.exists():
            try:
                with open(self.index_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        self.index_data = data
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

    def query(
        self,
        search_text: str,
        scope: str = "recursive",
        current_dir: str = "",
        match_mode: str = "contains",
        target_type: str = "all",
        ext_filter: str = "",
        icon_resolver=None,
        thumb_resolver=None,
        size_formatter=None
    ):
        self._active_token += 1
        if not search_text or not search_text.strip():
            self._debounce_timer.stop()
            self.searchResultsReady.emit([])
            return

        self._pending_args = (
            self._active_token,
            search_text,
            scope,
            current_dir,
            match_mode,
            target_type,
            ext_filter,
            icon_resolver,
            thumb_resolver,
            size_formatter
        )
        self._debounce_timer.start()

    def _execute_debounced_query(self):
        if not self._pending_args:
            return
        (
            tok,
            search_text,
            scope,
            current_dir,
            match_mode,
            target_type,
            ext_filter,
            icon_resolver,
            thumb_resolver,
            size_formatter
        ) = self._pending_args
        task = SearchQueryTask(
            tok,
            lambda: self._active_token,
            self.index_data,
            search_text,
            scope,
            current_dir,
            match_mode,
            target_type,
            ext_filter,
            icon_resolver,
            thumb_resolver,
            size_formatter,
            self.searchResultsReady
        )
        self.thread_pool.start(task)
        return

    def _legacy_sync_query_unused(self):

        import re
        raw_q = search_text.strip()
        q = raw_q.lower()
        results = []
        seen_paths = set()
        max_results = 200

        allowed_exts = set()
        if ext_filter and ext_filter.strip():
            for part in re.split(r'[,\s;]+', ext_filter.strip().lower()):
                clean_ext = part.strip().lstrip("*")
                if clean_ext:
                    if not clean_ext.startswith("."):
                        clean_ext = "." + clean_ext
                    allowed_exts.add(clean_ext)

        regex_obj = None
        if match_mode == "regex":
            try:
                regex_obj = re.compile(raw_q, re.IGNORECASE)
            except Exception:
                self.searchResultsReady.emit([])
                return

        def _matches_item(name: str, is_dir: bool) -> bool:
            if target_type == "folders" and not is_dir:
                return False
            if target_type == "files" and is_dir:
                return False
            if allowed_exts:
                if is_dir:
                    return False
                if Path(name).suffix.lower() not in allowed_exts:
                    return False

            n_low = name.lower()
            stem_low = Path(name).stem.lower() if not is_dir else n_low
            if match_mode == "exact":
                return n_low == q or stem_low == q
            elif match_mode == "starts_with":
                return n_low.startswith(q) or stem_low.startswith(q)
            elif match_mode == "ends_with":
                return n_low.endswith(q) or stem_low.endswith(q)
            elif match_mode == "regex" and regex_obj is not None:
                return bool(regex_obj.search(name))
            return q in n_low

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

        is_special_dir = not current_dir or current_dir in ("recent://", "trash://", "favorites://", "mediahub://") or current_dir.startswith("analyzer://")
        clean_curr = current_dir[11:] if (current_dir and current_dir.startswith("analyzer://")) else current_dir

        # Scope 1: Current Folder Only (Non-recursive)
        if scope == "current_only" and clean_curr and os.path.isdir(clean_curr):
            try:
                with os.scandir(clean_curr) as it:
                    for entry in it:
                        if entry.name.startswith("."):
                            continue
                        is_d = entry.is_dir(follow_symlinks=False)
                        if _matches_item(entry.name, is_d):
                            seen_paths.add(entry.path)
                            results.append(_make_entry(entry.path, entry.name, is_d))
                            if len(results) >= max_results:
                                break
            except OSError:
                pass
            self.searchResultsReady.emit(results)
            return

        # Scope 2: Current Folder & Subfolders (Recursive live walk)
        if scope in ("here", "recursive") and clean_curr and not is_special_dir and os.path.isdir(clean_curr):
            for root, dirs, files in os.walk(clean_curr):
                dirs[:] = [d for d in dirs if not d.startswith(".")]
                for d in dirs:
                    if _matches_item(d, True):
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
                    if _matches_item(f, False):
                        fp = os.path.join(root, f)
                        if fp not in seen_paths:
                            seen_paths.add(fp)
                            results.append(_make_entry(fp, f, False))
                            if len(results) >= max_results:
                                self.searchResultsReady.emit(results)
                                return
            self.searchResultsReady.emit(results)
            return

        # Scope 3: Search "everywhere" across index_data
        for dir_path, meta in list(self.index_data.items()):
            dir_name = os.path.basename(dir_path)
            if dir_name and _matches_item(dir_name, True) and dir_path not in seen_paths and os.path.exists(dir_path):
                seen_paths.add(dir_path)
                results.append(_make_entry(dir_path, dir_name, True))
                if len(results) >= max_results:
                    break

            for d in meta.get("dirs", []):
                if _matches_item(d, True):
                    fp = os.path.join(dir_path, d)
                    if fp not in seen_paths and os.path.exists(fp):
                        seen_paths.add(fp)
                        results.append(_make_entry(fp, d, True))
                        if len(results) >= max_results:
                            break
            if len(results) >= max_results:
                break

            for f in meta.get("files", []):
                if _matches_item(f, False):
                    fp = os.path.join(dir_path, f)
                    if fp not in seen_paths and os.path.exists(fp):
                        seen_paths.add(fp)
                        results.append(_make_entry(fp, f, False))
                        if len(results) >= max_results:
                            break
            if len(results) >= max_results:
                break

        self.searchResultsReady.emit(results)
