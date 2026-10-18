from PySide6.QtCore import Qt, QAbstractListModel, QModelIndex


class FileListModel(QAbstractListModel):
    NameRole = Qt.ItemDataRole.UserRole + 1
    PathRole = Qt.ItemDataRole.UserRole + 2
    IsDirRole = Qt.ItemDataRole.UserRole + 3
    SizeRole = Qt.ItemDataRole.UserRole + 4
    ModifiedRole = Qt.ItemDataRole.UserRole + 5
    CreatedRole = Qt.ItemDataRole.UserRole + 6
    IconRole = Qt.ItemDataRole.UserRole + 7
    TypeRole = Qt.ItemDataRole.UserRole + 8
    RawSizeRole = Qt.ItemDataRole.UserRole + 9
    RawModRole = Qt.ItemDataRole.UserRole + 10
    RawCreatedRole = Qt.ItemDataRole.UserRole + 11
    ThumbRole = Qt.ItemDataRole.UserRole + 12
    FolderPreviewsRole = Qt.ItemDataRole.UserRole + 13
    EpisodeNumRole = Qt.ItemDataRole.UserRole + 14
    ProgressRole = Qt.ItemDataRole.UserRole + 15
    IsWatchedRole = Qt.ItemDataRole.UserRole + 16
    IsNewRole = Qt.ItemDataRole.UserRole + 17
    IsMovieItemRole = Qt.ItemDataRole.UserRole + 18
    IsHdrRole = Qt.ItemDataRole.UserRole + 19
    EpisodeTitleRole = Qt.ItemDataRole.UserRole + 20
    OverviewRole = Qt.ItemDataRole.UserRole + 21
    RatingRole = Qt.ItemDataRole.UserRole + 22
    PosterRole = Qt.ItemDataRole.UserRole + 23
    SizeRatioRole = Qt.ItemDataRole.UserRole + 24
    PercentStrRole = Qt.ItemDataRole.UserRole + 25

    def __init__(self, parent=None):
        super().__init__(parent)
        self._entries = []
        self._path_to_row = {}

    def rowCount(self, parent=QModelIndex()):
        return len(self._entries)

    def data(self, index, role=Qt.ItemDataRole.DisplayRole):
        if not index.isValid() or not (0 <= index.row() < len(self._entries)):
            return None

        entry = self._entries[index.row()]
        if role == self.NameRole:
            return entry["name"]
        elif role == self.PathRole:
            return entry["path"]
        elif role == self.IsDirRole:
            return entry["is_dir"]
        elif role == self.SizeRole:
            return entry["size"]
        elif role == self.ModifiedRole:
            return entry["modified"]
        elif role == self.CreatedRole:
            return entry.get("created", "")
        elif role == self.IconRole:
            return entry["icon"]
        elif role == self.TypeRole:
            return entry["type"]
        elif role == self.RawSizeRole:
            return entry["raw_size"]
        elif role == self.RawModRole:
            return entry["raw_mod"]
        elif role == self.RawCreatedRole:
            return entry.get("raw_created", 0)
        elif role == self.ThumbRole:
            return entry.get("thumb", "")
        elif role == self.FolderPreviewsRole:
            return entry.get("folder_previews", [])
        elif role == self.EpisodeNumRole:
            return entry.get("episode_num", "")
        elif role == self.ProgressRole:
            return float(entry.get("progress", 0.0))
        elif role == self.IsWatchedRole:
            return bool(entry.get("is_watched", False))
        elif role == self.IsNewRole:
            return bool(entry.get("is_new", False))
        elif role == self.IsMovieItemRole:
            return bool(entry.get("is_movie_item", False))
        elif role == self.IsHdrRole:
            return bool(entry.get("is_hdr", False))
        elif role == self.EpisodeTitleRole:
            return str(entry.get("episode_title", ""))
        elif role == self.OverviewRole:
            return str(entry.get("overview", ""))
        elif role == self.RatingRole:
            return str(entry.get("rating", "")) if entry.get("rating") else ""
        elif role == self.PosterRole:
            return str(entry.get("poster", ""))
        elif role == self.SizeRatioRole:
            return float(entry.get("size_ratio", 0.0))
        elif role == self.PercentStrRole:
            return str(entry.get("percent_str", ""))
        return None

    def roleNames(self):
        return {
            self.NameRole: b"name",
            self.PathRole: b"path",
            self.IsDirRole: b"is_dir",
            self.SizeRole: b"size",
            self.ModifiedRole: b"modified",
            self.CreatedRole: b"created",
            self.IconRole: b"icon",
            self.TypeRole: b"type",
            self.RawSizeRole: b"raw_size",
            self.RawModRole: b"raw_mod",
            self.RawCreatedRole: b"raw_created",
            self.ThumbRole: b"thumb",
            self.FolderPreviewsRole: b"folder_previews",
            self.EpisodeNumRole: b"episode_num",
            self.ProgressRole: b"progress",
            self.IsWatchedRole: b"is_watched",
            self.IsNewRole: b"is_new",
            self.IsMovieItemRole: b"is_movie_item",
            self.IsHdrRole: b"is_hdr",
            self.EpisodeTitleRole: b"episode_title",
            self.OverviewRole: b"overview",
            self.RatingRole: b"rating",
            self.PosterRole: b"poster",
            self.SizeRatioRole: b"size_ratio",
            self.PercentStrRole: b"percent_str",
        }

    def set_entries(self, entries):
        self.beginResetModel()
        self._entries = entries
        self._path_to_row = {e["path"]: idx for idx, e in enumerate(entries)}
        self.endResetModel()

    def update_thumbnail(self, file_path, thumb_path):
        idx = self._path_to_row.get(file_path)
        if idx is not None and 0 <= idx < len(self._entries):
            self._entries[idx]["thumb"] = thumb_path
            model_idx = self.index(idx, 0)
            self.dataChanged.emit(model_idx, model_idx, [self.ThumbRole])

    def update_jellyfin_metadata(
        self,
        file_path: str,
        ep_title: str,
        overview: str,
        progress_val=None,
        is_watched_val=None,
        rating_val=None,
        poster_path: str = ""
    ):
        idx = self._path_to_row.get(file_path)
        if idx is not None and 0 <= idx < len(self._entries):
            changed_roles = []
            if ep_title and self._entries[idx].get("episode_title") != ep_title:
                self._entries[idx]["episode_title"] = ep_title
                changed_roles.append(self.EpisodeTitleRole)
            if overview and self._entries[idx].get("overview") != overview:
                self._entries[idx]["overview"] = overview
                changed_roles.append(self.OverviewRole)
            if rating_val is not None:
                r_str = str(rating_val) if rating_val else ""
                if self._entries[idx].get("rating") != r_str:
                    self._entries[idx]["rating"] = r_str
                    changed_roles.append(self.RatingRole)
            if poster_path and self._entries[idx].get("poster") != poster_path:
                self._entries[idx]["poster"] = poster_path
                changed_roles.append(self.PosterRole)
            if progress_val is not None:
                self._entries[idx]["progress"] = float(progress_val)
                changed_roles.append(self.ProgressRole)
            if is_watched_val is not None:
                self._entries[idx]["is_watched"] = bool(is_watched_val)
                if is_watched_val:
                    self._entries[idx]["is_new"] = False
                changed_roles.extend([self.IsWatchedRole, self.IsNewRole])
            if changed_roles:
                model_idx = self.index(idx, 0)
                self.dataChanged.emit(model_idx, model_idx, changed_roles)

    def update_hdr_status(self, file_path: str, is_hdr: bool):
        idx = self._path_to_row.get(file_path)
        if idx is not None and 0 <= idx < len(self._entries):
            if self._entries[idx].get("is_hdr") != bool(is_hdr):
                self._entries[idx]["is_hdr"] = bool(is_hdr)
                model_idx = self.index(idx, 0)
                self.dataChanged.emit(model_idx, model_idx, [self.IsHdrRole])

    def update_folder_previews(self, folder_path, previews):
        idx = self._path_to_row.get(folder_path)
        if idx is not None and 0 <= idx < len(self._entries):
            self._entries[idx]["folder_previews"] = previews
            model_idx = self.index(idx, 0)
            self.dataChanged.emit(model_idx, model_idx, [self.FolderPreviewsRole])

    def update_media_progress(self, file_path, progress_val, is_watched_val, is_new_val=None):
        idx = self._path_to_row.get(file_path)
        if idx is not None and 0 <= idx < len(self._entries):
            self._entries[idx]["progress"] = float(progress_val)
            self._entries[idx]["is_watched"] = bool(is_watched_val)
            if is_watched_val:
                self._entries[idx]["is_new"] = False
            elif is_new_val is not None:
                self._entries[idx]["is_new"] = bool(is_new_val)
            model_idx = self.index(idx, 0)
            self.dataChanged.emit(
                model_idx,
                model_idx,
                [self.ProgressRole, self.IsWatchedRole, self.IsNewRole]
            )

    def get_row_for_path(self, item_path: str) -> int:
        return self._path_to_row.get(item_path, -1)

    def get_entry_at(self, row: int):
        if 0 <= row < len(self._entries):
            return self._entries[row]
        return None

    def update_entry_size(self, item_path, size_str, raw_size=0):
        idx = self._path_to_row.get(item_path)
        if idx is not None and 0 <= idx < len(self._entries):
            self._entries[idx]["size"] = size_str
            if raw_size > 0:
                self._entries[idx]["raw_size"] = raw_size
            model_idx = self.index(idx, 0)
            self.dataChanged.emit(model_idx, model_idx, [self.SizeRole, self.RawSizeRole])
